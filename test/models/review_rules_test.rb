require "test_helper"

class ReviewRulesTest < ActiveSupport::TestCase
  setup { @s = create_sample_submission }

  test "confirm all only touches verified fields" do
    @s.confirm_all_verified!
    @s.reload
    assert @s.verified_fields.all? { _1["resolution"] == "confirmed" }
    assert @s.needs_approval_fields.all? { _1["resolution"].nil? }
    assert_equal 5, @s.resolved_count
  end

  test "approve is blocked on an invalid value" do
    assert_equal "Annual revenue must be a number greater than 0", @s.approve!(:annual_revenue)
    assert_nil @s.reload.field(:annual_revenue)["resolution"]
  end

  test "approve accepts a valid value as-is" do
    assert_nil @s.approve!(:employee_count)
    assert_equal "approved", @s.reload.field(:employee_count)["resolution"]
    assert_equal "41", @s.field(:employee_count)["value"]
  end

  test "edit re-validates the new value" do
    assert_equal "Annual revenue must be a number greater than 0", @s.edit!(:annual_revenue, "lots")
    assert_nil @s.reload.field(:annual_revenue)["resolution"]
  end

  test "edit stores the previous value and normalises the new one" do
    assert_nil @s.edit!(:annual_revenue, "$5,400,000")
    field = @s.reload.field(:annual_revenue)
    assert_equal "edited", field["resolution"]
    assert_equal "5400000", field["value"]
    assert_equal "Five point four million", field["original_value"]
  end

  test "mark not provided clears the value" do
    assert_nil @s.mark_not_provided!(:annual_revenue)
    field = @s.reload.field(:annual_revenue)
    assert_equal "not_provided", field["resolution"]
    assert_nil field["value"]
  end

  test "verified fields cannot be approved or cleared" do
    assert_equal "Only fields that need approval can be changed", @s.approve!(:business_name)
    assert_equal "Only fields that need approval can be changed", @s.mark_not_provided!(:business_name)
  end

  test "editing a verified field sets edited and keeps original_value" do
    assert_nil @s.edit!(:business_name, "Hudson Millwork Inc")
    field = @s.reload.field(:business_name)
    assert_equal "edited", field["resolution"]
    assert_equal "Hudson Millwork Inc", field["value"]
    assert_equal "Hudson Millwork LLC", field["original_value"]
    assert_equal "verified", field["category"]

    assert_nil @s.edit!(:business_name, "Hudson Millwork Co")
    assert_equal "Hudson Millwork LLC", @s.reload.field(:business_name)["original_value"]
  end

  test "editing a confirmed verified field changes it to edited" do
    @s.confirm_all_verified!
    assert_nil @s.edit!(:address, "79 Paterson Plank Road, Carlstadt, New Jersey")
    assert_equal "edited", @s.reload.field(:address)["resolution"]
  end

  test "confirm all does not overwrite edited verified fields" do
    @s.edit!(:address, "79 Paterson Plank Road, Carlstadt, New Jersey")
    @s.confirm_all_verified!
    @s.reload
    assert_equal "edited", @s.field(:address)["resolution"]
    assert_equal "confirmed", @s.field(:business_name)["resolution"]
  end

  test "invalid edit of a verified field is rejected" do
    assert_equal "Value is blank", @s.edit!(:address, " ")
    field = @s.reload.field(:address)
    assert_nil field["resolution"]
    assert_equal "77 Paterson Plank Road, Carlstadt, New Jersey", field["value"]
  end

  test "approve and not provided are one-time, but resolved fields stay editable" do
    @s.mark_not_provided!(:employee_count)
    assert_equal "Already resolved", @s.approve!(:employee_count)
    assert_nil @s.edit!(:employee_count, "41")
    field = @s.reload.field(:employee_count)
    assert_equal "edited", field["resolution"]
    assert_equal "41", field["value"]
  end
end
