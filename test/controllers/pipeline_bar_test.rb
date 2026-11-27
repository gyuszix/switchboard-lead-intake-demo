require "test_helper"

class PipelineBarTest < ActionDispatch::IntegrationTest
  test "every page renders the bar with actor labels and gate markers" do
    get root_path
    assert_select "nav#pipeline.pipeline[aria-label=?]", "Submission pipeline" do
      assert_select ".pipeline-step", 10
      assert_select ".pipeline-step .pipeline-actor", text: /AI \(Granite\)/, count: 1
      assert_select ".pipeline-step .pipeline-actor", text: /Human/, count: 2
      assert_select ".pipeline-step .pipeline-actor", text: /Code/, count: 6
      assert_select ".pipeline-step .pipeline-actor", text: /Input/, count: 1
      assert_select ".pipeline-step .pipeline-actor svg.pipeline-icon", 10
      assert_select ".pipeline-step.gate", 3
      assert_select ".pipeline-step.gate .pipeline-gate-icon", 3
      assert_select ".pipeline-step:not(.gate) .pipeline-gate-icon", 0
      assert_select ".pipeline-step.gate .gate-tag", text: "GATE", count: 3
      assert_select ".pipeline-step:not(.gate) .gate-tag", 0
      assert_select ".pipeline-step.gate[data-pipeline-key=transcript_check][title=?]",
                    "Quote exists in transcript, value appears in quote, format rules, no conflicting mentions. Advisory: sorts fields into Verified / Needs approval"
      assert_select ".pipeline-step.gate[data-pipeline-key=review][title=?]",
                    "A human approves, edits or marks every field. Nothing proceeds until every field is resolved"
      assert_select ".pipeline-step.gate[data-pipeline-key=schema][title=?]",
                    "Submission JSON must match the schema: all fields present, correct types and formats. Blocking"
      assert_select ".pipeline-step:not([title])", 0
      assert_select "[aria-current=step]", 1
      assert_select ".pipeline-step.state-active[data-pipeline-key=transcript][aria-current=step]"
    end
  end

  test "each step renders with its actor class" do
    get root_path
    actors = css_select("#pipeline .pipeline-step").to_h { [_1["data-pipeline-key"], _1["class"].split.grep(/\Aactor-/)] }
    assert_equal({ "transcript" => ["actor-input"], "extract" => ["actor-ai"], "transcript_check" => ["actor-code"],
                   "review" => ["actor-human"], "build" => ["actor-code"], "schema" => ["actor-code"],
                   "channel" => ["actor-human"], "channel_api" => ["actor-code"], "channel_portal" => ["actor-code"],
                   "channel_email" => ["actor-code"] }, actors)
  end

  test "state classes sit alongside actor classes, never replace them" do
    s = create_sample_submission
    resolve_sample(s, revenue: nil)
    post build_submission_path(s)
    assert_select ".pipeline-step.actor-input.state-done[data-pipeline-key=transcript]"
    assert_select ".pipeline-step.actor-ai.state-done[data-pipeline-key=extract] .pipeline-label svg", 1
    assert_select ".pipeline-step.actor-human.state-active[data-pipeline-key=review]"
    assert_select ".pipeline-step.actor-code.state-failed[data-pipeline-key=schema]"
    assert_select ".pipeline-step.actor-human.state-pending[data-pipeline-key=channel]"
    css_select("#pipeline .pipeline-step").each do |step|
      classes = step["class"].split
      assert_equal 1, classes.grep(/\Aactor-/).size, step["data-pipeline-key"]
      assert_equal 1, classes.grep(/\Astate-/).size, step["data-pipeline-key"]
    end
  end

  test "the bar starts with a legend of actors and the gate marker" do
    get root_path
    assert_select "#pipeline > .pipeline-legend:first-child li", 4
    assert_select "#pipeline .pipeline-legend li", text: "AI"
    assert_select "#pipeline .pipeline-legend li", text: "Code"
    assert_select "#pipeline .pipeline-legend li", text: "Human"
    assert_select "#pipeline .pipeline-legend li", text: "Gate"
    %w[ai code human].each { assert_select "#pipeline .pipeline-legend .legend-swatch.actor-#{_1} svg" }
    assert_select "#pipeline .pipeline-legend .legend-swatch.legend-gate svg"
  end

  test "review page: broker review is the active step" do
    s = create_sample_submission
    get submission_path(s)
    assert_select ".pipeline-step.state-done", 3
    assert_select ".pipeline-step.state-active[data-pipeline-key=review][aria-current=step]"
  end

  test "a failed build shows the schema check failed" do
    s = create_sample_submission
    resolve_sample(s, revenue: nil)
    post build_submission_path(s)
    assert_response :unprocessable_entity
    assert_select ".pipeline-step.state-failed[data-pipeline-key=schema]"
    assert_select ".pipeline-step.state-active[data-pipeline-key=review]"
  end

  test "ready page shows each channel's latest result, and a channel call replaces the bar" do
    s = create_ready_submission
    s.quote_requests.create!(channel: "api", carrier: "Acme Insurance", status: "quoted")
    get ready_submission_path(s)
    assert_select ".pipeline-step.state-done", 6
    assert_select ".pipeline-step.state-active[data-pipeline-key=channel][aria-current=step]"
    assert_select ".pipeline-step.actor-code.state-quoted[data-pipeline-key=channel_api]", /Quoted/
    assert_select "[data-pipeline-key=channel_api] .status-dot.status-quoted"
    assert_select "[data-pipeline-key=channel_email] .status-dot", 0
    assert_select ".pipeline-step.state-pending[data-pipeline-key=channel_email]"

    post submission_quote_requests_path(s), params: { channel: "email" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_select "turbo-stream[action=replace][target=pipeline] .pipeline-step.actor-code.state-sent[data-pipeline-key=channel_email] .status-dot.status-sent"
  end

  test "the extract, build and channel forms name their pipeline step" do
    get root_path
    assert_select "form[data-pipeline-step=extract][action=?]", submissions_path

    s = create_sample_submission
    resolve_sample(s)
    get submission_path(s)
    assert_select "form[data-pipeline-step=?][action=?]", "build schema", build_submission_path(s)

    s.build_submission!
    get ready_submission_path(s)
    %w[api portal email].each do |channel|
      assert_select "form[data-pipeline-step=?] input[name=channel][value=?]", "channel_#{channel}", channel
    end
    # Every name maps to a step in the bar.
    %w[extract build schema channel_api channel_portal channel_email].each do |key|
      assert_select "#pipeline [data-pipeline-key=?]", key
    end
  end
end
