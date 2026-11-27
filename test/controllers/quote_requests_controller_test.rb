require "test_helper"

class QuoteRequestsControllerTest < ActionDispatch::IntegrationTest
  setup { @s = create_sample_submission }

  def make_ready
    @s.confirm_all_verified!
    @s.approve!(:employee_count)
    @s.approve!(:years_in_business)
    @s.edit!(:annual_revenue, "4200000")
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
  end
end
