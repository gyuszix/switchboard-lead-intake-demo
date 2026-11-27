module MockCarriers
  # Fake "Beacon Mutual" broker portal: plain HTML pages, session cookie auth.
  # A stand-in for a real carrier website: shares nothing with the channels.
  class BeaconController < ActionController::Base
    layout "mock_carriers/beacon"

    COVERAGES = {
      "general_liability" => "General Liability",
      "property" => "Property",
      "workers_comp" => "Workers Comp",
      "professional_liability" => "Professional Liability"
    }.freeze

    before_action :require_login, only: %i[new_application create_application]

    def login; end

    def authenticate
      if valid_credentials?(params[:username], params[:password])
        session[:beacon_user] = params[:username]
        redirect_to mock_carriers_beacon_new_application_path
      else
        @error = "Invalid username or password"
        render :login
      end
    end

    def new_application
      @values = {}
      @errors = {}
    end

    def create_application
      @values = params.permit(:insured_legal_entity, :tax_id_no, :street_address, :zip_code, :naics,
                              :gross_annual_sales, :number_of_employees, :effective_date, coverages: []).to_h
      @errors = validate(@values)
      return render(:new_application) if @errors.any?

      coverages = Array(@values["coverages"]).map { COVERAGES.fetch(_1, _1).downcase }
      @decision = Pricing.decide(coverages: coverages, revenue: sales(@values), employees: @values["number_of_employees"].to_i)
      @reference = "BCN-#{rand(100_000..999_999)}" if @decision[:status] == "quoted"
      render :result
    end

    private

    def valid_credentials?(username, password)
      ActiveSupport::SecurityUtils.secure_compare(username.to_s, ENV.fetch("BEACON_USERNAME", "broker")) &
        ActiveSupport::SecurityUtils.secure_compare(password.to_s, ENV.fetch("BEACON_PASSWORD", "beacon-demo"))
    end

    def require_login
      redirect_to mock_carriers_beacon_login_path unless session[:beacon_user]
    end

    def sales(values) = values["gross_annual_sales"].to_s.delete(",").to_i

    def validate(v)
      errors = {}
      errors["insured_legal_entity"] = "Required" if v["insured_legal_entity"].blank?
      errors["tax_id_no"] = "Must be in the format 12-3456789" unless v["tax_id_no"].to_s.match?(/\A\d{2}-\d{7}\z/)
      errors["street_address"] = "Required" if v["street_address"].blank?
      errors["zip_code"] = "Must be 5 digits" unless v["zip_code"].to_s.match?(/\A\d{5}\z/)
      errors["naics"] = "Must be 6 digits" unless v["naics"].to_s.match?(/\A\d{6}\z/)
      errors["gross_annual_sales"] = "Enter an amount like 950,000" unless v["gross_annual_sales"].to_s.match?(/\A\d{1,3}(,\d{3})*\z/)
      errors["number_of_employees"] = "Must be a whole number" unless v["number_of_employees"].to_s.match?(/\A[1-9]\d*\z/)
      errors["effective_date"] = "Use MM/DD/YYYY" unless us_date?(v["effective_date"])
      errors["coverages"] = "Select at least one coverage" if Array(v["coverages"]).empty?
      errors
    end

    def us_date?(text)
      m = text.to_s.match(%r{\A(\d{2})/(\d{2})/(\d{4})\z})
      m.present? && Date.valid_date?(m[3].to_i, m[1].to_i, m[2].to_i)
    end
  end
end
