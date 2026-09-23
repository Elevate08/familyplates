import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container", "template"]

  connect() {
    this.nextIndex = this.highestExistingIndex() + 1
  }

  // Unique key per nested row. Date.now() collided inside one millisecond and the second row replaced the first.
  // A counter seeded above the server indices cannot.
  highestExistingIndex() {
    if (!this.hasContainerTarget) return -1

    const indices = Array.from(
      this.containerTarget.querySelectorAll("[name*='recipe_ingredients_attributes']")
    ).map(field => {
      const match = field.name.match(/recipe_ingredients_attributes\]\[(\d+)\]/)
      return match ? parseInt(match[1], 10) : -1
    })

    return indices.length ? Math.max(...indices) : -1
  }

  addRow(event) {
    if (event) event.preventDefault()
    if (!this.hasContainerTarget || !this.hasTemplateTarget) return

    if (this.nextIndex === undefined) this.nextIndex = this.highestExistingIndex() + 1
    const rowIndex = this.nextIndex
    this.nextIndex += 1

    const content = this.templateTarget.innerHTML.replace(/NEW_RECORD/g, rowIndex)
    
    const temp = document.createElement("div")
    temp.innerHTML = content.trim()
    const newRow = temp.firstElementChild

    this.containerTarget.appendChild(newRow)

    // Focus now. A deferred focus from a quick extra click landed in whatever field was active later.
    const firstInput = newRow.querySelector("input")
    if (firstInput) firstInput.focus()
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
