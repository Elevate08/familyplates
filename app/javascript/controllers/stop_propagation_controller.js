import { Controller } from "@hotwired/stimulus"

// Controls inside a linked card must not follow the card's link.
export default class extends Controller {
  stop(event) {
    event.stopPropagation()
  }
}
