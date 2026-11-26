# Sorts every extracted field into exactly one category: "verified" or
# "needs_approval".
#
# A field is never trusted because the model said so. It is verified only when
# this code can prove it against the transcript; everything else goes to a
# human broker with plain-English reasons.
class FieldChecker
  # Fields whose value is compared against quotes by digits only.
  NUMERIC = %w[fein zip naics_code years_in_business annual_revenue employee_count].freeze
  POSITIVE_NUMBERS = %w[years_in_business annual_revenue employee_count].freeze
  # Fields where a different value inside a mention can be detected by code.
  STRUCTURED = (NUMERIC + %w[effective_date contact_email]).freeze

  MONTHS = Date::MONTHNAMES.compact.map(&:downcase).freeze
  EMAIL_PATTERN = /[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)+/
  NUMBER_RUN = /\d(?:[\d,.\-\s]*\d)?/

  def initialize(transcript, today: Date.current)
    @transcript = normalize(transcript)
    @today = today
  end

  # extraction: { "zip" => { "value" => ..., "source_quote" => ..., "all_mentions" => [...] }, ... }
  # Returns the Submission field array.
  def categorise(extraction)
    extraction = (extraction || {}).to_h.transform_keys(&:to_s)
    Submission::FIELD_NAMES.map do |name|
      raw = extraction[name].is_a?(Hash) ? extraction[name].transform_keys(&:to_s) : {}
      value = self.class.normalize_value(name, raw["value"])
      quote = raw["source_quote"].presence&.to_s
      mentions = Array(raw["all_mentions"]).map(&:to_s).reject(&:blank?)

      reasons = check(name, value, quote, mentions)
      Submission.blank_field(name).merge(
        "value" => value,
        "source_quote" => quote,
        "all_mentions" => mentions,
        "category" => reasons.empty? ? "verified" : "needs_approval",
        "reasons" => reasons
      )
    end
  end

  # Returns the list of failed checks. Empty list means verified.
  def check(name, value, quote, mentions)
    return ["Not stated in call"] if value.blank?

    reasons = []
    if quote.blank?
      reasons << "No source quote given"
    elsif !in_transcript?(quote)
      reasons << "Quote not found in transcript"
    elsif !value_in_quote?(name, value, quote)
      reasons << "Value not in quote"
    end

    if (error = self.class.format_error(name, value, today: @today))
      reasons << error
    end

    reasons << "Mention not found in transcript" unless mentions.all? { in_transcript?(_1) }
    reasons << "Conflicting mentions in transcript" if mentions.any? { conflicts?(name, value, _1) }
    reasons
  end

  # Format validation shared by categorisation and the broker's approve/edit
  # actions. Returns nil when valid, otherwise a reason string.
  def self.format_error(name, value, today: Date.current)
    name = name.to_s
    value = normalize_value(name, value)
    return "Value is blank" if value.blank?

    case name
    when "fein"
      "FEIN format invalid (expected NN-NNNNNNN)" unless value.match?(/\A\d{2}-\d{7}\z/)
    when "naics_code"
      "NAICS code must be 6 digits" unless value.match?(/\A\d{6}\z/)
    when "zip"
      "ZIP must be 5 digits" unless value.match?(/\A\d{5}\z/)
    when *POSITIVE_NUMBERS
      label = name.humanize
      "#{label} must be a number greater than 0" unless value.match?(/\A\d+(\.\d+)?\z/) && value.to_f > 0
    when "contact_email"
      "Email format invalid" unless value.match?(/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/)
    when "effective_date"
      date = parse_iso_date(value)
      if date.nil?
        "Effective date is not a valid date (YYYY-MM-DD)"
      elsif date < today
        "Effective date is in the past"
      end
    end
  end

  # Canonical string form for a value: strips whitespace, and for the
  # positive-number fields drops "$" and thousands separators.
  def self.normalize_value(name, value)
    value = value.join(", ") if value.is_a?(Array)
    return nil if value.nil?
    value = value.to_s.strip
    return nil if value.empty?

    if POSITIVE_NUMBERS.include?(name.to_s)
      stripped = value.delete("$,").strip
      if stripped.match?(/\A\d+(\.\d+)?\z/)
        value = stripped.sub(/\.0+\z/, "")
      end
    end
    value
  end

  def self.parse_iso_date(value)
    return nil unless value.to_s.match?(/\A\d{4}-\d{2}-\d{2}\z/)
    Date.iso8601(value.to_s)
  rescue Date::Error
    nil
  end

  private

  # Lowercase, punctuation to spaces, collapse whitespace.
  def normalize(text)
    text.to_s.downcase.gsub(/[^a-z0-9@]+/, " ").squish
  end

  def in_transcript?(quote)
    q = normalize(quote)
    q.present? && " #{@transcript} ".include?(" #{q} ")
  end

  def value_in_quote?(name, value, quote)
    case name
    when *NUMERIC
      number_runs(quote).include?(digits(value))
    when "effective_date"
      date = self.class.parse_iso_date(value)
      date.present? && date_spellings(date).any? { phrase_in?(_1, quote) }
    when "contact_email"
      quote.downcase.include?(value.downcase)
    when "coverage_types"
      value.split(",").map(&:strip).reject(&:empty?).all? { phrase_in?(_1, quote) }
    else
      phrase_in?(value, quote)
    end
  end

  def phrase_in?(phrase, text)
    p = normalize(phrase)
    p.present? && " #{normalize(text)} ".include?(" #{p} ")
  end

  # Only structured fields can be checked for a different value.
  def conflicts?(name, value, mention)
    case name
    when *NUMERIC
      (number_runs(mention) - [digits(value)]).any?
    when "contact_email"
      mention.scan(EMAIL_PATTERN).any? { _1.downcase != value.downcase }
    when "effective_date"
      date = self.class.parse_iso_date(value)
      date.nil? || dates_in(mention).any? { |m, d, y| m != date.month || d != date.day || (y && y != date.year) }
    else
      false
    end
  end

  def digits(text) = text.to_s.gsub(/\D/, "")

  # Each run of digits (allowing spaces, dashes, commas and dots between them)
  # reduced to its digits: "84-317 2905" -> "843172905".
  def number_runs(text)
    text.to_s.scan(NUMBER_RUN).map { digits(_1) }
  end

  def date_spellings(date)
    month = MONTHS[date.month - 1]
    day = date.day
    ordinal = day.ordinalize
    [
      date.iso8601,
      "#{date.month}/#{day}/#{date.year}",
      format("%02d/%02d/%d", date.month, day, date.year),
      "#{month} #{day} #{date.year}",
      "#{month} #{ordinal} #{date.year}",
      "#{day} #{month} #{date.year}",
      "#{ordinal} of #{month} #{date.year}"
    ]
  end

  # [month, day, year_or_nil] for each literal date found in text.
  def dates_in(text)
    t = text.to_s.downcase
    found = t.scan(/\b(\d{4})-(\d{1,2})-(\d{1,2})\b/).map { |y, m, d| [m.to_i, d.to_i, y.to_i] }
    found += t.scan(%r{\b(\d{1,2})/(\d{1,2})(?:/(\d{4}))?\b}).map { |m, d, y| [m.to_i, d.to_i, y&.to_i] }
    month_re = MONTHS.join("|")
    found += t.scan(/\b(#{month_re})\s+(\d{1,2})(?:st|nd|rd|th)?(?:,?\s+(\d{4}))?/).map do |m, d, y|
      [MONTHS.index(m) + 1, d.to_i, y&.to_i]
    end
    found
  end
end
