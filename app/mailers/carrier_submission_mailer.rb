# Emails a submission to Northwind Specialty with the application PDF attached.
class CarrierSubmissionMailer < ApplicationMailer
  NORTHWIND = "submissions@northwind.test".freeze

  default from: "broker@lead-intake.test"

  def submission
    @submission = params[:submission]
    @json = @submission.submission_json
    attachments["commercial-insurance-application-#{@submission.id}.pdf"] = {
      mime_type: "application/pdf", content: params[:pdf] || SubmissionPdf.new(@submission).render
    }
    mail to: NORTHWIND,
         subject: "New submission ##{@submission.id}: #{@json.dig("applicant", "business_name")}"
  end
end
