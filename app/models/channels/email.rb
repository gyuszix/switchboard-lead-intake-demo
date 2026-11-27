module Channels
  # Emails the submission PDF to Northwind Specialty. There is no reply to
  # wait for: a human at the carrier answers later, outside this app.
  class Email < Base
    def self.channel = "email"

    private

    def deliver(_json)
      CarrierSubmissionMailer.with(submission: @submission).submission.deliver_now
      { status: "sent", message: "Awaiting carrier reply" }
    end
  end
end
