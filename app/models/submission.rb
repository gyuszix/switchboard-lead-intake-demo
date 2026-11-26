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
end
