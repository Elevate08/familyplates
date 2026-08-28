// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import { Turbo } from "@hotwired/turbo-rails"
import "controllers"

window.Turbo = Turbo

// Universal custom confirmation dialog matching the site theme & PIN modal
window.showConfirmDialog = function(message, options = {}) {
  return new Promise((resolve) => {
    const modal = document.getElementById("app-confirm-modal")
    const titleEl = document.getElementById("app-confirm-title")
    const messageEl = document.getElementById("app-confirm-message")
    const submitBtn = document.getElementById("app-confirm-submit")
    const cancelBtn = document.getElementById("app-confirm-cancel")
    const iconBadge = document.getElementById("app-confirm-icon-badge")
    const iconEl = document.getElementById("app-confirm-icon")

    if (!modal || !titleEl || !messageEl || !submitBtn || !cancelBtn) {
      resolve(window.confirm(message))
      return
    }

    const themeColor = getComputedStyle(document.documentElement).getPropertyValue("--user-accent").trim() || "#ea580c"

    titleEl.textContent = options.title || (message.toLowerCase().includes("delete") || message.toLowerCase().includes("remove") ? "Confirm Deletion" : "Are You Sure?")
    messageEl.textContent = message
    submitBtn.textContent = options.confirmText || (message.toLowerCase().includes("delete") || message.toLowerCase().includes("remove") ? "Yes, Delete" : "Confirm")
    if (iconEl) iconEl.textContent = options.icon || (message.toLowerCase().includes("delete") ? "🗑️" : "⚠️")

    if (submitBtn) {
      submitBtn.style.backgroundColor = themeColor
      submitBtn.style.boxShadow = `0 4px 14px ${themeColor}40`
    }
    if (iconBadge) {
      iconBadge.style.backgroundColor = themeColor
      iconBadge.style.boxShadow = `0 4px 14px ${themeColor}40`
    }

    const cleanup = () => {
      modal.classList.add("hidden")
      modal.classList.remove("flex")
      document.body.classList.remove("overflow-hidden")
      submitBtn.removeEventListener("click", onConfirm)
      cancelBtn.removeEventListener("click", onCancel)
      modal.removeEventListener("click", onBackdrop)
      document.removeEventListener("keydown", onEsc)
    }

    const onConfirm = () => {
      cleanup()
      resolve(true)
    }

    const onCancel = () => {
      cleanup()
      resolve(false)
    }

    const onBackdrop = (e) => {
      if (e.target === modal) {
        cleanup()
        resolve(false)
      }
    }

    const onEsc = (e) => {
      if (e.key === "Escape") {
        cleanup()
        resolve(false)
      }
    }

    submitBtn.addEventListener("click", onConfirm)
    cancelBtn.addEventListener("click", onCancel)
    modal.addEventListener("click", onBackdrop)
    document.addEventListener("keydown", onEsc)

    modal.classList.remove("hidden")
    modal.classList.add("flex")
    document.body.classList.add("overflow-hidden")
    setTimeout(() => submitBtn.focus(), 50)
  })
}

// Intercept all Turbo form confirmations across the entire app
Turbo.setConfirmMethod((message, _element) => {
  return window.showConfirmDialog(message)
})
