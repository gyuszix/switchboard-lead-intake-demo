require "test_helper"

class PortalChannelTest < ActiveSupport::TestCase
  def page(name)
    html = file_fixture("beacon/#{name}.html").read
    Mechanize::Page.new(URI("http://beacon.test/"), { "content-type" => "text/html" }, html, 200, Mechanize.new)
  end

  def portal = Channels::Portal.new

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
  end
end
