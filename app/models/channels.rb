module Channels
  CLASSES = { "api" => "Channels::Api", "portal" => "Channels::Portal", "email" => "Channels::Email" }.freeze

  def self.for(channel)
    CLASSES.fetch(channel.to_s).constantize
  end

  # Why a submission can't be sent, or nil if it can. The submission JSON is
  # re-validated against the schema before any channel runs.
  def self.refusal(submission)
    return "Submission is not ready to send; build it again" unless submission.ready?
    errors = SubmissionValidator.new.call(submission.submission_json)
    "Submission JSON fails the schema: #{errors.map(&:message).join("; ")}" if errors.any?
  end
end
