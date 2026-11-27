# The pipeline bar at the bottom of every page.
module PipelineHelper
  ICONS = {
    input: '<path d="M3.5 1.5h6l3 3v10h-9z M9.5 1.5v3h3 M5.5 8h5 M5.5 11h5"/>',
    ai: '<path fill="currentColor" stroke="none" d="M8 1l1.5 4.5L14 7l-4.5 1.5L8 13l-1.5-4.5L2 7l4.5-1.5z M13 11.5l.6 1.4 1.4.6-1.4.6-.6 1.4-.6-1.4-1.4-.6 1.4-.6z"/>',
    code: '<path d="M5 4.5L1.5 8 5 11.5 M11 4.5L14.5 8 11 11.5 M9.5 3l-3 10"/>',
    human: '<circle cx="8" cy="5" r="3"/><path d="M2.5 15c0-3.2 2.5-5 5.5-5s5.5 1.8 5.5 5"/>',
    shield: '<path d="M8 1.5l5.5 2v4.2c0 3.3-2.3 5.8-5.5 6.8-3.2-1-5.5-3.5-5.5-6.8V3.5z"/>',
    check: '<path d="M3 8.5l3.2 3.2L13 4.8"/>'
  }.freeze

  STATE_TEXT = {
    "pending" => "Not started", "active" => "Current step", "done" => "Done", "failed" => "Failed",
    "quoted" => "Quoted", "declined" => "Declined", "referred" => "Referred", "sent" => "Sent"
  }.freeze

  # Which page we are on, for PipelineState.
  def pipeline_state
    page = { "new" => :paste, "create" => :paste, "show" => :review, "build" => :review, "ready" => :ready }[action_name] if controller_name == "submissions"
    PipelineState.new(page: page, submission: @submission, build_failed: @build_errors.present?)
  end

  def pipeline_icon(name, css_class: "pipeline-icon")
    tag.svg(ICONS.fetch(name).html_safe, class: css_class, viewBox: "0 0 16 16", width: 12, height: 12, fill: "none",
            stroke: "currentColor", "stroke-width": 1.6, "stroke-linecap": "round", "stroke-linejoin": "round", aria: { hidden: true })
  end

  def pipeline_step_tag(step, pipeline)
    state = pipeline.state(step.key)
    actor = [pipeline_icon(step.actor), step.actor_label]
    actor += [" · ", STATE_TEXT[state]] if step.channel? && state != "pending"
    tag.div(class: ["pipeline-step", "state-#{state}", ("gate" if step.gate), ("channel" if step.channel?)],
            title: step.title, data: { pipeline_key: step.key }, aria: { current: ("step" if state == "active") }) do
      safe_join([
        tag.span(class: "pipeline-label") do
          safe_join([(pipeline_icon(:check) if state == "done"), step.label,
                     (pipeline_icon(:shield, css_class: "pipeline-icon pipeline-gate-icon") if step.gate)].compact, " ")
        end,
        tag.span(safe_join(actor), class: "pipeline-actor"),
        tag.span(" (#{"Gate, " if step.gate}#{STATE_TEXT[state]})", class: "visually-hidden")
      ])
    end
  end
end
