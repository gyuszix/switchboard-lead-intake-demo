# A submission is one call transcript plus the intake fields extracted from it.
#
# `fields` is a JSON array with one hash per field in FIELD_NAMES order:
#   name, value, original_value, source_quote, all_mentions,
#   category ("verified" / "needs_approval"), reasons (array),
#   resolution (nil / "confirmed" / "approved" / "edited" / "not_provided")
class Submission < ApplicationRecord
  FIELD_NAMES = %w[
    business_name fein address zip industry_description naics_code
    years_in_business annual_revenue employee_count coverage_types
    effective_date contact_name contact_email
  ].freeze

  CATEGORIES = %w[verified needs_approval].freeze
  RESOLUTIONS = %w[confirmed approved edited not_provided].freeze

  validates :transcript, presence: true

  # Any change to the reviewed fields invalidates a built submission.
  before_save :clear_built_submission, if: :will_save_change_to_fields?

  def self.blank_field(name)
    {
      "name" => name,
      "value" => nil,
      "original_value" => nil,
      "source_quote" => nil,
      "all_mentions" => [],
      "category" => "needs_approval",
      "reasons" => [],
      "resolution" => nil
    }
  end

  def field(name)
    fields.find { |f| f["name"] == name.to_s } or raise ArgumentError, "unknown field #{name}"
  end

  # Merges attrs into the named field. Persist with save.
  def update_field(name, attrs)
    name = name.to_s
    self.fields = fields.map { |f| f["name"] == name ? f.merge(attrs.stringify_keys) : f }
  end

  def verified_fields = fields.select { |f| f["category"] == "verified" }
  def needs_approval_fields = fields.select { |f| f["category"] == "needs_approval" }

  def resolved_count = fields.count { |f| f["resolution"].present? }
  def total_count = fields.size
  def all_resolved? = fields.any? && fields.all? { |f| f["resolution"].present? }

  # --- Review rules -----------------------------------------------------
  # Each returns nil on success or an error message. Approve and Not provided
  # are one-time decisions; Edit is always available, on every field.

  # Confirms every unresolved verified field. Never touches needs_approval
  # fields or verified fields the broker already edited.
  def confirm_all_verified!
    verified_fields.each do |f|
      update_field(f["name"], "resolution" => "confirmed") if f["resolution"].nil?
    end
    save!
    nil
  end

  # Accepts the extracted value unchanged, only if it passes format validation.
  def approve!(name)
    field = field(name)
    error = review_error(field) || FieldChecker.format_error(name, field["value"])
    return error if error

    update_field(name, "resolution" => "approved")
    save!
    nil
  end

  # Replaces the value with the broker's, which must pass format validation.
  # original_value keeps the first (extracted) value across repeated edits.
  def edit!(name, new_value)
    field = field(name)
    new_value = FieldChecker.normalize_value(name, new_value)
    error = FieldChecker.format_error(name, new_value)
    return error if error

    update_field(name, "original_value" => field["original_value"] || field["value"],
                       "value" => new_value, "resolution" => "edited")
    save!
    nil
  end

  # Records that the information was not given; clears the value.
  def mark_not_provided!(name)
    field = field(name)
    error = review_error(field)
    return error if error

    update_field(name, "value" => nil, "resolution" => "not_provided")
    save!
    nil
  end

  # --- Build -----------------------------------------------------------

  # Builds the submission JSON from the approved values and validates it
  # against the schema. Saves it only if valid. Returns the list of errors.
  def build_submission!(now: Time.current)
    json = SubmissionBuilder.new(self, now: now).call
    errors = SubmissionValidator.new.call(json)
    update!(submission_json: json, ready_at: now) if errors.empty?
    errors
  end

  def ready? = submission_json.present? && ready_at.present?

  private

  def clear_built_submission
    self.submission_json = nil
    self.ready_at = nil
  end

  def review_error(field)
    return "Only fields that need approval can be changed" unless field["category"] == "needs_approval"
    "Already resolved" if field["resolution"].present?
  end
end
