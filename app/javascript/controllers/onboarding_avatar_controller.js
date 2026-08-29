import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["nameInput", "previewColor", "previewName", "previewInitial", "roleSelect", "pinSection"]

  connect() {
    this.updatePreview()
    this.toggleRolePin()
  }

  updatePreview() {
    // Update name & initial
    if (this.hasNameInputTarget && this.hasPreviewNameTarget) {
      const name = this.nameInputTarget.value.trim()
      this.previewNameTarget.textContent = name || "Your Profile"
      if (this.hasPreviewInitialTarget) {
        this.previewInitialTarget.textContent = name ? name[0].toUpperCase() : "?"
      }
    }
  }

  changeColor(event) {
    const color = event.target.value
    if (this.hasPreviewColorTarget && color) {
      this.previewColorTarget.style.backgroundColor = color
    }
  }

  changeIcon(event) {
    const selectedIcon = event.target.value
    // Toggle active classes on icon picker container
    const iconSvgs = this.element.querySelectorAll("[data-icon-name]")
    iconSvgs.forEach(svgWrapper => {
      if (svgWrapper.dataset.iconName === selectedIcon) {
        svgWrapper.classList.remove("hidden")
      } else {
        svgWrapper.classList.add("hidden")
      }
    })
  }

  toggleRolePin() {
    if (this.hasRoleSelectTarget && this.hasPinSectionTarget) {
      const role = this.roleSelectTarget.value
      if (role === "admin") {
        this.pinSectionTarget.classList.remove("hidden")
      } else {
        this.pinSectionTarget.classList.add("hidden")
      }
    }
  }
}
