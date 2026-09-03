import { Controller } from "@hotwired/stimulus"

// Replaces onclick="window.print()".
export default class extends Controller {
  print() {
    window.print()
  }
}
