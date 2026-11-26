# Builds the submission JSON from broker-approved field values.
#
# The raw extraction is the model's claim; this is the broker-approved record,
# and the only thing that will ever leave the app. Conversions are
# deterministic: a value that can't be converted is kept as its raw string so
# the schema check fails. Nothing is guessed or silently fixed.
class SubmissionBuilder
  SCHEMA_VERSION = "1".freeze

  SECTIONS = {
    "applicant" => %w[business_name fein address zip years_in_business],
    "operations" => %w[industry_description naics_code annual_revenue employee_count],
    "coverage" => %w[coverage_types effective_date],
    "contact" => %w[contact_name contact_email]
  }.freeze

  INTEGER_FIELDS = %w[annual_revenue employee_count years_in_business].freeze

  def initialize(submission, now: Time.current)
    @submission = submission
    @now = now
  end

  def call
    {
      "schema_version" => SCHEMA_VERSION,
      "submission_id" => @submission.id,
      "built_at" => @now.utc.iso8601,
      **SECTIONS.transform_values { |names| names.index_with { convert(_1, @submission.field(_1)) } }
    }
  end

  private

  def convert(name, field)
    return nil if field["resolution"] == "not_provided"
    value = field["value"]
    return nil if value.nil? || value.to_s.strip.empty?
    value = value.to_s.strip

    case name
    when *INTEGER_FIELDS
      digits = value.delete("$, ")
      digits.match?(/\A\d+\z/) ? digits.to_i : value
    when "coverage_types"
      value.split(/,|\s+and\s+/i).map(&:strip).reject(&:empty?)
    when "effective_date"
      FieldChecker.parse_iso_date(value)&.iso8601 || value
    else
      value
    end
  end
end
