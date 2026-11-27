require "prawn"

# A clean, standardised commercial insurance application, built from the
# validated submission JSON. Fixed sections in a fixed order, every field
# always present. No trace of the review process.
class SubmissionPdf
  SECTIONS = {
    "Applicant" => %w[business_name fein address zip years_in_business],
    "Operations" => %w[industry_description naics_code annual_revenue employee_count],
    "Coverage" => %w[coverage_types effective_date],
    "Contact" => %w[contact_name contact_email]
  }.freeze

  NOT_PROVIDED = "Not provided".freeze
  LABEL_WIDTH = 170

  def initialize(submission, generated_on: Date.current)
    @json = submission.submission_json || {}
    @generated_on = generated_on
  end

  # [[section title, [[label, display value], ...]], ...]
  def sections
    SECTIONS.map do |title, names|
      [title, names.map { [ApplicationHelper::FIELD_LABELS.fetch(_1), display(_1, @json.dig(title.downcase, _1))] }]
    end
  end

  def render
    pdf = Prawn::Document.new(page_size: "LETTER", margin: 54, info: { Title: "Commercial Insurance Application" })
    pdf.font "Helvetica"

    pdf.text "Commercial Insurance Application", size: 20, style: :bold
    pdf.move_down 4
    pdf.text "Submission ##{@json["submission_id"]}    Generated #{@generated_on.iso8601}", size: 9, color: "555555"
    pdf.move_down 18

    sections.each do |title, rows|
      pdf.text title, size: 13, style: :bold
      pdf.move_down 2
      pdf.stroke_color "999999"
      pdf.stroke_horizontal_rule
      pdf.move_down 8
      rows.each { |label, value| row(pdf, label, value) }
      pdf.move_down 14
    end
    pdf.render
  end

  private

  def display(name, value)
    return NOT_PROVIDED if value.blank?
    value = value.join(", ") if value.is_a?(Array)

    text = case name
    when "annual_revenue"
      ActiveSupport::NumberHelper.number_to_currency(value, precision: 0)
    when "effective_date"
      FieldChecker.parse_iso_date(value)&.iso8601 || value.to_s
    else
      value.to_s
    end
    pdf_safe(text)
  end

  # The built-in Helvetica only covers Windows-1252.
  def pdf_safe(text)
    text.encode("Windows-1252", invalid: :replace, undef: :replace, replace: "?").encode("UTF-8")
  end

  def row(pdf, label, value)
    top = pdf.cursor
    pdf.bounding_box([0, top], width: LABEL_WIDTH) { pdf.text label, size: 10, style: :bold }
    label_bottom = pdf.cursor
    pdf.move_cursor_to top
    pdf.bounding_box([LABEL_WIDTH, top], width: pdf.bounds.width - LABEL_WIDTH) do
      pdf.text value, size: 10, color: value == NOT_PROVIDED ? "777777" : "000000"
    end
    pdf.move_cursor_to [label_bottom, pdf.cursor].min - 6
  end
end
