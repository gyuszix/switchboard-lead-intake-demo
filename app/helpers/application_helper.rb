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

  SPEAKER_LABEL = /\A([A-Za-z][A-Za-z .'\-]{0,30}:)(.*)\z/m

  def transcript_lines(submission) = submission.transcript.to_s.split(/\r?\n/)

  def transcript_line_id(index) = "line-#{index + 1}"

  # DOM id of the transcript line containing the field's source quote, or nil.
  def quote_line_id(submission, quote)
    index = FieldChecker.line_index(transcript_lines(submission), quote)
    index && transcript_line_id(index)
  end

  # One transcript line with its speaker label ("Broker:", "Name:") in bold.
  def transcript_line(text)
    if (m = text.match(SPEAKER_LABEL))
      safe_join([ tag.strong(m[1]), m[2] ])
    else
      text
    end
  end
end
