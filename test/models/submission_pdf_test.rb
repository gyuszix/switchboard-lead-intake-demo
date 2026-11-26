require "test_helper"

class SubmissionPdfTest < ActiveSupport::TestCase
  setup do
    @s = create_sample_submission
    @s.confirm_all_verified!
    @s.edit!(:annual_revenue, "4200000")
    @s.mark_not_provided!(:employee_count)
    @pdf = SubmissionPdf.new(@s, generated_on: Date.new(2026, 11, 26))
  end

  test "fixed sections in fixed order with every field present" do
    assert_equal %w[Applicant Operations Coverage Contact], @pdf.sections.map(&:first)
    labels = @pdf.sections.flat_map { _2.map(&:first) }
    assert_equal ["Business name", "FEIN", "Address", "ZIP", "Years in business", "Industry description",
                  "NAICS code", "Annual revenue", "Employee count", "Coverage types", "Effective date",
                  "Contact name", "Contact email"], labels
  end

  test "formats revenue, dates and empty fields" do
    values = @pdf.sections.flat_map(&:last).to_h
    assert_equal "$4,200,000", values["Annual revenue"]
    assert_equal "2027-02-15", values["Effective date"]
    assert_equal "Not provided", values["Employee count"]
  end

  test "renders a PDF" do
    assert @pdf.render.start_with?("%PDF")
  end
end
