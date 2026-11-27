require "test_helper"

class EmailChannelTest < ActiveSupport::TestCase
  setup do
    ActionMailer::Base.deliveries.clear
    @s = create_ready_submission
  end

  test "mailer sends to Northwind with the PDF attached and a plain-text summary" do
    mail = CarrierSubmissionMailer.with(submission: @s).submission
    assert_equal ["submissions@northwind.test"], mail.to
    assert_equal 1, mail.attachments.size
    assert_equal "application/pdf", mail.attachments.first.mime_type
    assert mail.attachments.first.body.decoded.start_with?("%PDF")
    body = mail.text_part.body.decoded
    assert_includes body, "Hudson Millwork LLC"
    assert_includes body, "Submission ID:  #{@s.id}"
    assert_includes body, "general liability, property, workers comp"
    assert_includes body, "2027-04-01"
  end

  test "channel delivers the email and saves a sent QuoteRequest" do
    qr = Channels::Email.new.call(@s)
    assert_equal 1, ActionMailer::Base.deliveries.size
    assert qr.persisted?
    assert_equal ["sent", "Awaiting carrier reply", "Northwind Specialty", "email"],
                 [qr.status, qr.message, qr.carrier, qr.channel]
  end

  test "channel records the email as it was sent" do
    qr = Channels::Email.new.call(@s)
    mail = ActionMailer::Base.deliveries.last
    sent = qr.reload.request_data
    assert_equal "broker@lead-intake.test", sent["from"]
    assert_equal "submissions@northwind.test", sent["to"]
    assert_equal "New submission ##{@s.id}: Hudson Millwork LLC", sent["subject"]
    assert_equal mail[:date].to_s, sent["date"]
    assert sent["date"].present?
    assert_equal mail.text_part.body.decoded, sent["body"]
    assert_includes sent["body"], "Please find attached a commercial insurance application"
    assert_equal "commercial-insurance-application-#{@s.id}.pdf", sent["attachment"]
    assert_nil qr.response_body
  end

  test "the attached PDF is the one kept on the QuoteRequest" do
    qr = Channels::Email.new.call(@s)
    attached = ActionMailer::Base.deliveries.last.attachments.first.body.decoded
    assert qr.reload.document.start_with?("%PDF")
    assert_equal attached.b, qr.document.b
  end

  test "letter_opener is gone, so sending never opens a browser tab" do
    refute_match(/letter_opener/, Rails.root.join("Gemfile").read)
    assert_equal :test, ActionMailer::Base.delivery_method
  end

  test "channel is refused when the submission is not ready" do
    @s.edit!(:zip, "60174")
    qr = Channels::Email.new.call(@s)
    assert_not qr.persisted?
    assert_empty ActionMailer::Base.deliveries
  end
end
