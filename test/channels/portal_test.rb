require "test_helper"

class PortalChannelTest < ActiveSupport::TestCase
  def page(name)
    html = file_fixture("beacon/#{name}.html").read
    Mechanize::Page.new(URI("http://beacon.test/"), { "content-type" => "text/html" }, html, 200, Mechanize.new)
  end

  def portal = Channels::Portal.new

  LOGIN_PAGE = <<~HTML
    <html><body><form id="login" action="/mock_carriers/beacon/login" method="post">
      <input type="text" name="username"><input type="password" name="password">
    </form></body></html>
  HTML

  # Serves the Beacon HTML fixtures over real HTTP, so the bot runs end to end.
  # Logging in sets a session cookie and redirects, like the mock carrier.
  def with_beacon(result)
    pages = { "app_form" => file_fixture("beacon/app_form.html").read, "result" => file_fixture("beacon/#{result}.html").read }
    html = ->(body) { [200, { "content-type" => "text/html" }, [body]] }
    app = lambda do |env|
      req = Rack::Request.new(env)
      case [req.request_method, req.path]
      in ["GET", "/mock_carriers/beacon/login"] then html.(LOGIN_PAGE)
      in ["POST", "/mock_carriers/beacon/login"] if req.POST["password"] == "beacon-demo"
        [302, { "location" => "/mock_carriers/beacon/applications/new", "set-cookie" => "_beacon_session=cookie-secret-123; path=/" }, []]
      in ["GET", "/mock_carriers/beacon/applications/new"] then html.(pages["app_form"])
      in ["POST", "/mock_carriers/beacon/applications"] then html.(pages["result"])
      else [404, {}, []]
      end
    end
    server = Puma::Server.new(app, nil, min_threads: 0, max_threads: 2, log_writer: Puma::LogWriter.null)
    server.add_tcp_listener("127.0.0.1", 0)
    server.run
    yield "http://127.0.0.1:#{server.connected_ports.first}"
  ensure
    server&.stop(true)
  end

  # The IT services sample asks for cyber, which Beacon doesn't offer; these
  # coverages all have checkboxes.
  def beacon_ready_submission
    s = create_ready_submission
    s.update_columns(submission_json: s.submission_json.deep_merge("coverage" => { "coverage_types" => ["general liability", "professional liability"] }))
    s
  end

  test "maps the submission to Beacon field names and formats" do
    json = create_ready_submission.submission_json
    assert_equal({
      "insured_legal_entity" => "Brightpath IT Solutions Inc", "tax_id_no" => "82-6150347",
      "street_address" => "400 Commerce Drive, Suite 210, Schaumburg, Illinois", "zip_code" => "60173",
      "naics" => "541512", "gross_annual_sales" => "4,200,000", "number_of_employees" => "45",
      "effective_date" => "02/15/2027"
    }, portal.form_values(json))
  end

  test "ticks coverage checkboxes by label text, translating synonyms" do
    p = page("app_form")
    form = p.form_with(id: "new_application")
    portal.tick_coverages(p, form, ["General liability", "workers compensation"])
    assert_equal %w[general_liability workers_comp], form.checkboxes.select(&:checked?).map(&:value)
  end

  test "stops on a coverage with no checkbox" do
    p = page("app_form")
    error = assert_raises(Channels::Portal::Failure) { portal.tick_coverages(p, p.form_with(id: "new_application"), ["cyber liability"]) }
    assert_equal "Coverage 'cyber liability' not available on Beacon portal", error.message
  end

  test "parses result pages" do
    assert_equal({ status: "quoted", reference: "BCN-722916", premium: 3_825, message: "Quoted via Beacon portal" },
                 portal.parse_result(page("quoted")))
    assert_equal({ status: "declined", message: "flood not offered" }, portal.parse_result(page("declined")))
    assert_equal({ status: "referred", message: "Requires underwriter review" }, portal.parse_result(page("referred")))
    assert_equal({ status: "failed", message: "Beacon rejected the form: tax_id_no must be in the format 12-3456789; " \
                                              "gross_annual_sales enter an amount like 950,000" },
                 portal.parse_result(page("errors")))
    assert_equal({ status: "failed", message: "Unrecognised result page from Beacon portal" }, portal.parse_result(page("app_form")))
  end

  test "unreachable portal is failed, never raised" do
    qr = Channels::Portal.new(base_url: "http://127.0.0.1:9").call(create_ready_submission)
    assert_equal "failed", qr.status
    assert_match(/Could not connect to Beacon portal/, qr.message)
    assert_equal ["GET /mock_carriers/beacon/login → no response", "Stopped: #{qr.message}"], qr.request_data["steps"]
    assert_nil qr.response_body
  end

  test "records each step, the filled fields and ticked coverages" do
    qr = with_beacon("quoted") { Channels::Portal.new(base_url: _1).call(beacon_ready_submission) }
    assert_equal "quoted", qr.status
    sent = qr.request_data
    assert_equal ["GET /mock_carriers/beacon/login → 200", "POST /mock_carriers/beacon/login → 302",
                  "GET /mock_carriers/beacon/applications/new → 200", "Logged in as broker",
                  "Filled 8 fields", "Ticked 2 coverages", "POST /mock_carriers/beacon/applications → 200"], sent["steps"]
    assert_equal 8, sent["filled"].size
    assert_includes sent["filled"], { "label" => "Tax ID No.", "name" => "tax_id_no", "value" => "82-6150347", "source" => "applicant.fein" }
    assert_includes sent["filled"], { "label" => "Gross Annual Sales", "name" => "gross_annual_sales", "value" => "4,200,000",
                                      "source" => "operations.annual_revenue" }
    assert_equal [{ "name" => "general liability", "label" => "General Liability" },
                  { "name" => "professional liability", "label" => "Professional Liability" }], sent["coverages"]["ticked"]
    assert_empty sent["coverages"]["unmatched"]
  end

  test "every scraped value comes with the HTML it was read from" do
    qr = with_beacon("quoted") { Channels::Portal.new(base_url: _1).call(beacon_ready_submission) }
    scraped = qr.response_data["scraped"]
    assert_equal [["Status", "quoted"], ["Reference", "BCN-722916"], ["Premium", 3825]], scraped.map { [_1["label"], _1["value"]] }
    assert_equal "<tr>\n<th>Premium</th>\n<td>$3,825.00</td>\n</tr>", scraped.last["html"]
    scraped.each { assert _1["html"].start_with?("<tr>") }

    p = portal
    p.parse_result(page("declined"))
    assert_equal %w[Status Reason], p.record[:scraped].map { _1[:label] }
    assert p.record[:scraped].all? { _1[:html].include?("alert-error") }

    p = portal
    p.parse_result(page("errors"))
    assert_equal ["Error on tax_id_no", "Error on gross_annual_sales"], p.record[:scraped].map { _1[:label] }
    assert p.record[:scraped].all? { _1[:html].start_with?('<div class="field-error"') && _1[:html].length <= 300 }
  end

  test "never records the password or the session cookie" do
    qr = with_beacon("quoted") { Channels::Portal.new(base_url: _1).call(beacon_ready_submission) }
    stored = qr.attributes.values.join(" ")
    refute_includes stored, "beacon-demo"
    refute_includes stored, "cookie-secret-123"
  end

  test "a run that stops early records steps up to the failure and nothing scraped" do
    qr = with_beacon("quoted") { Channels::Portal.new(base_url: _1).call(create_ready_submission) }
    assert_equal "failed", qr.status
    sent = qr.request_data
    assert_equal ["Logged in as broker", "Filled 8 fields", "Stopped: Coverage 'cyber liability' not available on Beacon portal"],
                 sent["steps"].last(3)
    refute sent["steps"].any? { _1.include?("/applications →") || _1.start_with?("POST /mock_carriers/beacon/applications") }
    assert_equal ["cyber liability"], sent["coverages"]["unmatched"]
    assert_nil qr.response_body
  end
end
