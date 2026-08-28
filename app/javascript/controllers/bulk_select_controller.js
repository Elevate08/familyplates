import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "checkbox",
    "selectAllCheckbox",
    "toolbar",
    "count",
    "tagsModal",
    "mealTypesModal",
    "deleteForm",
    "tagsForm",
    "mealTypesForm"
  ]

  connect() {
    this.updateState()
  }

  toggle() {
    this.updateState()
  }

  toggleAll(event) {
    const isChecked = event.target.checked
    this.checkboxTargets.forEach(cb => {
      cb.checked = isChecked
    })
    this.updateState()
  }

  clearAll(event) {
    if (event) event.preventDefault()
    this.checkboxTargets.forEach(cb => {
      cb.checked = false
    })
    if (this.hasSelectAllCheckboxTarget) {
      this.selectAllCheckboxTarget.checked = false
    }
    this.updateState()
  }

  getSelectedIds() {
    return this.checkboxTargets
      .filter(cb => cb.checked)
      .map(cb => cb.value)
  }

  updateState() {
    const selectedIds = this.getSelectedIds()
    const count = selectedIds.length

    if (this.hasCountTarget) {
      this.countTarget.textContent = `${count} selected`
    }

    if (this.hasSelectAllCheckboxTarget) {
      this.selectAllCheckboxTarget.checked = (count > 0 && count === this.checkboxTargets.length)
      this.selectAllCheckboxTarget.indeterminate = (count > 0 && count < this.checkboxTargets.length)
    }

    if (this.hasToolbarTarget) {
      if (count > 0) {
        this.toolbarTarget.classList.remove("hidden")
      } else {
        this.toolbarTarget.classList.add("hidden")
      }
    }

    // Sync selected IDs into hidden forms
    this.syncHiddenFormInputs(this.tagsFormTarget, selectedIds)
    this.syncHiddenFormInputs(this.mealTypesFormTarget, selectedIds)
    this.syncHiddenFormInputs(this.deleteFormTarget, selectedIds)
  }

  syncHiddenFormInputs(form, ids) {
    if (!form) return

    // Remove existing dynamic hidden inputs
    form.querySelectorAll("input[data-dynamic-recipe-id='true']").forEach(el => el.remove())

    // Append new hidden inputs for each selected recipe
    ids.forEach(id => {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = "recipe_ids[]"
      input.value = id
      input.dataset.dynamicRecipeId = "true"
      form.appendChild(input)
    })
  }

  openTagsModal(event) {
    if (event) event.preventDefault()
    if (this.hasTagsModalTarget) {
      this.tagsModalTarget.classList.remove("hidden")
      document.body.classList.add("overflow-hidden")
    }
  }

  closeTagsModal(event) {
    if (event) event.preventDefault()
    if (this.hasTagsModalTarget) {
      this.tagsModalTarget.classList.add("hidden")
      document.body.classList.remove("overflow-hidden")
    }
  }

  openMealTypesModal(event) {
    if (event) event.preventDefault()
    if (this.hasMealTypesModalTarget) {
      this.mealTypesModalTarget.classList.remove("hidden")
      document.body.classList.add("overflow-hidden")
    }
  }

  closeMealTypesModal(event) {
    if (event) event.preventDefault()
    if (this.hasMealTypesModalTarget) {
      this.mealTypesModalTarget.classList.add("hidden")
      document.body.classList.remove("overflow-hidden")
    }
  }

  confirmBulkDelete(event) {
    if (event) event.preventDefault()
    const count = this.getSelectedIds().length
    if (count === 0) return

    const message = `Are you sure you want to delete ${count} selected ${count === 1 ? 'recipe' : 'recipes'}? This action cannot be undone.`
    
    // Use Turbo's confirm method
    if (window.Turbo && window.Turbo.confirmMethod) {
      window.Turbo.confirmMethod(message, this.deleteFormTarget).then(confirmed => {
        if (confirmed && this.hasDeleteFormTarget) {
          this.deleteFormTarget.requestSubmit()
        }
      })
    } else if (confirm(message)) {
      if (this.hasDeleteFormTarget) this.deleteFormTarget.requestSubmit()
    }
  }
}
