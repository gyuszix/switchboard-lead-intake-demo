import { Controller } from "@hotwired/stimulus"

// Shows or hides a quote request's full-width detail row beneath it.
export default class extends Controller {
  static values = { row: String }

  toggle() {
    const row = document.getElementById(this.rowValue)
    row.hidden = !row.hidden
    this.element.setAttribute("aria-expanded", String(!row.hidden))
  }
}
