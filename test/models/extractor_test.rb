require "test_helper"

class ExtractorTest < ActiveSupport::TestCase
  # Extractor whose single network call returns `body` (or raises `error`).
  def extractor(body: nil, error: nil)
    e = Extractor.new
    sent = nil
    e.define_singleton_method(:post) do |payload|
      sent = payload
      raise error if error
      body
    end
    e.define_singleton_method(:sent) { sent }
    e
  end

  def ollama_body(content) = { message: { content: content } }.to_json

  test "sends the required Ollama options and schema" do
    e = extractor(body: ollama_body("{}"))
    e.call("hi")
    assert_equal false, e.sent[:stream]
    assert_equal false, e.sent[:think]
    assert_equal({ temperature: 0, num_ctx: 8192 }, e.sent[:options])
    assert_equal Submission::FIELD_NAMES, e.sent[:format][:required]
    assert_not_includes e.sent.to_json, "confidence"
  end

  test "parses fields from the model response" do
    content = { zip: { value: "60614", source_quote: "The zip code is 60614.", all_mentions: ["The zip code is 60614."] } }.to_json
    result = extractor(body: ollama_body(content)).call("x")
    assert_not result.used_fixtures
    assert_equal "60614", result.fields["zip"]["value"]
    assert_equal ["The zip code is 60614."], result.fields["zip"]["all_mentions"]
  end

  test "invalid JSON becomes empty fields" do
    result = extractor(body: ollama_body("not json {")).call("x")
    assert_equal({}, result.fields)
    assert_not result.used_fixtures
  end

  test "malformed field is dropped and treated as null" do
    content = { zip: "60614", fein: { value: ["12", "3"], all_mentions: "nope" } }.to_json
    fields = extractor(body: ollama_body(content)).call("x").fields
    assert_nil fields["zip"]
    assert_equal "12, 3", fields["fein"]["value"]
    assert_equal ["nope"], fields["fein"]["all_mentions"]
  end

  test "falls back to fixtures for a sample transcript when Ollama is unreachable" do
    sample = Sample.all.first
    result = extractor(error: Errno::ECONNREFUSED.new).call(sample[:transcript])
    assert result.used_fixtures
    assert_equal "Golden Crust Bakery LLC", result.fields["business_name"]["value"]
  end

  test "falls back to empty fields for an unknown transcript when Ollama is unreachable" do
    result = extractor(error: Net::OpenTimeout.new).call("some other call")
    assert result.used_fixtures
    assert_equal({}, result.fields)
  end

  test "sample fixtures categorise as each sample intends" do
    by_key = Sample.all.to_h do |s|
      fields = FieldChecker.new(s[:transcript], today: Date.new(2026, 11, 26)).categorise(Sample.fixture_for(s[:transcript]))
      [s[:key], fields.select { _1["category"] == "needs_approval" }.map { _1["name"] }]
    end
    assert_empty by_key["bakery"]
    assert_equal %w[fein contact_email], by_key["landscaping"]
    assert_equal %w[annual_revenue employee_count], by_key["it_services"]
  end
end
