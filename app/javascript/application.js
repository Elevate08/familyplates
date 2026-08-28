// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

// Custom styled confirmation dialog (replaces browser native confirm)
Turbo.setConfirmMethod((message, element) => {
  return new Promise((resolve) => {
    // Create backdrop
    const backdrop = document.createElement("div")
    backdrop.className = "fixed inset-0 z-[9999] bg-slate-900/60 backdrop-blur-sm flex items-center justify-center p-4"
    backdrop.style.animation = "fadeIn 150ms ease-out"

    // Determine if this is a destructive action
    const isDelete = element?.closest("form")?.method === "post" &&
      (element?.closest("form")?.querySelector("[name='_method'][value='delete']") ||
       message.toLowerCase().includes("delete") ||
       message.toLowerCase().includes("remove"))

    const accentColor = isDelete ? "#e11d48" : (getComputedStyle(document.documentElement).getPropertyValue("--user-accent").trim() || "#ea580c")

    backdrop.innerHTML = `
      <div class="bg-white rounded-3xl border border-slate-200 p-6 sm:p-8 max-w-sm w-full shadow-2xl" style="animation: zoomIn 150ms ease-out">
        <div class="text-center mb-5">
          <div class="w-14 h-14 rounded-2xl flex items-center justify-center text-2xl font-extrabold shadow-md mx-auto mb-3"
               style="background-color: ${isDelete ? '#fef2f2' : '#fff7ed'}; border: 2px solid ${isDelete ? '#fecdd3' : '#fed7aa'}">
            ${isDelete ? '🗑️' : '⚠️'}
          </div>
          <h3 class="text-lg font-extrabold text-slate-900">
            ${isDelete ? 'Confirm Deletion' : 'Are You Sure?'}
          </h3>
          <p class="text-sm text-slate-600 mt-2 leading-relaxed">${message}</p>
        </div>

        <div class="flex items-center gap-3">
          <button type="button" data-confirm-action="cancel"
                  class="w-1/2 py-2.5 rounded-xl border border-slate-200 text-xs font-bold text-slate-600 hover:bg-slate-50 cursor-pointer transition-colors">
            Cancel
          </button>
          <button type="button" data-confirm-action="confirm"
                  class="w-1/2 py-2.5 rounded-xl text-white text-xs font-bold shadow-md cursor-pointer transition-all hover:brightness-110"
                  style="background-color: ${accentColor}; box-shadow: 0 4px 14px ${accentColor}40">
            ${isDelete ? 'Yes, Delete' : 'Confirm'}
          </button>
        </div>
      </div>
    `

    document.body.appendChild(backdrop)
    document.body.classList.add("overflow-hidden")

    const cleanup = () => {
      backdrop.remove()
      document.body.classList.remove("overflow-hidden")
    }

    // Button handlers
    backdrop.querySelector("[data-confirm-action='confirm']").addEventListener("click", () => {
      cleanup()
      resolve(true)
    })
    backdrop.querySelector("[data-confirm-action='cancel']").addEventListener("click", () => {
      cleanup()
      resolve(false)
    })

    // Click outside to cancel
    backdrop.addEventListener("click", (e) => {
      if (e.target === backdrop) {
        cleanup()
        resolve(false)
      }
    })

    // Escape key to cancel
    const escHandler = (e) => {
      if (e.key === "Escape") {
        document.removeEventListener("keydown", escHandler)
        cleanup()
        resolve(false)
      }
    }
    document.addEventListener("keydown", escHandler)

    // Focus the confirm button
    setTimeout(() => backdrop.querySelector("[data-confirm-action='confirm']")?.focus(), 50)
  })
})
