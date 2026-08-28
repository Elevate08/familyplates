import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu", "button", "activeOption"]

  connect() {
    this.boundMediaListener = this.handleSystemThemeChange.bind(this)
    this.mediaQuery = window.matchMedia("(prefers-color-scheme: dark)")
    this.mediaQuery.addEventListener("change", this.boundMediaListener)

    this.applyTheme(this.currentTheme)
    this.updateUI()
  }

  disconnect() {
    if (this.mediaQuery) {
      this.mediaQuery.removeEventListener("change", this.boundMediaListener)
    }
  }

  get currentTheme() {
    return localStorage.getItem("familyplates_theme") || "system"
  }

  setTheme(event) {
    const theme = event.currentTarget.dataset.themeValue
    if (!theme) return

    localStorage.setItem("familyplates_theme", theme)
    this.applyTheme(theme)
    this.updateUI()
    this.closeMenu()
  }

  toggle(event) {
    event.stopPropagation()
    const current = this.currentTheme
    let nextTheme = "system"

    if (current === "system") {
      nextTheme = this.mediaQuery.matches ? "light" : "dark"
    } else if (current === "light") {
      nextTheme = "dark"
    } else {
      nextTheme = "system"
    }

    localStorage.setItem("familyplates_theme", nextTheme)
    this.applyTheme(nextTheme)
    this.updateUI()
  }

  toggleMenu(event) {
    event.stopPropagation()
    if (this.hasMenuTarget) {
      this.menuTarget.classList.toggle("hidden")
    }
  }

  closeMenu() {
    if (this.hasMenuTarget) {
      this.menuTarget.classList.add("hidden")
    }
  }

  closeMenuOnOutside(event) {
    if (!this.element.contains(event.target)) {
      this.closeMenu()
    }
  }

  handleSystemThemeChange() {
    if (this.currentTheme === "system") {
      this.applyTheme("system")
      this.updateUI()
    }
  }

  applyTheme(theme) {
    const isDark = theme === "dark" || (theme === "system" && this.mediaQuery.matches)
    if (isDark) {
      document.documentElement.classList.add("dark")
    } else {
      document.documentElement.classList.remove("dark")
    }
  }

  updateUI() {
    const theme = this.currentTheme

    // Update active highlight in dropdown menu
    if (this.hasActiveOptionTargets) {
      this.activeOptionTargets.forEach(el => {
        if (el.dataset.themeValue === theme) {
          el.classList.add("bg-primary-50", "text-primary-700", "dark:bg-primary-950/50", "dark:text-primary-400", "font-bold")
          el.classList.remove("text-slate-700", "dark:text-slate-300")
        } else {
          el.classList.remove("bg-primary-50", "text-primary-700", "dark:bg-primary-950/50", "dark:text-primary-400", "font-bold")
          el.classList.add("text-slate-700", "dark:text-slate-300")
        }
      })
    }
  }
}
