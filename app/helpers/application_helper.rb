module ApplicationHelper
  FIELD_LABELS = {
    "business_name" => "Business name",
    "fein" => "FEIN",
    "address" => "Address",
    "zip" => "ZIP",
    "industry_description" => "Industry description",
    "naics_code" => "NAICS code",
    "years_in_business" => "Years in business",
    "annual_revenue" => "Annual revenue",
    "employee_count" => "Employee count",
    "coverage_types" => "Coverage types",
    "effective_date" => "Effective date",
    "contact_name" => "Contact name",
    "contact_email" => "Contact email"
  }.freeze

  RESOLUTION_LABELS = {
    "confirmed" => "Confirmed",
    "approved" => "Approved as-is",
    "edited" => "Edited",
    "not_provided" => "Marked not provided"
  }.freeze

  def field_label(name) = FIELD_LABELS.fetch(name.to_s)
  def field_frame_id(name) = "field_#{name}"
end
