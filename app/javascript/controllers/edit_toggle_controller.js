import { Controller } from "@hotwired/stimulus"

// Shows or hides the inline edit input on a needs-approval field row.
export default class extends Controller {
  static targets = ["form", "actions", "input"]

  toggle() {
    this.formTarget.classList.toggle("hidden")
    this.actionsTarget.classList.toggle("hidden")
    if (!this.formTarget.classList.contains("hidden")) this.inputTarget.focus()
  }
}
