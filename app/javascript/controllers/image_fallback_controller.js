import { Controller } from "@hotwired/stimulus"
 
// Replaces broken images with a placeholder element
export default class extends Controller {
  static targets = ["image", "placeholder"]

  connect() {
    // If the image already failed before Stimulus initialized
    const img = this.imageElement
    if (img && img.complete && img.naturalWidth === 0) {
      this.failed()
    }
  }

  failed(event) {
    const image = event?.target || this.imageElement
    if (image) image.style.display = "none"

    const placeholder = this.hasPlaceholderTarget
      ? this.placeholderTarget
      : (image?.nextElementSibling || this.element.querySelector("[data-image-fallback-target='placeholder']"))

    if (placeholder) {
      placeholder.classList.remove("hidden")
      placeholder.classList.remove("hidden!")
    }
  }

  get imageElement() {
    if (this.hasImageTarget) return this.imageTarget
    if (this.element.tagName === "IMG") return this.element
    return this.element.querySelector("img")
  }
}
