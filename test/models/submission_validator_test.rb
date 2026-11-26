require "test_helper"

class SubmissionValidatorTest < ActiveSupport::TestCase
  def valid_json
    {
      "schema_version" => "1",
      "submission_id" => 7,
      "built_at" => "2026-11-26T12:00:00Z",
      "applicant" => { "business_name" => "Golden Crust Bakery LLC", "fein" => "36-4829175",
                       "address" => "2150 North Halsted Street, Chicago, Illinois", "zip" => "60614", "years_in_business" => 9 },
      "operations" => { "industry_description" => "retail bakery", "naics_code" => "311811",
                        "annual_revenue" => 850_000, "employee_count" => 14 },
      "coverage" => { "coverage_types" => ["general liability", "commercial property"], "effective_date" => "2027-01-01" },
      "contact" => { "contact_name" => "Maria Lopez", "contact_email" => "maria@goldencrustbakery.com" }
    }
  end

  def errors_for(json) = SubmissionValidator.new.call(json).map { [_1.field, _1.message] }

  test "valid submission passes" do
    assert SubmissionValidator.new.valid?(valid_json)
  end

  test "missing field" do
    json = valid_json.tap { _1["applicant"].delete("zip") }
    assert_equal [["zip", "Required for submission"]], errors_for(json)
  end

  test "null field" do
    json = valid_json.tap { _1["contact"]["contact_email"] = nil }
    assert_equal [["contact_email", "Required for submission"]], errors_for(json)
  end

  test "bad pattern" do
    json = valid_json.tap { _1["applicant"]["fein"] = "47-391205588" }
    assert_equal [["fein", "FEIN must look like 12-3456789"]], errors_for(json)
  end

  test "wrong type" do
    json = valid_json.tap { _1["operations"]["annual_revenue"] = "four point two million" }
    assert_equal [["annual_revenue", "Annual revenue must be a whole number of at least 1"]], errors_for(json)
  end

  test "extra property" do
    json = valid_json.tap { _1["contact"]["phone"] = "555-0100" }
    assert_equal [["phone", "Unexpected field, not part of the submission schema"]], errors_for(json)
  end

  test "format and list checks" do
    json = valid_json.tap do
      _1["coverage"]["effective_date"] = "next spring"
      _1["coverage"]["coverage_types"] = []
      _1["contact"]["contact_email"] = "maria at bakery"
    end
    assert_equal [["coverage_types", "Coverage types must list at least one item"],
                  ["effective_date", "Effective date must be a date like 2027-01-31"],
                  ["contact_email", "Contact email must be a valid email address"]], errors_for(json)
  end

  test "builder output for a fully reviewed sample is valid" do
    s = create_sample_submission
    s.confirm_all_verified!
    s.approve!(:employee_count)
    s.approve!(:years_in_business)
    s.edit!(:annual_revenue, "4200000")
    assert SubmissionValidator.new.valid?(SubmissionBuilder.new(s).call)
  end
end
