import { Controller } from "@hotwired/stimulus"

// Opens the transcript panel, scrolls to a quote's line and briefly highlights it.
export default class extends Controller {
  static targets = ["panel"]

  show(event) {
    event.preventDefault()
    const line = document.getElementById(event.params.line)
    if (!line) return

    this.panelTarget.open = true
    line.scrollIntoView({ behavior: "smooth", block: "center" })
    line.classList.remove("highlight")
    void line.offsetWidth // restart the animation on repeat clicks
    line.classList.add("highlight")
    clearTimeout(line.highlightTimer)
    line.highlightTimer = setTimeout(() => line.classList.remove("highlight"), 2000)
  }
}
