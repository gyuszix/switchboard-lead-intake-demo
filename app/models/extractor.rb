require "net/http"
require "json"

# Asks a local Ollama model to extract intake fields from a call transcript.
# All Ollama code lives here.
#
# The result is only a claim: FieldChecker decides what can be trusted.
# If Ollama is unreachable, falls back to hardcoded fixture extractions for
# the sample transcripts (or all-null fields for anything else).
class Extractor
  Result = Struct.new(:fields, :used_fixtures, keyword_init: true)

  UNREACHABLE = [
    SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout,
    IOError, EOFError, OpenSSL::SSL::SSLError
  ].freeze

  FIELD_HINTS = {
    "business_name" => "legal name of the business",
    "fein" => "federal employer identification number, exactly as stated",
    "address" => "street address including city and state, without the zip code",
    "zip" => "5 digit zip code",
    "industry_description" => "short description of what the business does",
    "naics_code" => "6 digit NAICS code, only if the code itself is said",
    "years_in_business" => "number of years in business, digits only",
    "annual_revenue" => "annual revenue in dollars, digits only, no $ or commas",
    "employee_count" => "number of employees, digits only",
    "coverage_types" => "comma separated list of coverage types requested",
    "effective_date" => "requested policy start date as YYYY-MM-DD",
    "contact_name" => "name of the contact person",
    "contact_email" => "contact email address"
  }.freeze

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You extract a commercial insurance intake form from a phone call transcript.

    Rules:
    - Only extract what is explicitly stated in the transcript. Never infer or guess.
    - If a field is not stated, set value and source_quote to null.
    - If a value is corrected later in the call, use the latest value.
    - source_quote is the exact sentence from the transcript that states the value, copied verbatim.
    - When the transcript states a field, fill value with that stated value, written in the format given below.
    - all_mentions lists every verbatim quote in the transcript where this field is mentioned, including earlier or corrected values.
    - Copy every quote verbatim, character for character, from the transcript.
    - Names and details may appear in either speaker's lines, including how the broker addresses the client (e.g. 'Hey Mike'). A contact name may be partial; return what is stated.

    Fields:
    #{FIELD_HINTS.map { |name, hint| "- #{name}: #{hint}" }.join("\n")}
  PROMPT

  def initialize(url: ENV.fetch("OLLAMA_URL", "http://localhost:11434"),
                 model: ENV.fetch("OLLAMA_MODEL", "granite4.2:8b"))
    @url = url
    @model = model
  end

  class Unavailable < StandardError; end

  def call(transcript)
    body = post(payload(transcript))
    Result.new(fields: parse(body), used_fixtures: false)
  rescue *UNREACHABLE, Unavailable
    Result.new(fields: Sample.fixture_for(transcript) || {}, used_fixtures: true)
  end

  def self.schema
    field_schema = {
      type: "object",
      properties: {
        source_quote: { type: %w[string null] },
        value: { type: %w[string null] },
        all_mentions: { type: "array", items: { type: "string" } }
      },
      required: %w[source_quote value all_mentions]
    }
    {
      type: "object",
      properties: Submission::FIELD_NAMES.index_with { field_schema },
      required: Submission::FIELD_NAMES
    }
  end

  private

  def payload(transcript)
    {
      model: @model,
      stream: false,
      think: false,
      format: self.class.schema,
      options: { temperature: 0, num_ctx: 8192 },
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: "Transcript:\n\n#{transcript}" }
      ]
    }
  end

  # The only network call. Returns the response body or raises.
  def post(payload)
    uri = URI.join(@url, "/api/chat")
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                               open_timeout: 3, read_timeout: 300) do |http|
      http.post(uri.path, payload.to_json, "Content-Type" => "application/json")
    end
    raise Unavailable, "Ollama returned #{response.code}" unless response.is_a?(Net::HTTPSuccess)
    response.body
  end

  # Defensive: anything malformed becomes an empty field (treated as null).
  def parse(body)
    content = JSON.parse(body).dig("message", "content")
    data = JSON.parse(content.to_s)
    return {} unless data.is_a?(Hash)

    Submission::FIELD_NAMES.each_with_object({}) do |name, out|
      raw = data[name]
      next unless raw.is_a?(Hash)
      out[name] = {
        "value" => scalar(raw["value"]),
        "source_quote" => scalar(raw["source_quote"]),
        "all_mentions" => Array(raw["all_mentions"]).filter_map { scalar(_1) }
      }
    end
  rescue JSON::ParserError, TypeError
    {}
  end

  def scalar(value)
    case value
    when String, Numeric then value.to_s
    when Array then value.map(&:to_s).join(", ")
    end
  end
end
