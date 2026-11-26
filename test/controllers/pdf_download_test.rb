require "test_helper"

class PdfDownloadTest < ActionDispatch::IntegrationTest
  setup { @s = create_sample_submission }

  test "download is refused with 422 while any field is unresolved" do
    @s.confirm_all_verified!
    get pdf_submission_path(@s)
    assert_response :unprocessable_entity
    assert_not_equal "application/pdf", response.media_type
  end

  test "download button is disabled until everything is resolved" do
    get submission_path(@s)
    assert_select "#review_status button[disabled]", "Download PDF"
    assert_select "#review_status a", 0
  end

  test "download works once every field is resolved" do
    @s.confirm_all_verified!
    @s.approve!(:employee_count)
    @s.approve!(:years_in_business)
    @s.edit!(:annual_revenue, "4200000")
    get pdf_submission_path(@s)
    assert_response :success
    assert_equal "application/pdf", response.media_type
    assert response.body.start_with?("%PDF")

    get submission_path(@s)
    assert_select "#review_status a[href=?]", pdf_submission_path(@s), "Download PDF"
  end
end
