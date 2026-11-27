require "test_helper"

class AcmeTest < ActionDispatch::IntegrationTest
  def body(**overrides)
    {
      insured_name: "Brightpath IT Solutions Inc", tax_id: "82-6150347", street_address: "400 Commerce Drive",
      postal_code: "60173", naics: "541512", annual_revenue: 4_200_000, employees: 45,
      coverages: [ "cyber", "professional liability", "general liability" ], effective_date: "2027-02-15"
    }.merge(overrides)
  end

  def quote(payload = body, token: "acme-demo-token")
    headers = { "Content-Type" => "application/json" }
    headers["Authorization"] = "Bearer #{token}" if token
    post mock_carriers_acme_quotes_path, params: payload.to_json, headers: headers
    response.parsed_body
  end

  test "missing or wrong token is 401" do
    assert_equal({ "error" => "unauthorized" }, quote(token: nil))
    assert_response :unauthorized
    quote(token: "nope")
    assert_response :unauthorized
  end

  test "missing field or wrong type is 422 with details" do
    json = quote(body(employees: "45").except(:tax_id))
    assert_response :unprocessable_entity
    assert_equal "invalid", json["error"]
    assert_equal [ "tax_id is required", "employees must be an integer" ], json["details"]
  end

  test "test outage business name is 503" do
    assert_equal({ "error" => "service unavailable" }, quote(body(insured_name: "Acme Test Outage")))
    assert_response :service_unavailable
  end

  test "unoffered coverage is declined" do
    assert_equal({ "status" => "declined", "reason" => "flood not offered" }, quote(body(coverages: [ "cyber", "flood" ])))
    assert_response :ok
  end

  test "revenue over 5,000,000 is referred" do
    assert_equal({ "status" => "referred", "reason" => "Requires underwriter review" }, quote(body(annual_revenue: 5_000_001)))
    assert_response :ok
  end

  test "otherwise quoted with premium and validity" do
    json = quote
    assert_response :created
    assert_equal "quoted", json["status"]
    assert_match(/\AACM-\d+\z/, json["quote_id"])
    assert_equal 1_200 + 8_400 + 12_600, json["premium"]
    assert_equal (Date.current + 30).iso8601, json["valid_until"]
  end
end
