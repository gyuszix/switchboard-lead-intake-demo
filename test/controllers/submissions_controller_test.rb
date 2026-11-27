require "test_helper"

class SubmissionsControllerTest < ActionDispatch::IntegrationTest
  test "paste page renders with sample buttons" do
    get root_path
    assert_response :success
    assert_select "textarea[name=transcript]"
    assert_select "a.button", 3
    assert_equal [ "Northgate Dental (happy path)", "Hudson Millwork (AI caught)", "Lumen Analytics (channels differ)" ],
                 css_select("a.button").map { _1.text.strip }
  end

  test "load sample fills the textarea" do
    get root_path(sample: "northgate_dental")
    assert_select "textarea", text: /Northgate Dental Studio PC/
  end

  test "extract creates a categorised submission and redirects to review" do
    transcript = "Client: The zip code is 60614."
    fields = { "zip" => { "value" => "60614", "source_quote" => "The zip code is 60614.", "all_mentions" => [] } }
    stub_extractor(fields) do
      assert_difference("Submission.count") { post submissions_path, params: { transcript: transcript } }
    end
    submission = Submission.last
    assert_redirected_to submission_path(submission)
    assert_equal "verified", submission.field(:zip)["category"]
    assert_equal "needs_approval", submission.field(:fein)["category"]
    assert_not submission.used_fixtures
  end

  test "blank transcript is rejected" do
    assert_no_difference("Submission.count") { post submissions_path, params: { transcript: " " } }
    assert_response :unprocessable_entity
  end
end
