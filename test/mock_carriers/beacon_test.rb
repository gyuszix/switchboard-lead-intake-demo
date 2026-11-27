require "test_helper"

class BeaconTest < ActionDispatch::IntegrationTest
  def log_in(password: "beacon-demo")
    post mock_carriers_beacon_login_path, params: { username: "broker", password: password }
  end

  def apply(**overrides)
    post mock_carriers_beacon_applications_path, params: {
      insured_legal_entity: "Golden Crust Bakery LLC", tax_id_no: "36-4829175", street_address: "2150 North Halsted Street",
      zip_code: "60614", naics: "311811", gross_annual_sales: "850,000", number_of_employees: "14",
      effective_date: "01/01/2027", coverages: %w[general_liability property]
    }.merge(overrides)
  end

  test "login is required" do
    get mock_carriers_beacon_new_application_path
    assert_redirected_to mock_carriers_beacon_login_path
    apply
    assert_redirected_to mock_carriers_beacon_login_path
  end

  test "wrong password shows an error, right one opens the application form" do
    log_in(password: "nope")
    assert_select ".alert-error", "Invalid username or password"
    log_in
    follow_redirect!
    assert_select "#signed-in-as"
    assert_select "form#new_application label", "Gross Annual Sales"
    assert_select "input[type=checkbox][name='coverages[]']", 4
  end

  test "quoted result page" do
    log_in
    apply
    assert_select "table#quote-result td", /\ABCN-\d+\z/
    assert_select "table#quote-result td", "$3,825.00" # 850 * 3.00 + 850 * 1.50
  end

  test "declined and referred result pages" do
    log_in
    apply(coverages: %w[general_liability flood])
    assert_select ".alert-error", "Declined: flood not offered"
    apply(gross_annual_sales: "6,000,000")
    assert_select ".alert-error", "Referred: Requires underwriter review"
  end

  test "invalid input shows inline field errors" do
    log_in
    apply(gross_annual_sales: "850000", effective_date: "2027-01-01")
    assert_select ".field-error[data-field=gross_annual_sales]", "Enter an amount like 950,000"
    assert_select ".field-error[data-field=effective_date]", "Use MM/DD/YYYY"
    assert_select "table#quote-result", 0
  end
end
