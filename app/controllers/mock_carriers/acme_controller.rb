module MockCarriers
  # Fake "Acme Insurance" quoting API. JSON in, JSON out, bearer token auth.
  # A stand-in for a real carrier system: shares nothing with the channels.
  class AcmeController < ActionController::API
    FIELDS = {
      "insured_name" => String, "tax_id" => String, "street_address" => String,
      "postal_code" => String, "naics" => String, "annual_revenue" => Integer,
      "employees" => Integer, "coverages" => Array, "effective_date" => String
    }.freeze

    def create
      return render(json: { error: "unauthorized" }, status: :unauthorized) unless authorized?

      body = parse_body
      details = body ? validate(body) : ["body must be a JSON object"]
      return render(json: { error: "invalid", details: details }, status: :unprocessable_entity) if details.any?

      if body["insured_name"] == "Acme Test Outage"
        return render(json: { error: "service unavailable" }, status: :service_unavailable)
      end

      decision = Pricing.decide(coverages: body["coverages"], revenue: body["annual_revenue"], employees: body["employees"])
      case decision[:status]
      when "quoted"
        render status: :created, json: {
          status: "quoted",
          quote_id: "ACM-#{rand(100_000..999_999)}",
          premium: decision[:premium],
          valid_until: (Date.current + 30).iso8601
        }
      else
        render status: :ok, json: { status: decision[:status], reason: decision[:reason] }
      end
    end

    private

    def token = ENV.fetch("ACME_API_TOKEN", "acme-demo-token")

    def authorized?
      given = request.authorization.to_s.delete_prefix("Bearer ")
      request.authorization.to_s.start_with?("Bearer ") && ActiveSupport::SecurityUtils.secure_compare(given, token)
    end

    def parse_body
      data = JSON.parse(request.raw_post)
      data.is_a?(Hash) ? data : nil
    rescue JSON::ParserError
      nil
    end

    def validate(body)
      FIELDS.filter_map do |name, type|
        value = body[name]
        if value.nil? || value == ""
          "#{name} is required"
        elsif !value.is_a?(type)
          "#{name} must be #{type == Integer ? "an integer" : "a #{type.name.downcase}"}"
        elsif type == Array && (value.empty? || !value.all? { _1.is_a?(String) })
          "#{name} must be a non-empty array of strings"
        end
      end
    end
  end
end
