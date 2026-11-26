require "test_helper"

class FieldCheckerTest < ActiveSupport::TestCase
  TODAY = Date.new(2026, 11, 26)

  TRANSCRIPT = <<~TEXT
    Broker: What's the business called?
    Client: It's Sunrise Bakery, LLC.
    Broker: And your FEIN?
    Client: Our FEIN is 12-3456789.
    Client: The zip is 02134.
    Client: We have about 40 employees... actually closer to 45 now.
    Client: We'd like coverage to start January 15th, 2027.
    Client: Email me at Jane@SunriseBakery.com please.
    Client: Revenue was roughly one point two million.
    Client: We need general liability and workers comp.
  TEXT

  def checker = FieldChecker.new(TRANSCRIPT, today: TODAY)

  def check(name, value, quote, mentions = [])
    checker.check(name, value, quote, mentions)
  end

  # --- verified rules -------------------------------------------------------

  test "verified when value, quote, format and mentions all check out" do
    assert_empty check("fein", "12-3456789", "Our FEIN is 12-3456789.", ["Our FEIN is 12-3456789."])
  end

  test "categorise builds full field hashes in order" do
    fields = checker.categorise("zip" => { "value" => "02134", "source_quote" => "The zip is 02134.", "all_mentions" => [] })
    assert_equal Submission::FIELD_NAMES, fields.map { _1["name"] }
    zip = fields.find { _1["name"] == "zip" }
    assert_equal "verified", zip["category"]
    assert_nil zip["resolution"]
    assert_equal ["Not stated in call"], fields.find { _1["name"] == "fein" }["reasons"]
  end

  test "categorise treats missing or malformed fields as null" do
    fields = checker.categorise("zip" => "garbage", "fein" => nil)
    assert fields.all? { _1["category"] == "needs_approval" && _1["value"].nil? }
  end

  # --- failure reasons ------------------------------------------------------

  test "null value is not stated in call" do
    assert_equal ["Not stated in call"], check("contact_email", nil, nil)
  end

  test "quote not found in transcript" do
    assert_includes check("zip", "02134", "The zip code is 02134"), "Quote not found in transcript"
  end

  test "missing source quote" do
    assert_includes check("zip", "02134", nil), "No source quote given"
  end

  test "value not in quote" do
    assert_includes check("zip", "02135", "The zip is 02134."), "Value not in quote"
  end

  test "FEIN format invalid" do
    t = "Client: The FEIN is 12-34567890."
    reasons = FieldChecker.new(t, today: TODAY).check("fein", "12-34567890", "The FEIN is 12-34567890.", [])
    assert_equal ["FEIN format invalid (expected NN-NNNNNNN)"], reasons
  end

  test "format rules per field" do
    assert_nil FieldChecker.format_error("naics_code", "311811")
    assert_equal "NAICS code must be 6 digits", FieldChecker.format_error("naics_code", "31181")
    assert_equal "ZIP must be 5 digits", FieldChecker.format_error("zip", "2134")
    assert_nil FieldChecker.format_error("annual_revenue", "$1,250,000")
    assert_equal "Annual revenue must be a number greater than 0", FieldChecker.format_error("annual_revenue", "1.2 million")
    assert_equal "Employee count must be a number greater than 0", FieldChecker.format_error("employee_count", "0")
    assert_nil FieldChecker.format_error("years_in_business", "12")
    assert_equal "Email format invalid", FieldChecker.format_error("contact_email", "jane at bakery")
    assert_nil FieldChecker.format_error("contact_email", "jane@bakery.com")
    assert_equal "Value is blank", FieldChecker.format_error("business_name", " ")
  end

  test "effective date must be a valid future date" do
    assert_nil FieldChecker.format_error("effective_date", "2027-01-15", today: TODAY)
    assert_nil FieldChecker.format_error("effective_date", "2026-11-26", today: TODAY)
    assert_equal "Effective date is in the past", FieldChecker.format_error("effective_date", "2026-11-25", today: TODAY)
    assert_equal "Effective date is not a valid date (YYYY-MM-DD)", FieldChecker.format_error("effective_date", "2027-02-30", today: TODAY)
    assert_equal "Effective date is not a valid date (YYYY-MM-DD)", FieldChecker.format_error("effective_date", "January 15", today: TODAY)
  end

  test "revenue in words is not in quote and fails format" do
    reasons = check("annual_revenue", "one point two million", "Revenue was roughly one point two million.")
    assert_includes reasons, "Annual revenue must be a number greater than 0"
  end

  test "mention not found in transcript" do
    assert_includes check("zip", "02134", "The zip is 02134.", ["zip is 02134 in Boston"]), "Mention not found in transcript"
  end

  # --- normalised matching --------------------------------------------------

  test "quote matching ignores case, whitespace and punctuation" do
    assert_empty check("business_name", "Sunrise Bakery", "it's   SUNRISE bakery llc")
  end

  test "quote must match on word boundaries" do
    assert_includes check("business_name", "Sunrise", "rise Bakery"), "Quote not found in transcript"
  end

  test "numeric values compare digits only" do
    t ="Client: it is 12 345 6789 I think"
    assert_empty FieldChecker.new(t, today: TODAY).check("fein", "12-3456789", "it is 12 345 6789", [])
  end

  test "numeric match does not accept a partial number" do
    assert_includes check("employee_count", "4", "actually closer to 45 now"), "Value not in quote"
  end

  test "email match is case insensitive" do
    assert_empty check("contact_email", "jane@sunrisebakery.com", "Email me at Jane@SunriseBakery.com please.")
  end

  test "spoken date with year matches iso value" do
    assert_empty check("effective_date", "2027-01-15", "We'd like coverage to start January 15th, 2027.")
  end

  test "coverage types each must appear in quote" do
    quote = "We need general liability and workers comp."
    assert_empty check("coverage_types", "general liability, workers comp", quote)
    assert_includes check("coverage_types", "general liability, property", quote), "Value not in quote"
  end

  # --- conflicting mentions -------------------------------------------------

  test "conflicting numeric mention" do
    reasons = check("employee_count", "45", "actually closer to 45 now",
      ["We have about 40 employees... actually closer to 45 now."])
    assert_equal ["Conflicting mentions in transcript"], reasons
  end

  test "agreeing mentions do not conflict" do
    assert_empty check("zip", "02134", "The zip is 02134.", ["The zip is 02134."])
  end

  test "conflicting email mention" do
    t = TRANSCRIPT + "Client: Or use jane@gmail.com.\n"
    reasons = FieldChecker.new(t, today: TODAY).check("contact_email", "jane@sunrisebakery.com",
      "Email me at Jane@SunriseBakery.com please.", ["Or use jane@gmail.com."])
    assert_equal ["Conflicting mentions in transcript"], reasons
  end

  test "conflicting date mention" do
    t = TRANSCRIPT + "Client: Or maybe February 1st.\n"
    reasons = FieldChecker.new(t, today: TODAY).check("effective_date", "2027-01-15",
      "We'd like coverage to start January 15th, 2027.", ["Or maybe February 1st."])
    assert_equal ["Conflicting mentions in transcript"], reasons
  end

  test "free text fields are not checked for conflicting values" do
    assert_empty check("business_name", "Sunrise Bakery", "It's Sunrise Bakery, LLC.", ["What's the business called?"])
  end
end
