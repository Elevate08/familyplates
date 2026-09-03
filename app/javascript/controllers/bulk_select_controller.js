import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "checkbox",
    "selectAllCheckbox",
    "toolbar",
    "count",
    "tagsModal",
    "tagsSearchInput",
    "mealTypesModal",
    "deleteForm",
    "tagsForm",
    "mealTypesForm",
    "tagsInput"
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

  getCheckedCheckboxes() {
    return this.checkboxTargets.filter(cb => cb.checked)
  }

  getSelectedIds() {
    return this.getCheckedCheckboxes().map(cb => cb.value)
  }

  getCommonMealTypes() {
    const checked = this.getCheckedCheckboxes()
    if (checked.length === 0) return []

    const recipeMealTypeLists = checked.map(cb => {
      const raw = cb.dataset.mealTypes || ""
      return raw.split(",").map(s => s.trim().toLowerCase()).filter(Boolean)
    })

    return recipeMealTypeLists.reduce((common, currentList) => {
      return common.filter(mt => currentList.includes(mt))
    }, recipeMealTypeLists[0] || [])
  }

  getCommonTags() {
    const checked = this.getCheckedCheckboxes()
    if (checked.length === 0) return []

    const recipeTagLists = checked.map(cb => {
      const raw = cb.dataset.tags || ""
      return raw.split(",").map(s => s.trim()).filter(Boolean)
    })

    return recipeTagLists.reduce((common, currentList) => {
      const currentLower = currentList.map(t => t.toLowerCase())
      return common.filter(t => currentLower.includes(t.toLowerCase()))
    }, recipeTagLists[0] || [])
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

    // Sync selected IDs into all available bulk forms
    if (this.hasTagsFormTarget) this.syncHiddenFormInputs(this.tagsFormTarget, selectedIds)
    if (this.hasMealTypesFormTarget) this.syncHiddenFormInputs(this.mealTypesFormTarget, selectedIds)
    if (this.hasDeleteFormTarget) this.syncHiddenFormInputs(this.deleteFormTarget, selectedIds)
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

  // Intercept form submit to ensure latest IDs are present
  beforeFormSubmit(event) {
    const selectedIds = this.getSelectedIds()
    if (selectedIds.length === 0) {
      event.preventDefault()
      if (window.showConfirmDialog) {
        window.showConfirmDialog("Please select at least one recipe first.")
      } else {
        alert("Please select at least one recipe first.")
      }
      return
    }
    this.syncHiddenFormInputs(event.target, selectedIds)
  }

  openMealTypesModal(event) {
    if (event) event.preventDefault()
    const selectedIds = this.getSelectedIds()
    if (selectedIds.length === 0) return

    if (this.hasMealTypesFormTarget) {
      this.syncHiddenFormInputs(this.mealTypesFormTarget, selectedIds)

      // Prepopulate checkboxes with shared/common meal types
      const commonMealTypes = this.getCommonMealTypes()
      const checkboxes = this.mealTypesFormTarget.querySelectorAll("input[name='meal_types[]']")
      checkboxes.forEach(cb => {
        cb.checked = commonMealTypes.includes(cb.value.toLowerCase())
      })
    }

    if (this.hasMealTypesModalTarget) {
      this.mealTypesModalTarget.classList.remove("hidden")
      this.mealTypesModalTarget.classList.add("flex")
      document.body.classList.add("overflow-hidden")
    }
  }

  closeMealTypesModal(event) {
    if (event) event.preventDefault()
    if (this.hasMealTypesModalTarget) {
      this.mealTypesModalTarget.classList.add("hidden")
      this.mealTypesModalTarget.classList.remove("flex")
      document.body.classList.remove("overflow-hidden")
    }
  }

  openTagsModal(event) {
    if (event) event.preventDefault()
    const selectedIds = this.getSelectedIds()
    if (selectedIds.length === 0) return

    if (this.hasTagsFormTarget) {
      this.syncHiddenFormInputs(this.tagsFormTarget, selectedIds)

      // Prepopulate tags input with shared/common tags
      const commonTags = this.getCommonTags()
      if (this.hasTagsInputTarget) {
        this.tagsInputTarget.value = commonTags.join(", ")
        this.tagsInputTarget.dispatchEvent(new Event("change", { bubbles: true }))
      }
    }

    if (this.hasTagsModalTarget) {
      this.tagsModalTarget.classList.remove("hidden")
      this.tagsModalTarget.classList.add("flex")
      document.body.classList.add("overflow-hidden")
      // tagsInput is a hidden field - focus() on type="hidden" does nothing, so
      // this modal has never actually put the caret anywhere. Focus the tag box
      // a reader can type into, and do it now rather than from a timer.
      if (this.hasTagsSearchInputTarget) this.tagsSearchInputTarget.focus()
    }
  }

  closeTagsModal(event) {
    if (event) event.preventDefault()
    if (this.hasTagsModalTarget) {
      this.tagsModalTarget.classList.add("hidden")
      this.tagsModalTarget.classList.remove("flex")
      document.body.classList.remove("overflow-hidden")
    }
  }

  closeOnBackdrop(event) {
    if (event.target === event.currentTarget) {
      this.closeMealTypesModal()
      this.closeTagsModal()
    }
  }

  addTag(event) {
    if (event) event.preventDefault()
    const tag = event.currentTarget.dataset.tag
    if (!tag || !this.hasTagsInputTarget) return

    const currentTags = this.tagsInputTarget.value
      .split(",")
      .map(t => t.trim())
      .filter(Boolean)

    const tagIndex = currentTags.findIndex(t => t.toLowerCase() === tag.toLowerCase())
    if (tagIndex >= 0) {
      // Toggle off if already present
      currentTags.splice(tagIndex, 1)
    } else {
      // Add if not present
      currentTags.push(tag)
    }

    this.tagsInputTarget.value = currentTags.join(", ")
  }

  confirmBulkDelete(event) {
    if (event) event.preventDefault()
    const count = this.getSelectedIds().length
    if (count === 0) return

    const message = `Are you sure you want to delete ${count} selected ${count === 1 ? 'recipe' : 'recipes'}? This action cannot be undone.`

    window.showConfirmDialog(message, {
      title: "Confirm Bulk Deletion",
      confirmText: `Delete ${count} ${count === 1 ? 'Recipe' : 'Recipes'}`,
      icon: "🗑️"
    }).then(confirmed => {
      if (confirmed && this.hasDeleteFormTarget) {
        this.syncHiddenFormInputs(this.deleteFormTarget, this.getSelectedIds())
        this.deleteFormTarget.requestSubmit()
      }
    })
  }
}
