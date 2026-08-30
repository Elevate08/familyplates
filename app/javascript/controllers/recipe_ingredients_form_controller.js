import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container", "template"]

  addRow(event) {
    if (event) event.preventDefault()
    if (!this.hasContainerTarget || !this.hasTemplateTarget) return

    const timestamp = new Date().getTime()
    const content = this.templateTarget.innerHTML.replace(/NEW_RECORD/g, timestamp)
    
    // Create temporary wrapper to parse HTML
    const temp = document.createElement("div")
    temp.innerHTML = content.trim()
    const newRow = temp.firstElementChild

    this.containerTarget.appendChild(newRow)

    // Focus on first input in the new row
    setTimeout(() => {
      const firstInput = newRow.querySelector("input")
      if (firstInput) firstInput.focus()
    }, 50)
  }

  removeRow(event) {
    if (event) event.preventDefault()
    const row = event.currentTarget.closest("[data-ingredient-row]")
    if (!row) return

    const destroyInput = row.querySelector("input[name*='[_destroy]']")
    if (destroyInput) {
      destroyInput.value = "1"
      row.classList.add("hidden")
    } else {
      row.remove()
    }
  }
}
