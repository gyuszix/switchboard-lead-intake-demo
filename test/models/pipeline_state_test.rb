require "test_helper"

class PipelineStateTest < ActiveSupport::TestCase
  def states(pipeline) = (pipeline.steps + pipeline.channels).to_h { [ _1.key, pipeline.state(_1.key) ] }

  test "steps run in order with their actors and gates" do
    pipeline = PipelineState.new(page: nil)
    assert_equal [ "Transcript", "Extract fields", "Transcript check", "Broker review", "Build JSON", "Schema check", "Choose channel" ],
                 pipeline.steps.map(&:label)
    assert_equal [ "Input", "AI (Granite)", "Code", "Human", "Code", "Code", "Human" ], pipeline.steps.map(&:actor_label)
    assert_equal %w[transcript_check review schema], (pipeline.steps + pipeline.channels).select(&:gate).map(&:key)
    assert_equal [ "Acme API", "Beacon bot", "Northwind email" ], pipeline.channels.map(&:label)
    assert pipeline.channels.all? { _1.actor_label == "Code" && _1.channel? }
  end

  test "paste page: Transcript is active, everything else pending" do
    s = states(PipelineState.new(page: :paste))
    assert_equal "active", s.delete("transcript")
    assert s.values.all?("pending")
  end

  test "review page: extraction and transcript check done, broker review active" do
    s = states(PipelineState.new(page: :review, submission: create_sample_submission))
    assert_equal %w[done done done active pending pending pending],
                 s.values_at(*%w[transcript extract transcript_check review build schema channel])
    assert_equal %w[pending] * 3, s.values_at(*%w[channel_api channel_portal channel_email])
  end

  test "review page after a failed build: schema check failed, broker review still active" do
    s = states(PipelineState.new(page: :review, build_failed: true))
    assert_equal %w[active done failed pending], s.values_at(*%w[review build schema channel])
  end

  test "ready page: everything up to the schema check done, choose channel active" do
    s = states(PipelineState.new(page: :ready, submission: create_ready_submission))
    assert_equal %w[done] * 6, s.values_at(*%w[transcript extract transcript_check review build schema])
    assert_equal "active", s["channel"]
    assert_equal %w[pending] * 3, s.values_at(*%w[channel_api channel_portal channel_email])
  end

  test "each channel shows its latest quote request status" do
    sub = create_ready_submission
    add = ->(channel, status, at) { sub.quote_requests.create!(channel: channel, carrier: QuoteRequest::CARRIERS[channel], status: status, created_at: at) }
    add.("api", "failed", 2.minutes.ago)
    add.("api", "quoted", 1.minute.ago)
    add.("portal", "referred", 1.minute.ago)
    add.("email", "sent", 1.minute.ago)
    s = states(PipelineState.new(page: :ready, submission: sub.reload))
    assert_equal %w[quoted referred sent], s.values_at(*%w[channel_api channel_portal channel_email])

    add.("portal", "declined", Time.current)
    add.("email", "failed", Time.current)
    s = states(PipelineState.new(page: :ready, submission: sub.reload))
    assert_equal %w[quoted declined failed], s.values_at(*%w[channel_api channel_portal channel_email])
  end
end
