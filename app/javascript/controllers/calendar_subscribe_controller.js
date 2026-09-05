import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tabAll", "tabMember", "panelAll", "panelMember"]

  showAll(event) {
    if (event) event.preventDefault()
    if (this.hasTabAllTarget && this.hasTabMemberTarget) {
      this.activateTab(this.tabAllTarget, this.tabMemberTarget)
    }
    if (this.hasPanelAllTarget) {
      this.panelAllTarget.classList.remove("hidden")
    }
    if (this.hasPanelMemberTarget) {
      this.panelMemberTarget.classList.add("hidden")
    }
  }

  showMember(event) {
    if (event) event.preventDefault()
    if (this.hasTabAllTarget && this.hasTabMemberTarget) {
      this.activateTab(this.tabMemberTarget, this.tabAllTarget)
    }
    if (this.hasPanelMemberTarget) {
      this.panelMemberTarget.classList.remove("hidden")
    }
    if (this.hasPanelAllTarget) {
      this.panelAllTarget.classList.add("hidden")
    }
  }

  activateTab(active, inactive) {
    active.classList.add("bg-white", "dark:bg-slate-700", "text-primary-600", "dark:text-primary-400", "shadow-xs")
    active.classList.remove("text-slate-600", "dark:text-slate-400")

    if (inactive) {
      inactive.classList.remove("bg-white", "dark:bg-slate-700", "text-primary-600", "dark:text-primary-400", "shadow-xs")
      inactive.classList.add("text-slate-600", "dark:text-slate-400")
    }
  }
}
