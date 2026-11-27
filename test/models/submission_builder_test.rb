require "test_helper"

class SubmissionBuilderTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 11, 26, 12, 0, 0)

  setup { @s = create_sample_submission }

  def build = SubmissionBuilder.new(@s, now: NOW).call

  def set(name, value, resolution: "edited")
    @s.update_field(name, "value" => value, "resolution" => resolution)
  end

  test "builds the fixed structure" do
    json = build
    assert_equal %w[schema_version submission_id built_at applicant operations coverage contact], json.keys
    assert_equal "1", json["schema_version"]
    assert_equal @s.id, json["submission_id"]
    assert_equal "2026-11-26T12:00:00Z", json["built_at"]
    assert_equal %w[business_name fein address zip years_in_business], json["applicant"].keys
    assert_equal "Eight one, four four two, oh nine seven six", json["applicant"]["fein"]
    assert_equal "07072", json["applicant"]["zip"]
    assert_nil json["operations"]["naics_code"]
  end

  test "converts numbers to integers" do
    set(:annual_revenue, "$5,400,000")
    set(:employee_count, " 41 ")
    json = build
    assert_equal 5_400_000, json["operations"]["annual_revenue"]
    assert_equal 41, json["operations"]["employee_count"]
    assert_equal 15, json["applicant"]["years_in_business"]
  end

  test "splits coverage types on commas and 'and'" do
    set(:coverage_types, "General liability, commercial property And workers comp, ,")
    assert_equal ["General liability", "commercial property", "workers comp"], build["coverage"]["coverage_types"]
  end

  test "keeps effective date as YYYY-MM-DD" do
    assert_equal "2027-04-01", build["coverage"]["effective_date"]
  end

  test "not provided becomes null" do
    set(:contact_email, nil, resolution: "not_provided")
    assert_nil build["contact"]["contact_email"]
  end

  test "unconvertible values are kept raw" do
    set(:annual_revenue, "four point two million")
    set(:years_in_business, "2.5")
    set(:effective_date, "next spring")
    json = build
    assert_equal "four point two million", json["operations"]["annual_revenue"]
    assert_equal "2.5", json["applicant"]["years_in_business"]
    assert_equal "next spring", json["coverage"]["effective_date"]
  end
end
