require "test_helper"

class PricingTest < ActiveSupport::TestCase
  P = MockCarriers::Pricing

  def premium(coverages, revenue: 1_000_000, employees: 10)
    P.premium(coverages: coverages, revenue: revenue, employees: employees)
  end

  test "each coverage rate" do
    assert_equal 3_000, premium([ "general liability" ])
    assert_equal 2_000, premium([ "professional liability" ])
    assert_equal 1_500, premium([ "property" ])
    assert_equal 9_000, premium([ "workers comp" ])
    assert_equal 1_500, premium([ "commercial auto" ])
    assert_equal 1_200, premium([ "cyber" ])
  end

  test "rounds to whole dollars" do
    assert_equal 3_704, premium([ "general liability" ], revenue: 1_234_567) # 3703.701
    assert_equal 1_852, premium([ "property" ], revenue: 1_234_567)          # 1851.8505
  end

  test "matches coverages case-insensitively after trimming" do
    assert_equal 4_200, premium([ "  General Liability ", "CYBER" ])
  end

  test "decision: decline, refer, quote" do
    assert_equal({ status: "declined", reason: "flood not offered" },
                 P.decide(coverages: [ "cyber", " flood " ], revenue: 9_000_000, employees: 1))
    assert_equal({ status: "referred", reason: "Requires underwriter review" },
                 P.decide(coverages: [ "cyber" ], revenue: 5_000_001, employees: 1))
    assert_equal({ status: "quoted", premium: 1_200 }, P.decide(coverages: [ "cyber" ], revenue: 5_000_000, employees: 1))
  end
end
