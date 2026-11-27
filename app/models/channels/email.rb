module Channels
  # Emails the submission PDF to Northwind Specialty. There is no reply to
  # wait for: a human at the carrier answers later, outside this app.
  class Email < Base
    def self.channel = "email"

    private

    # Records the email exactly as delivered: its headers, plain-text body and
    # attachment name as JSON (in the column the API channel uses for what it
    # sent), and the attached PDF's bytes as the document.
    def deliver(_json)
      pdf = SubmissionPdf.new(@submission).render
      mail = CarrierSubmissionMailer.with(submission: @submission, pdf: pdf).submission.deliver_now
      attachment = mail.attachments.first
      sent = {
        from: mail[:from].to_s, to: mail[:to].to_s, subject: mail.subject, date: mail[:date].to_s,
        body: mail.text_part.body.decoded, attachment: attachment.filename
      }
      { status: "sent", message: "Awaiting carrier reply", document: attachment.body.decoded, request_body: sent.to_json }
    end
  end
end
