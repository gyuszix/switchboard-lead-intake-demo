module MockCarriers
  # The only code the fake carriers share. Deterministic: the same submission
  # always gets the same result. Coverage names are each carrier's own
  # vocabulary, matched case-insensitively after trimming.
  module Pricing
    PER_THOUSAND_REVENUE = {
      "general liability" => 3.00,
      "professional liability" => 2.00,
      "property" => 1.50
    }.freeze
    PER_EMPLOYEE = { "workers comp" => 900 }.freeze
    FLAT = { "commercial auto" => 1_500, "cyber" => 1_200 }.freeze
    OFFERED = (PER_THOUSAND_REVENUE.keys + PER_EMPLOYEE.keys + FLAT.keys).freeze

    REFERRAL_REVENUE = 5_000_000

    def self.key(coverage) = coverage.to_s.strip.downcase

    def self.offered?(coverage) = OFFERED.include?(key(coverage))

    def self.premium(coverages:, revenue:, employees:)
      total = coverages.sum do |coverage|
        k = key(coverage)
        if PER_THOUSAND_REVENUE.key?(k) then PER_THOUSAND_REVENUE[k] * revenue / 1000.0
        elsif PER_EMPLOYEE.key?(k) then PER_EMPLOYEE[k] * employees
        elsif FLAT.key?(k) then FLAT[k]
        else raise ArgumentError, "#{coverage} not offered"
        end
      end
      total.round
    end

    # The underwriting decision both carriers use, in order:
    # decline unoffered coverage, refer large revenue, otherwise quote.
    def self.decide(coverages:, revenue:, employees:)
      if (missing = coverages.find { !offered?(_1) })
        { status: "declined", reason: "#{missing.to_s.strip} not offered" }
      elsif revenue > REFERRAL_REVENUE
        { status: "referred", reason: "Requires underwriter review" }
      else
        { status: "quoted", premium: premium(coverages: coverages, revenue: revenue, employees: employees) }
      end
    end
  end
end
