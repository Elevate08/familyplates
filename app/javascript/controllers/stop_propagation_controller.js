import { Controller } from "@hotwired/stimulus"

// Replaces onclick="event.stopPropagation()" on controls that sit inside a
// linked card, so clicking them does not also follow the card's link.
export default class extends Controller {
  stop(event) {
    event.stopPropagation()
  }
}
