ENV["RAILS_ENV"] ||= "test"
# Tests never talk to Ollama: point any accidental call at a closed port.
ENV["OLLAMA_URL"] = "http://127.0.0.1:9"
# ...and never reach the mock carriers over the network either.
ENV["MOCK_CARRIER_BASE_URL"] = "http://127.0.0.1:9"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # A submission built from the Hudson Millwork sample fixture (today 2026-11-26):
    # 5 verified fields; fein, zip, naics_code, years_in_business, annual_revenue,
    # employee_count, effective_date and contact_email need approval.
    def create_sample_submission
      sample = Sample.all.find { _1[:key] == "hudson_millwork" }
      Submission.create!(
        transcript: sample[:transcript],
        fields: FieldChecker.new(sample[:transcript], today: Date.new(2026, 11, 26)).categorise(Sample.fixture_for(sample[:transcript]))
      )
    end

    # Resolves every field of the Hudson sample the way a broker would.
    # revenue: nil marks annual revenue not provided, which fails the schema.
    def resolve_sample(s, revenue: "5400000")
      s.confirm_all_verified!
      s.edit!(:fein, "81-4420976")
      s.approve!(:zip)
      s.edit!(:naics_code, "337110")
      s.approve!(:years_in_business)
      revenue ? s.edit!(:annual_revenue, revenue) : s.mark_not_provided!(:annual_revenue)
      s.approve!(:employee_count)
      s.approve!(:effective_date)
      s.approve!(:contact_email)
    end

    # The Hudson sample, fully reviewed and built: ready to send.
    def create_ready_submission
      s = create_sample_submission
      resolve_sample(s)
      raise "sample did not build" unless s.build_submission!.empty?
      s
    end

    # Replaces Extractor#call for the duration of the block.
    def stub_extractor(fields, used_fixtures: false)
      result = Extractor::Result.new(fields: fields, used_fixtures: used_fixtures)
      Extractor.alias_method :__real_call, :call
      Extractor.define_method(:call) { |_transcript| result }
      yield
    ensure
      Extractor.alias_method :call, :__real_call
      Extractor.remove_method :__real_call
    end
  end
end
