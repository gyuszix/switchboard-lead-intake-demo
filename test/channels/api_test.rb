require "test_helper"

class ApiChannelTest < ActiveSupport::TestCase
  setup { @s = create_ready_submission }

  # A transport that records the request and returns a canned response (or raises).
  def channel(code: 201, body: {}, raises: nil)
    @sent = nil
    transport = lambda do |url, json, headers|
      @sent = { url: url, json: JSON.parse(json), headers: headers }
      raise raises if raises
      Channels::Api::Response.new(code, body.to_json)
    end
    Channels::Api.new(transport: transport, base_url: "http://carrier.test", token: "t0k")
  end

  test "maps the submission to Acme field names and sends the token" do
    channel(body: { status: "quoted", quote_id: "ACM-1", premium: 1, valid_until: "2027-01-01" }).call(@s)
    assert_equal "http://carrier.test/mock_carriers/acme/api/v1/quotes", @sent[:url]
    assert_equal "Bearer t0k", @sent[:headers]["Authorization"]
    assert_equal({
      "insured_name" => "Hudson Millwork LLC", "tax_id" => "81-4420976",
      "street_address" => "77 Paterson Plank Road, Carlstadt, New Jersey", "postal_code" => "07072",
      "naics" => "337110", "annual_revenue" => 5_400_000, "employees" => 41,
      "coverages" => ["general liability", "property", "workers comp"], "effective_date" => "2027-04-01"
    }, @sent[:json])
  end

  test "translates coverage synonyms to Acme's vocabulary" do
    json = { "coverage" => { "coverage_types" => ["Workers Compensation", "commercial property", "General liability"] } }
    assert_equal ["workers comp", "property", "General liability"], Channels::Api.new.payload(json)["coverages"]
  end

  test "quoted" do
    qr = channel(code: 201, body: { status: "quoted", quote_id: "ACM-42", premium: 22_200, valid_until: "2026-12-26" }).call(@s)
    assert qr.persisted?
    assert_equal ["quoted", 22_200, "ACM-42", "Valid until 2026-12-26", "Acme Insurance", "api"],
                 [qr.status, qr.premium, qr.reference, qr.message, qr.carrier, qr.channel]
  end

  test "declined and referred" do
    qr = channel(code: 200, body: { status: "declined", reason: "flood not offered" }).call(@s)
    assert_equal ["declined", "flood not offered"], [qr.status, qr.message]
    qr = channel(code: 200, body: { status: "referred", reason: "Requires underwriter review" }).call(@s)
    assert_equal ["referred", "Requires underwriter review"], [qr.status, qr.message]
  end

  test "401, 422 and 503 are failed with a clear message" do
    assert_equal "Acme rejected the API token (401)", channel(code: 401, body: { error: "unauthorized" }).call(@s).message
    qr = channel(code: 422, body: { error: "invalid", details: ["tax_id is required"] }).call(@s)
    assert_equal ["failed", "Acme rejected the request (422): tax_id is required"], [qr.status, qr.message]
    assert_equal "Acme API unavailable (503)", channel(code: 503, body: { error: "service unavailable" }).call(@s).message
  end

  test "records what was sent and received, without the token" do
    qr = channel(code: 201, body: { status: "quoted", quote_id: "ACM-42", premium: 22_200, valid_until: "2026-12-26" }).call(@s)
    assert qr.request_body.start_with?("POST http://carrier.test/mock_carriers/acme/api/v1/quotes\n")
    assert_includes qr.request_body, "Authorization: Bearer [hidden]"
    assert_not_includes qr.request_body, "t0k"
    assert_includes qr.request_body, %("insured_name": "Hudson Millwork LLC")
    assert qr.response_body.start_with?("HTTP 201\n\n")
    assert_includes qr.response_body, %("quote_id": "ACM-42")

    qr = channel(code: 401, body: { error: "unauthorized" }).call(@s)
    assert_includes qr.response_body, "HTTP 401"
  end

  test "timeouts and connection errors are failed, never raised" do
    qr = channel(raises: Net::ReadTimeout).call(@s)
    assert_equal ["failed", "Acme API timed out after 15s"], [qr.status, qr.message]
    assert qr.request_body.present?
    assert_nil qr.response_body
    qr = channel(raises: Errno::ECONNREFUSED).call(@s)
    assert_equal ["failed", "Could not connect to Acme API (ECONNREFUSED)"], [qr.status, qr.message]
  end

  test "garbage response is failed" do
    transport = ->(*) { Channels::Api::Response.new(200, "<html>oops</html>") }
    qr = Channels::Api.new(transport: transport).call(@s)
    assert_equal ["failed", "Unexpected response from Acme API (HTTP 200)"], [qr.status, qr.message]
  end

  test "refused, and nothing sent, when the submission is not ready" do
    @s.edit!(:zip, "60174")
    qr = channel.call(@s)
    assert_not qr.persisted?
    assert_equal "failed", qr.status
    assert_nil @sent
  end
end
