require "test_helper"

class SubmissionPdfTest < ActiveSupport::TestCase
  setup do
    @s = create_ready_submission
    # A null in the JSON still prints, as "Not provided".
    @s.update_columns(submission_json: @s.submission_json.deep_merge("operations" => { "employee_count" => nil }))
    @pdf = SubmissionPdf.new(@s, generated_on: Date.new(2026, 11, 26))
  end

  test "fixed sections in fixed order with every field present" do
    assert_equal %w[Applicant Operations Coverage Contact], @pdf.sections.map(&:first)
    labels = @pdf.sections.flat_map { _2.map(&:first) }
    assert_equal ["Business name", "FEIN", "Address", "ZIP", "Years in business", "Industry description",
                  "NAICS code", "Annual revenue", "Employee count", "Coverage types", "Effective date",
                  "Contact name", "Contact email"], labels
  end

  test "formats revenue, dates, coverages and empty fields from the submission JSON" do
    values = @pdf.sections.flat_map(&:last).to_h
    assert_equal "general liability, property, workers comp", values["Coverage types"]
    assert_equal "$5,400,000", values["Annual revenue"]
    assert_equal "2027-04-01", values["Effective date"]
    assert_equal "Not provided", values["Employee count"]
  end

  test "renders a PDF" do
    assert @pdf.render.start_with?("%PDF")
  end
end
