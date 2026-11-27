module Channels
  # Emails the submission PDF to Northwind Specialty. There is no reply to
  # wait for: a human at the carrier answers later, outside this app.
  class Email < Base
    def self.channel = "email"

    private

    # Renders the PDF once: the same bytes are attached and kept on the
    # QuoteRequest, so the broker can see exactly what was sent.
    def deliver(_json)
      pdf = SubmissionPdf.new(@submission).render
      CarrierSubmissionMailer.with(submission: @submission, pdf: pdf).submission.deliver_now
      { status: "sent", message: "Awaiting carrier reply", document: pdf }
    end
  end
end
