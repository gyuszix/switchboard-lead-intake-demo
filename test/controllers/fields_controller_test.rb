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

  test "confirm all responds with streams for verified rows and counter" do
    patch confirm_all_submission_path(@s), headers: stream_headers
    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_select "turbo-stream[action=replace][target=field_fein]"
    assert_select "turbo-stream[target=field_employee_count]", 0
    assert_select "turbo-stream[target=review_status]", /11 of 13/
    assert_nil @s.reload.field(:employee_count)["resolution"]
  end

  test "edit with an invalid value returns 422 and shows the error" do
    patch submission_field_path(@s, "annual_revenue"), params: { value: "lots" }, headers: stream_headers
    assert_response :unprocessable_entity
    assert_select "turbo-stream[target=field_annual_revenue]", /must be a number/
    assert_nil @s.reload.field(:annual_revenue)["resolution"]
  end

  test "edit with a valid value resolves the row" do
    patch submission_field_path(@s, "annual_revenue"), params: { value: "4200000" }, headers: stream_headers
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

  test "unknown field is 404" do
    patch approve_submission_field_path(@s, "favourite_colour"), headers: stream_headers
    assert_response :not_found
  end
end
