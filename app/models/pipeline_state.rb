# Works out what the pipeline bar at the bottom of every page shows: which
# step the submission is on, and whether each step is pending, active, done or
# failed. Channel steps show their latest quote request status instead.
class PipelineState
  Step = Data.define(:key, :label, :actor, :actor_label, :gate, :title) do
    def channel? = key.start_with?("channel_")
  end

  STEPS = [
    Step.new("transcript", "Transcript", :input, "Input", false,
             "The call transcript pasted by the broker. Every extracted value is checked against it"),
    Step.new("extract", "Extract fields", :ai, "AI (Granite)", false,
             "A local Granite model proposes a value and a supporting quote for each field. Its output is a claim, never trusted on its own"),
    Step.new("transcript_check", "Transcript check", :code, "Code", true,
             "Quote exists in transcript, value appears in quote, format rules, no conflicting mentions. Advisory: sorts fields into Verified / Needs approval"),
    Step.new("review", "Broker review", :human, "Human", true,
             "A human approves, edits or marks every field. Nothing proceeds until every field is resolved"),
    Step.new("build", "Build JSON", :code, "Code", false,
             "Turns the approved values into typed submission JSON: whole numbers, a coverage list, an ISO date"),
    Step.new("schema", "Schema check", :code, "Code", true,
             "Submission JSON must match the schema: all fields present, correct types and formats. Blocking"),
    Step.new("channel", "Choose channel", :human, "Human", false,
             "The broker chooses which carrier to send the validated submission to")
  ].freeze

  CHANNELS = [
    Step.new("channel_api", "Acme API", :code, "Code", false,
             "Posts the submission JSON to Acme's API and reads the quote from the response"),
    Step.new("channel_portal", "Beacon bot", :code, "Code", false,
             "A bot logs in to Beacon's portal, fills the form from the submission JSON and reads the result page"),
    Step.new("channel_email", "Northwind email", :code, "Code", false,
             "Emails the submission PDF to Northwind. A person there replies later, outside this app")
  ].freeze

  # page: :paste, :review, :ready, or nil for any other page (all pending).
  def initialize(page:, submission: nil, build_failed: false)
    @states = case page
    when :paste
      { "transcript" => "active" }
    when :review
      states = done(%w[transcript extract transcript_check]).merge("review" => "active")
      build_failed ? states.merge("build" => "done", "schema" => "failed") : states
    when :ready
      done(%w[transcript extract transcript_check review build schema]).merge("channel" => "active").merge(latest_channel_statuses(submission))
    else
      {}
    end
  end

  def steps = STEPS
  def channels = CHANNELS

  # "pending", "active", "done" or "failed"; channel steps: the latest quote
  # request status (quoted, declined, referred, sent, failed) or "pending".
  def state(key) = @states.fetch(key, "pending")

  private

  def done(keys) = keys.index_with("done")

  def latest_channel_statuses(submission)
    return {} unless submission
    submission.quote_requests.to_a.group_by(&:channel).to_h do |channel, requests|
      ["channel_#{channel}", requests.max_by { [_1.created_at || Time.current, _1.id || 0] }.status]
    end
  end
end
