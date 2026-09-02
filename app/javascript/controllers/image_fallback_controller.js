import { Controller } from "@hotwired/stimulus"

// Replaces onerror="this.style.display='none'; this.nextElementSibling..."
// on recipe images: hide a broken image and reveal the placeholder after it.
export default class extends Controller {
  static targets = ["image", "placeholder"]

  failed(event) {
    const image = event?.target || (this.hasImageTarget ? this.imageTarget : null)
    if (image) image.style.display = "none"

    const placeholder = this.hasPlaceholderTarget
      ? this.placeholderTarget
      : image?.nextElementSibling

    if (placeholder) placeholder.classList.remove("hidden")
  }
}
