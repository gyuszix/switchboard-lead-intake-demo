require "json_schemer"

# Checks a submission JSON against config/schemas/submission_v1.json and
# translates json_schemer errors into plain English, one per field.
# The schema checks format only; value checks stay in the review stage.
class SubmissionValidator
  SCHEMA_PATH = Rails.root.join("config/schemas/submission_v1.json")

  Error = Struct.new(:field, :message, keyword_init: true)

  PATTERN_MESSAGES = {
    "fein" => "FEIN must look like 12-3456789",
    "naics_code" => "NAICS code must be 6 digits",
    "zip" => "ZIP must be 5 digits"
  }.freeze

  FORMAT_MESSAGES = {
    "effective_date" => "Effective date must be a date like 2027-01-31",
    "contact_email" => "Contact email must be a valid email address",
    "built_at" => "Built at must be an ISO 8601 timestamp"
  }.freeze

  JSON_TYPES = %w[string integer number boolean array object null].freeze

  def self.schemer
    @schemer ||= JSONSchemer.schema(SCHEMA_PATH)
  end

  # Returns a list of Errors; empty means valid.
  def call(json)
    self.class.schemer.validate(json).flat_map { translate(_1) }
  end

  def valid?(json) = call(json).empty?

  private

  def translate(error)
    # json_schemer reports the keyword as "type", except for type errors,
    # where "type" holds the expected JSON type name.
    keyword = JSON_TYPES.include?(error["type"]) ? "type" : error["type"]
    field = error["data_pointer"].to_s.split("/").last.to_s

    if keyword == "required"
      return error.dig("details", "missing_keys").map { Error.new(field: _1, message: "Required for submission") }
    end
    # A disallowed additional property fails the `false` schema.
    return [ Error.new(field: field, message: "Unexpected field, not part of the submission schema") ] if keyword == "schema"
    return [ Error.new(field: field, message: "Required for submission") ] if error["data"].nil? || error["data"] == ""

    [ Error.new(field: field, message: message_for(field, keyword)) ]
  end

  def message_for(field, keyword)
    label = label(field)
    case keyword
    when "pattern" then PATTERN_MESSAGES.fetch(field, "#{label} format is invalid")
    when "format" then FORMAT_MESSAGES.fetch(field, "#{label} format is invalid")
    when "minItems" then "#{label} must list at least one item"
    when "minLength" then "Required for submission"
    when "type", "minimum"
      expected = SCHEMA_TYPES[field]
      expected == "integer" ? "#{label} must be a whole number of at least 1" : "#{label} must be a #{expected || "valid value"}"
    when "const" then "#{label} must be #{SubmissionBuilder::SCHEMA_VERSION.inspect}"
    else "#{label} is invalid"
    end
  end

  def label(field)
    ApplicationHelper::FIELD_LABELS.fetch(field) { field.humanize }
  end

  # field name => schema type, for the "wrong type" message.
  SCHEMA_TYPES = begin
    schema = JSON.parse(SCHEMA_PATH.read)
    top = schema["properties"]
    nested = top.values.select { _1["type"] == "object" }.flat_map { _1["properties"].to_a }
    (top.to_a + nested).to_h { |name, s| [ name, s["type"] ] }
  end.freeze
end
