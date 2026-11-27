require "test_helper"

class BuildFlowTest < ActionDispatch::IntegrationTest
  setup { @s = create_sample_submission }

  def resolve_all(revenue: "4200000")
    @s.confirm_all_verified!
    @s.approve!(:employee_count)
    @s.approve!(:years_in_business)
    @s.edit!(:annual_revenue, revenue)
  end

  test "build is refused with 422 while any field is unresolved" do
    @s.confirm_all_verified!
    post build_submission_path(@s)
    assert_response :unprocessable_entity
    assert_nil @s.reload.submission_json
  end

  test "build button is disabled until everything is resolved" do
    get submission_path(@s)
    assert_select "#review_status button[disabled]", "Approve and build submission"
    resolve_all
    get submission_path(@s)
    assert_select "#review_status form[action=?] button:not([disabled])", build_submission_path(@s)
  end

  test "invalid submission is not saved and errors are shown on the review page" do
    @s.confirm_all_verified!
    @s.approve!(:employee_count)
    @s.approve!(:years_in_business)
    @s.mark_not_provided!(:annual_revenue)

    post build_submission_path(@s)
    assert_response :unprocessable_entity
    assert_select ".error-banner li", "Annual revenue: Required for submission"
    assert_select "#field_annual_revenue.build-error"
    assert_select "#field_fein.build-error", 0
    @s.reload
    assert_nil @s.submission_json
    assert_nil @s.ready_at
  end

  test "valid submission sets submission_json and ready_at and shows the ready page" do
    resolve_all
    post build_submission_path(@s)
    assert_redirected_to ready_submission_path(@s)
    @s.reload
    assert @s.ready_at.present?
    assert_equal 4_200_000, @s.submission_json.dig("operations", "annual_revenue")

    follow_redirect!
    assert_select "pre", /"fein": "82-6150347"/
    assert_select "#quote_requests_empty"

    get submission_path(@s)
    assert_select "#review_status a[href=?]", ready_submission_path(@s)
  end

  test "editing a field after ready clears the built submission" do
    resolve_all
    post build_submission_path(@s)
    assert @s.reload.ready?

    patch submission_field_path(@s, "zip"), params: { value: "60174" },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    @s.reload
    assert_nil @s.submission_json
    assert_nil @s.ready_at

    get ready_submission_path(@s)
    assert_redirected_to submission_path(@s)
  end

  test "the PDF download route is gone" do
    assert_not Rails.application.routes.url_helpers.respond_to?(:pdf_submission_path)
  end
end
