require "net/http"

module Channels
  # Gets a quote from Acme Insurance's JSON API.
  class Api < Base
    TIMEOUT = 15

    # Our coverage names → Acme's vocabulary. Anything else is sent as-is.
    COVERAGE_SYNONYMS = {
      "workers compensation" => "workers comp",
      "workers' compensation" => "workers comp",
      "commercial property" => "property",
      "cyber liability" => "cyber"
    }.freeze

    Response = Struct.new(:code, :body)

    # Default transport: a real HTTP POST. Tests inject their own callable.
    HTTP = lambda do |url, body, headers|
      uri = URI(url)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                 open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
        http.post(uri.path, body, headers)
      end
      Response.new(response.code.to_i, response.body)
    end

    def self.channel = "api"

    def initialize(transport: HTTP,
                   base_url: ENV.fetch("MOCK_CARRIER_BASE_URL", "http://localhost:3000"),
                   token: ENV.fetch("ACME_API_TOKEN", "acme-demo-token"))
      @transport = transport
      @url = "#{base_url.chomp("/")}/mock_carriers/acme/api/v1/quotes"
      @token = token
    end

    # Submission JSON → Acme's field names.
    def payload(json)
      {
        "insured_name" => json.dig("applicant", "business_name"),
        "tax_id" => json.dig("applicant", "fein"),
        "street_address" => json.dig("applicant", "address"),
        "postal_code" => json.dig("applicant", "zip"),
        "naics" => json.dig("operations", "naics_code"),
        "annual_revenue" => json.dig("operations", "annual_revenue"),
        "employees" => json.dig("operations", "employee_count"),
        "coverages" => Array(json.dig("coverage", "coverage_types")).map { coverage_name(_1) },
        "effective_date" => json.dig("coverage", "effective_date")
      }
    end

    private

    def coverage_name(name)
      name = name.to_s.strip
      COVERAGE_SYNONYMS.fetch(name.downcase, name)
    end

    HEADERS = { "Content-Type" => "application/json", "Accept" => "application/json" }.freeze

    # Records what was sent and, if anything came back, what was received.
    def deliver(json)
      body = payload(json).to_json
      sent = [ "POST #{@url}", *HEADERS.map { "#{_1}: #{_2}" }, "Authorization: Bearer [hidden]", "", pretty(body) ].join("\n")
      exchange(body).merge(request_body: sent)
    end

    def exchange(body)
      response = @transport.call(@url, body, HEADERS.merge("Authorization" => "Bearer #{@token}"))
      interpret(response).merge(response_body: "HTTP #{response.code}\n\n#{pretty(response.body)}")
    rescue Net::OpenTimeout, Net::ReadTimeout
      failed("Acme API timed out after #{TIMEOUT}s")
    rescue SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError => e
      failed("Could not connect to Acme API (#{e.class.name.demodulize})")
    end

    def pretty(text)
      JSON.pretty_generate(JSON.parse(text.to_s))
    rescue JSON::ParserError
      text.to_s
    end

    def interpret(response)
      body = parse(response.body)
      case [ response.code, body["status"] ]
      in [ 201, "quoted" ]
        { status: "quoted", premium: body["premium"], reference: body["quote_id"],
          message: "Valid until #{body["valid_until"]}" }
      in [ 200, "declined" | "referred" => status ]
        { status: status, message: body["reason"] }
      in [ 401, _ ]
        failed("Acme rejected the API token (401)")
      in [ 422, _ ]
        failed("Acme rejected the request (422): #{Array(body["details"]).join("; ")}")
      in [ 503, _ ]
        failed("Acme API unavailable (503)")
      else
        failed("Unexpected response from Acme API (HTTP #{response.code})")
      end
    end

    def parse(text)
      data = JSON.parse(text.to_s)
      data.is_a?(Hash) ? data : {}
    rescue JSON::ParserError
      {}
    end

    def failed(message) = { status: "failed", message: message }
  end
end
