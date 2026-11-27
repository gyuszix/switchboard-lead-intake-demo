require "mechanize"

module Channels
  # Gets a quote from Beacon Mutual by driving its broker portal with a
  # Mechanize bot: log in, fill the application form, parse the result page.
  # Depends on Beacon's page layout; anything unexpected is a failure.
  class Portal < Base
    TIMEOUT = 15

    # Our coverage names → Beacon's checkbox labels. Anything else is matched
    # against the labels as-is.
    COVERAGE_LABELS = {
      "general liability" => "General Liability",
      "commercial property" => "Property",
      "property" => "Property",
      "workers compensation" => "Workers Comp",
      "workers' compensation" => "Workers Comp",
      "workers comp" => "Workers Comp",
      "professional liability" => "Professional Liability"
    }.freeze

    # Where each Beacon form field's value comes from in the submission JSON.
    SOURCES = {
      "insured_legal_entity" => "applicant.business_name",
      "tax_id_no" => "applicant.fein",
      "street_address" => "applicant.address",
      "zip_code" => "applicant.zip",
      "naics" => "operations.naics_code",
      "gross_annual_sales" => "operations.annual_revenue",
      "number_of_employees" => "operations.employee_count",
      "effective_date" => "coverage.effective_date"
    }.freeze
    SNIPPET_LENGTH = 300

    Failure = Class.new(StandardError)

    def self.channel = "portal"

    def initialize(base_url: ENV.fetch("MOCK_CARRIER_BASE_URL", "http://localhost:3000"),
                   username: ENV.fetch("BEACON_USERNAME", "broker"),
                   password: ENV.fetch("BEACON_PASSWORD", "beacon-demo"))
      @base = "#{base_url.chomp("/")}/mock_carriers/beacon"
      @username = username
      @password = password
    end

    # What the bot did and read on this run: HTTP steps (method, path, status),
    # filled fields, coverages and scraped values. Never holds the password or
    # cookies.
    def record
      @record ||= { steps: [], filled: [], coverages: { ticked: [], unmatched: [] }, scraped: [] }
    end

    # Submission JSON → Beacon's form field names and formats.
    def form_values(json)
      {
        "insured_legal_entity" => json.dig("applicant", "business_name"),
        "tax_id_no" => json.dig("applicant", "fein"),
        "street_address" => json.dig("applicant", "address"),
        "zip_code" => json.dig("applicant", "zip"),
        "naics" => json.dig("operations", "naics_code"),
        "gross_annual_sales" => ActiveSupport::NumberHelper.number_to_delimited(json.dig("operations", "annual_revenue")),
        "number_of_employees" => json.dig("operations", "employee_count").to_s,
        "effective_date" => Date.iso8601(json.dig("coverage", "effective_date")).strftime("%m/%d/%Y")
      }
    end

    # Ticks a checkbox for each coverage by matching its label text. Raises
    # Failure, before anything is submitted, if a coverage has no checkbox.
    def tick_coverages(page, form, coverages)
      coverages.each do |name|
        wanted = COVERAGE_LABELS.fetch(name.to_s.strip.downcase, name.to_s.strip)
        label = page.search("label").find { _1.text.strip.casecmp?(wanted) }
        checkbox = label && form.checkbox_with(id: label["for"])
        if checkbox
          checkbox.check
          record[:coverages][:ticked] << { name: name, label: label.text.strip }
        else
          record[:coverages][:unmatched] << name
        end
      end
      if (missing = record[:coverages][:unmatched].first)
        raise Failure, "Coverage '#{missing}' not available on Beacon portal"
      end
    end

    # Result page → QuoteRequest attributes.
    def parse_result(page)
      if (table = page.at("table#quote-result"))
        tr = ->(heading) { table.search("tr").find { _1.at("th")&.text&.strip == heading } }
        row = ->(heading) { tr.(heading)&.at("td")&.text&.strip }
        premium = row.("Premium").to_s
        unless row.("Status") == "Quoted" && row.("Reference").present? && premium.match?(/\A\$[\d,]+(\.\d{2})?\z/)
          return failed("Unrecognised quote table on Beacon result page")
        end
        result = { status: "quoted", reference: row.("Reference"), premium: premium.delete("$,").to_d.round.to_i,
                   message: "Quoted via Beacon portal" }
        scrape("Status", result[:status], tr.("Status"))
        scrape("Reference", result[:reference], tr.("Reference"))
        scrape("Premium", result[:premium], tr.("Premium"))
        result
      elsif (banner = page.at(".alert-error")) && (m = banner.text.strip.match(/\A(Declined|Referred):\s*(.+)\z/m))
        scrape("Status", m[1].downcase, banner)
        scrape("Reason", m[2].strip, banner)
        { status: m[1].downcase, message: m[2].strip }
      elsif (errors = page.search(".field-error")).any?
        errors.each { scrape("Error on #{_1["data-field"]}", _1.text.strip, _1) }
        failed("Beacon rejected the form: " + errors.map { "#{_1["data-field"]} #{_1.text.strip.downcase_first}" }.join("; "))
      else
        failed("Unrecognised result page from Beacon portal")
      end
    end

    private

    # Runs the bot, then stores its record as JSON in the same columns the API
    # channel uses: steps and filled fields as sent, scraped values as received.
    def deliver(json)
      attrs = drive(json)
      record[:steps][-1] += " → no response" if @awaiting_response
      record[:steps] << "Stopped: #{attrs[:message]}" if attrs[:status] == "failed"
      attrs.merge(request_body: record.slice(:steps, :filled, :coverages).to_json,
                  response_body: (record.slice(:scraped).to_json if record[:scraped].any?))
    end

    def drive(json)
      agent = Mechanize.new { _1.open_timeout = TIMEOUT; _1.read_timeout = TIMEOUT }
      watch(agent)
      page = log_in(agent)
      record[:steps] << "Logged in as #{@username}"

      form = page.form_with(id: "new_application") or raise Failure, "Application form not found on Beacon portal"
      form_values(json).each do |name, value|
        field = form.field_with(name: name) or raise Failure, "Field '#{name}' not found on Beacon application form"
        field.value = value
        record[:filled] << { label: page.at("label[for='#{field.node["id"]}']")&.text&.strip,
                             name: name, value: value, source: SOURCES[name] }
      end
      record[:steps] << "Filled #{record[:filled].size} fields"
      tick_coverages(page, form, Array(json.dig("coverage", "coverage_types")))
      record[:steps] << "Ticked #{record[:coverages][:ticked].size} coverages"

      parse_result(form.submit)
    rescue Failure => e
      failed(e.message)
    rescue Mechanize::ResponseCodeError => e
      failed("Beacon portal returned HTTP #{e.response_code}")
    rescue Net::OpenTimeout, Net::ReadTimeout
      failed("Beacon portal timed out after #{TIMEOUT}s")
    rescue SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError, Net::HTTP::Persistent::Error => e
      failed("Could not connect to Beacon portal (#{e.class.name.demodulize})")
    end

    # Records each HTTP request's method and path, and its response status.
    # Headers (and so cookies) and request bodies (and so the password) are
    # never recorded.
    def watch(agent)
      agent.pre_connect_hooks << lambda do |_agent, request|
        record[:steps] << "#{request.method} #{request.path}"
        @awaiting_response = true
      end
      agent.post_connect_hooks << lambda do |_agent, _uri, response, _body|
        record[:steps][-1] += " → #{response.code}"
        @awaiting_response = false
      end
    end

    def scrape(label, value, node)
      record[:scraped] << { label: label, value: value, html: node.to_html.strip.truncate(SNIPPET_LENGTH) }
    end

    def log_in(agent)
      login = agent.get("#{@base}/login")
      form = login.form_with(id: "login") or raise Failure, "Login form not found on Beacon portal"
      form["username"] = @username
      form["password"] = @password
      page = form.submit
      return page if page.at("#signed-in-as")

      error = page.at(".alert-error")&.text&.strip
      raise Failure, "Beacon login failed#{": #{error}" if error}"
    end

    def failed(message) = { status: "failed", message: message }
  end
end
