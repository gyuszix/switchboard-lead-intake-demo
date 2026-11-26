require "test_helper"

class ReviewRulesTest < ActiveSupport::TestCase
  setup { @s = create_sample_submission }

  test "confirm all only touches verified fields" do
    @s.confirm_all_verified!
    @s.reload
    assert @s.verified_fields.all? { _1["resolution"] == "confirmed" }
    assert @s.needs_approval_fields.all? { _1["resolution"].nil? }
    assert_equal 10, @s.resolved_count
  end

  test "approve is blocked on an invalid value" do
    assert_equal "Annual revenue must be a number greater than 0", @s.approve!(:annual_revenue)
    assert_nil @s.reload.field(:annual_revenue)["resolution"]
  end

  test "approve accepts a valid value as-is" do
    assert_nil @s.approve!(:employee_count)
    assert_equal "approved", @s.reload.field(:employee_count)["resolution"]
    assert_equal "45", @s.field(:employee_count)["value"]
  end

  test "edit re-validates the new value" do
    assert_equal "Annual revenue must be a number greater than 0", @s.edit!(:annual_revenue, "lots")
    assert_nil @s.reload.field(:annual_revenue)["resolution"]
  end

  test "edit stores the previous value and normalises the new one" do
    assert_nil @s.edit!(:annual_revenue, "$4,200,000")
    field = @s.reload.field(:annual_revenue)
    assert_equal "edited", field["resolution"]
    assert_equal "4200000", field["value"]
    assert_equal "four point two million", field["original_value"]
  end

  test "mark not provided clears the value" do
    assert_nil @s.mark_not_provided!(:annual_revenue)
    field = @s.reload.field(:annual_revenue)
    assert_equal "not_provided", field["resolution"]
    assert_nil field["value"]
  end

  test "verified fields cannot be approved or cleared" do
    assert_equal "Only fields that need approval can be changed", @s.approve!(:fein)
    assert_equal "Only fields that need approval can be changed", @s.mark_not_provided!(:fein)
  end

  test "editing a verified field sets edited and keeps original_value" do
    assert_nil @s.edit!(:fein, "12-3456789")
    field = @s.reload.field(:fein)
    assert_equal "edited", field["resolution"]
    assert_equal "12-3456789", field["value"]
    assert_equal "82-6150347", field["original_value"]
    assert_equal "verified", field["category"]

    assert_nil @s.edit!(:fein, "98-7654321")
    assert_equal "82-6150347", @s.reload.field(:fein)["original_value"]
  end

  test "editing a confirmed verified field changes it to edited" do
    @s.confirm_all_verified!
    assert_nil @s.edit!(:zip, "60174")
    assert_equal "edited", @s.reload.field(:zip)["resolution"]
  end

  test "confirm all does not overwrite edited verified fields" do
    @s.edit!(:zip, "60174")
    @s.confirm_all_verified!
    @s.reload
    assert_equal "edited", @s.field(:zip)["resolution"]
    assert_equal "confirmed", @s.field(:fein)["resolution"]
  end

  test "invalid edit of a verified field is rejected" do
    assert_equal "ZIP must be 5 digits", @s.edit!(:zip, "601")
    field = @s.reload.field(:zip)
    assert_nil field["resolution"]
    assert_equal "60173", field["value"]
  end

  test "approve and not provided are one-time, but resolved fields stay editable" do
    @s.mark_not_provided!(:employee_count)
    assert_equal "Already resolved", @s.approve!(:employee_count)
    assert_nil @s.edit!(:employee_count, "45")
    field = @s.reload.field(:employee_count)
    assert_equal "edited", field["resolution"]
    assert_equal "45", field["value"]
  end
end
