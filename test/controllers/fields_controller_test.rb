require "test_helper"

class FieldsControllerTest < ActionDispatch::IntegrationTest
  setup { @s = create_sample_submission }

  def stream_headers = { "Accept" => "text/vnd.turbo-stream.html, text/html" }

  test "review page lists both sections" do
    get submission_path(@s)
    assert_response :success
    assert_select ".badge.green", "Verified"
    assert_select ".badge.amber", "Needs approval"
    assert_select "turbo-frame.field-row", 13
    assert_select "#review_status", /0 of 13/
    assert_select "[data-controller=edit-toggle]", 13
  end

  test "review page renders the transcript and links quotes to their line" do
    get submission_path(@s)
    lines = @s.transcript.split("\n")
    assert_select "details.transcript:not([open]) summary", "Show full transcript"
    assert_select ".transcript-line", lines.size
    assert_select "#line-1 strong", "Broker:"

    name_line = "line-#{lines.index { _1.include?("Hudson Millwork LLC.") } + 1}"
    assert_select "#field_business_name a.quote-link[href=?][data-transcript-line-param=?]", "##{name_line}", name_line
    assert_select "##{name_line}", /Hudson Millwork LLC/
  end

  test "a quote with no matching line is not clickable" do
    @s.update_field(:zip, "source_quote" => "a quote that is nowhere in the call")
    @s.save!
    get submission_path(@s)
    assert_select "#field_zip .quote", /nowhere in the call/
    assert_select "#field_zip a.quote-link", 0
  end

  test "confirm all responds with streams for verified rows and counter" do
    patch confirm_all_submission_path(@s), headers: stream_headers
    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_select "turbo-stream[action=replace][target=field_business_name]"
    assert_select "turbo-stream[target=field_employee_count]", 0
    assert_select "turbo-stream[target=review_status]", /5 of 13/
    assert_nil @s.reload.field(:employee_count)["resolution"]
  end

  test "edit with an invalid value returns 422 and shows the error" do
    patch submission_field_path(@s, "annual_revenue"), params: { value: "lots" }, headers: stream_headers
    assert_response :unprocessable_entity
    assert_select "turbo-stream[target=field_annual_revenue]", /must be a number/
    assert_nil @s.reload.field(:annual_revenue)["resolution"]
  end

  test "edit with a valid value resolves the row" do
    patch submission_field_path(@s, "annual_revenue"), params: { value: "5400000" }, headers: stream_headers
    assert_response :success
    assert_equal "edited", @s.reload.field(:annual_revenue)["resolution"]
  end

  test "approve on an invalid value is refused" do
    patch approve_submission_field_path(@s, "annual_revenue"), headers: stream_headers
    assert_response :unprocessable_entity
  end

  test "mark not provided" do
    patch not_provided_submission_field_path(@s, "employee_count"), headers: stream_headers
    assert_response :success
    assert_equal "not_provided", @s.reload.field(:employee_count)["resolution"]
  end

  test "verified rows have an edit action and a verified badge" do
    get submission_path(@s)
    assert_select "#field_business_name .badge.green", "Verified"
    assert_select "#field_business_name button", "Edit"
    assert_select "#field_business_name form[action=?]", approve_submission_field_path(@s, "business_name"), 0
  end

  test "editing a verified field swaps the badge and keeps the quote" do
    patch submission_field_path(@s, "business_name"), params: { value: "Hudson Millwork Inc" }, headers: stream_headers
    assert_response :success
    assert_select "turbo-stream[target=field_business_name]" do
      assert_select ".badge.blue", "Edited by broker"
      assert_select ".badge.green", 0
      assert_select ".quote", /Hudson Millwork LLC/
    end
  end

  test "unknown field is 404" do
    patch approve_submission_field_path(@s, "favourite_colour"), headers: stream_headers
    assert_response :not_found
  end
end
