module Channels
  # A channel sends a ready submission to one carrier and records the outcome
  # as a QuoteRequest. Subclasses implement #deliver and never raise to the UI.
  class Base
    def self.channel = raise(NotImplementedError)

    def call(submission)
      if (reason = Channels.refusal(submission))
        return QuoteRequest.new(submission: submission, channel: self.class.channel,
                                carrier: carrier, status: "failed", message: reason)
      end

      @submission = submission
      attrs = begin
        deliver(submission.submission_json)
      rescue StandardError => e
        { status: "failed", message: "Unexpected error: #{e.class}: #{e.message}" }
      end
      submission.quote_requests.create!(channel: self.class.channel, carrier: carrier, **attrs)
    end

    private

    def carrier = QuoteRequest::CARRIERS.fetch(self.class.channel)

    # Returns QuoteRequest attributes: status, premium, reference, message.
    def deliver(json) = raise(NotImplementedError)
  end
end
