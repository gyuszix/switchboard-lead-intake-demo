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
    assert_includes body, "Brightpath IT Solutions Inc"
    assert_includes body, "Submission ID:  #{@s.id}"
    assert_includes body, "cyber liability, professional liability, general liability"
    assert_includes body, "2027-02-15"
  end

  test "channel delivers the email and saves a sent QuoteRequest" do
    qr = Channels::Email.new.call(@s)
    assert_equal 1, ActionMailer::Base.deliveries.size
    assert qr.persisted?
    assert_equal ["sent", "Awaiting carrier reply", "Northwind Specialty", "email"],
                 [qr.status, qr.message, qr.carrier, qr.channel]
  end

  test "channel is refused when the submission is not ready" do
    @s.edit!(:zip, "60174")
    qr = Channels::Email.new.call(@s)
    assert_not qr.persisted?
    assert_empty ActionMailer::Base.deliveries
  end
end
