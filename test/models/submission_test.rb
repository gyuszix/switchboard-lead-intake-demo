require "test_helper"

class SubmissionTest < ActiveSupport::TestCase
  def build_submission
    Submission.new(transcript: "hello", fields: Submission::FIELD_NAMES.map { Submission.blank_field(_1) })
  end

  test "requires a transcript" do
    assert_not Submission.new(transcript: "").valid?
  end

  test "stores fields as json and round-trips" do
    s = build_submission
    s.update_field(:zip, "value" => "02134", "category" => "verified")
    s.save!
    s.reload
    assert_equal "02134", s.field(:zip)["value"]
    assert_equal Submission::FIELD_NAMES, s.fields.map { _1["name"] }
  end

  test "counts resolutions" do
    s = build_submission
    assert_equal 0, s.resolved_count
    assert_not s.all_resolved?
    Submission::FIELD_NAMES.each { s.update_field(_1, "resolution" => "not_provided") }
    assert_equal 13, s.resolved_count
    assert s.all_resolved?
  end

  test "splits fields by category" do
    s = build_submission
    s.update_field(:fein, "category" => "verified")
    assert_equal [ "fein" ], s.verified_fields.map { _1["name"] }
    assert_equal 12, s.needs_approval_fields.size
  end
end
