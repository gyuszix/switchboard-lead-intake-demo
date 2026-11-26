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

  test "verified fields cannot be approved, edited or cleared" do
    assert_equal "Only fields that need approval can be changed", @s.edit!(:fein, "12-3456789")
    assert_equal "Only fields that need approval can be changed", @s.mark_not_provided!(:fein)
  end

  test "resolutions are final" do
    @s.approve!(:employee_count)
    assert_equal "Already resolved", @s.edit!(:employee_count, "50")
  end
end
