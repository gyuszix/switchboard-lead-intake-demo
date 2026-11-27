import { Controller } from "@hotwired/stimulus"

// Pulses the pipeline step(s) named by a submitting form's
// data-pipeline-step attribute (space separated) while its request runs.
export default class extends Controller {
  start(event) { this.mark(event.target, true) }
  stop(event) { this.mark(event.target, false) }

  mark(form, running) {
    const keys = (form.dataset?.pipelineStep || "").split(/\s+/).filter(Boolean)
    keys.forEach((key) => {
      this.element.querySelector(`[data-pipeline-key="${key}"]`)?.classList.toggle("is-running", running)
    })
  }
}
