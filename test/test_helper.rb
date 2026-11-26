ENV["RAILS_ENV"] ||= "test"
# Tests never talk to Ollama: point any accidental call at a closed port.
ENV["OLLAMA_URL"] = "http://127.0.0.1:9"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # A submission built from the IT services sample fixture:
    # 11 verified fields, annual_revenue and employee_count need approval.
    def create_sample_submission
      sample = Sample.all.find { _1[:key] == "it_services" }
      Submission.create!(
        transcript: sample[:transcript],
        fields: FieldChecker.new(sample[:transcript], today: Date.new(2026, 11, 26)).categorise(Sample.fixture_for(sample[:transcript]))
      )
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
