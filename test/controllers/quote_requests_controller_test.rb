require "test_helper"

class QuoteRequestsControllerTest < ActionDispatch::IntegrationTest
  setup { @s = create_sample_submission }

  def make_ready
    resolve_sample(@s)
    assert_empty @s.build_submission!
  end

  test "channel is refused with 422 when the submission is not ready" do
    %w[api portal email].each do |channel|
      post submission_quote_requests_path(@s), params: { channel: channel }
      assert_response :unprocessable_entity
    end
    assert_equal 0, QuoteRequest.count
  end

  test "channel is refused when the stored submission JSON no longer passes the schema" do
    make_ready
    @s.update_columns(submission_json: @s.submission_json.merge("extra" => 1))
    post submission_quote_requests_path(@s), params: { channel: "api" }
    assert_response :unprocessable_entity
    assert_match "fails the schema", response.body
  end

  test "running a channel prepends a quote request row via Turbo Stream" do
    make_ready
    post submission_quote_requests_path(@s), params: { channel: "api" },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_select "turbo-stream[action=prepend][target=quote_requests] td", "Acme Insurance"
    assert_select "turbo-stream[action=remove][target=quote_requests_empty]"
    # The test environment has no carrier to reach, so the channel records a failure instead of raising.
    assert_equal "failed", @s.quote_requests.first.status
  end

  test "email rows show the sent email, with the attachment linking to the stored PDF" do
    make_ready
    post submission_quote_requests_path(@s), params: { channel: "email" },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }
    qr = @s.quote_requests.first
    sent = qr.request_data
    path = document_submission_quote_request_path(@s, qr)
    assert_select "turbo-stream[target=quote_requests] button.exchange-toggle", "Sent"
    assert_select "turbo-stream[target=quote_requests] tr.exchange-row td[colspan=7] .exchange" do
      assert_select "dt", %w[From To Subject Date].size
      assert_select "dt + dd", sent["from"]
      assert_select "dd", "submissions@northwind.test"
      assert_select "dd", sent["subject"]
      assert_select "dd", sent["date"]
      assert_select "a[href=?]", path, sent["attachment"]
      assert_select "pre", /Please find attached a commercial insurance application/
    end
    assert_select "a", text: "View sent PDF", count: 0
    assert_select ".exchange .exchange-label", text: "Received", count: 0

    get path
    assert_response :success
    assert_equal "application/pdf", response.media_type
    assert_match(/\Ainline/, response.headers["Content-Disposition"])
    assert_equal ActionMailer::Base.deliveries.last.attachments.first.body.decoded.b, response.body.b
  end

  test "API rows show what was sent and received" do
    make_ready
    @s.quote_requests.create!(channel: "api", carrier: "Acme Insurance", status: "quoted",
                              request_body: "POST /quotes\n\n{}", response_body: "HTTP 201\n\n{\"premium\": 1}")
    get ready_submission_path(@s)
    assert_select "button.exchange-toggle", "Sent / received"
    assert_select "tr.exchange-row .exchange pre", /POST \/quotes/
    assert_select "tr.exchange-row .exchange pre", /HTTP 201/
  end

  test "portal rows show steps, filled fields and scraped values, with HTML escaped" do
    make_ready
    @s.quote_requests.create!(channel: "portal", carrier: "Beacon Mutual", status: "quoted",
      request_body: { steps: ["GET /mock_carriers/beacon/login → 200", "Filled 1 fields"],
                      filled: [{ label: "Tax ID No.", name: "tax_id_no", value: "82-6150347", source: "applicant.fein" }],
                      coverages: { ticked: [{ name: "general liability", label: "General Liability" }], unmatched: ["cyber"] } }.to_json,
      response_body: { scraped: [{ label: "Reference", value: "BCN-1", html: "<tr><th>Reference</th><td>BCN-1</td></tr><script>alert(1)</script>" }] }.to_json)
    get ready_submission_path(@s)
    assert_select "button.exchange-toggle", "Steps / scraped"
    assert_select "tr.exchange-row .exchange pre", /GET \/mock_carriers\/beacon\/login → 200\nFilled 1 fields/
    assert_select "tr.exchange-row .exchange table.exchange-table td", "Tax ID No."
    assert_select "tr.exchange-row .exchange table.exchange-table td code", "applicant.fein"
    assert_select "tr.exchange-row .exchange li", "Ticked: General Liability (general liability)"
    assert_select "tr.exchange-row .exchange li", "Unmatched: cyber (no checkbox)"
    assert_select "tr.exchange-row .exchange .scraped-value", "Reference: BCN-1"
    # The snippet is shown as text, never rendered as HTML.
    assert_select "tr.exchange-row .exchange pre", "<tr><th>Reference</th><td>BCN-1</td></tr><script>alert(1)</script>"
    assert_includes response.body, "&lt;script&gt;alert(1)&lt;/script&gt;"
    assert_select "tr.exchange-row .exchange script", count: 0
  end

  test "portal rows that stopped early have no scraped section" do
    make_ready
    @s.quote_requests.create!(channel: "portal", carrier: "Beacon Mutual", status: "failed",
      request_body: { steps: ["Stopped: Coverage 'cyber' not available on Beacon portal"], filled: [], coverages: {} }.to_json)
    get ready_submission_path(@s)
    assert_select "tr.exchange-row .exchange pre", /Stopped: Coverage/
    assert_select "tr.exchange-row .exchange .exchange-label", text: "Scraped", count: 0
  end

  test "expanded content sits in a hidden full-width row directly beneath its summary row" do
    make_ready
    qr = @s.quote_requests.create!(channel: "api", carrier: "Acme Insurance", status: "quoted",
                                   request_body: "POST /quotes\n\n{}", response_body: "HTTP 201")
    get ready_submission_path(@s)
    columns = css_select(".quote-requests thead th").size
    assert_select "tr#quote_request_#{qr.id} td", columns
    assert_select "tr#quote_request_#{qr.id} td pre", 0
    assert_select "tr#quote_request_#{qr.id} button.exchange-toggle[aria-controls=?][aria-expanded=false]", "details_quote_request_#{qr.id}"
    assert_select "tr#quote_request_#{qr.id} + tr#details_quote_request_#{qr.id}.exchange-row[hidden]" do
      assert_select "td", 1
      assert_select "td[colspan=?] pre", columns.to_s, /POST \/quotes/
    end
  end

  test "times show in Eastern with the full ISO timestamp on hover" do
    make_ready
    @s.quote_requests.create!(channel: "email", carrier: "Northwind Specialty", status: "sent",
                              created_at: Time.utc(2026, 11, 27, 0, 12, 5))
    get ready_submission_path(@s)
    assert_select ".quote-requests thead th", "Requested"
    assert_select "td time[datetime=?][title=?]", "2026-11-26T19:12:05-05:00", "2026-11-26T19:12:05-05:00", "Nov 26, 7:12 PM"
  end

  test "rows without a document have no PDF link and 404" do
    make_ready
    qr = @s.quote_requests.create!(channel: "api", carrier: "Acme Insurance", status: "quoted")
    get ready_submission_path(@s)
    assert_select "tr.exchange-row .exchange a", count: 0
    get document_submission_quote_request_path(@s, qr)
    assert_response :not_found
  end

  test "unknown channel is 404" do
    make_ready
    post submission_quote_requests_path(@s), params: { channel: "fax" }
    assert_response :not_found
  end

  test "ready page has the three channel buttons and lists quote requests" do
    make_ready
    @s.quote_requests.create!(channel: "api", carrier: "Acme Insurance", status: "quoted", premium: 18_450, reference: "ACM-1")
    get ready_submission_path(@s)
    assert_select "form[action=?] button", submission_quote_requests_path(@s), 3
    assert_select "button", "Get quote via Acme API"
    assert_select "button", "Get quote via Beacon portal"
    assert_select "button", "Email submission to Northwind"
    assert_select "#quote_requests tr", 1
    assert_select "#quote_requests td", "$18,450"
    assert_select "tr.exchange-row", 0
    assert_select "button.exchange-toggle", 0
  end
end
