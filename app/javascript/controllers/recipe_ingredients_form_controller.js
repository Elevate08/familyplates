import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container", "template"]

  connect() {
    this.nextIndex = this.highestExistingIndex() + 1
  }

  // Rails needs a unique key per nested row. This used to be
  // new Date().getTime(), so two rows added inside the same millisecond - Enter
  // held down, or a double-click - got the same key and the second silently
  // replaced the first on submit. A counter cannot collide with itself, and
  // seeding it above the server-rendered indices keeps it clear of those too.
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
