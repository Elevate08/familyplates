import { Controller } from "@hotwired/stimulus"

// Drives the counter-top cooking view: one step on screen at a time, an
// ingredient drawer that remembers what has been used, and navigation that
// works by tap, key, or swipe because a cook's hands are rarely free.
export default class extends Controller {
  static targets = [
    "step",
    "counter",
    "progressBar",
    "previousButton",
    "nextButton",
    "finishLink",
    "drawer",
    "drawerPanel",
    "drawerBackdrop",
    "ingredient",
    "remaining"
  ]

  static values = { storageKey: String }

  // Below this a touch is a tap or a scroll, not a deliberate swipe.
  SWIPE_THRESHOLD = 60

  connect() {
    this.index = 0
    this.restoreIngredients()
    this.updateRemaining()
    this.showStep()

    this.boundKeydown = this.keydown.bind(this)
    window.addEventListener("keydown", this.boundKeydown)
  }

  disconnect() {
    window.removeEventListener("keydown", this.boundKeydown)
  }

  // --- Step navigation ---------------------------------------------------

  next() {
    if (this.index >= this.lastIndex) return
    this.index += 1
    this.showStep()
  }

  previous() {
    if (this.index <= 0) return
    this.index -= 1
    this.showStep()
  }

  showStep() {
    this.stepTargets.forEach((step, i) => {
      step.hidden = i !== this.index
    })

    const humanIndex = this.index + 1
    const total = this.stepTargets.length

    if (this.hasCounterTarget) {
      this.counterTarget.textContent = `Step ${humanIndex} of ${total}`
    }

    if (this.hasProgressBarTarget) {
      const percent = total > 0 ? (humanIndex / total) * 100 : 0
      this.progressBarTarget.style.width = `${percent}%`
      this.progressBarTarget.parentElement?.setAttribute("aria-valuenow", String(humanIndex))
    }

    if (this.hasPreviousButtonTarget) {
      this.previousButtonTarget.disabled = this.index === 0
    }

    // On the last step "Next" would go nowhere, so it gives way to the way out.
    const onLastStep = this.index === this.lastIndex
    if (this.hasNextButtonTarget) this.nextButtonTarget.hidden = onLastStep
    if (this.hasFinishLinkTarget) this.finishLinkTarget.hidden = !onLastStep

    // A step taller than the screen keeps its predecessor's scroll position
    // otherwise, which reads as a step that starts halfway through.
    window.scrollTo({ top: 0, behavior: "instant" })
  }

  get lastIndex() {
    return Math.max(this.stepTargets.length - 1, 0)
  }

  keydown(event) {
    if (event.metaKey || event.ctrlKey || event.altKey) return

    const typing = event.target.closest("input, textarea, select")
    if (typing) return

    switch (event.key) {
      case "ArrowRight":
      case "PageDown":
        event.preventDefault()
        this.next()
        break
      case "ArrowLeft":
      case "PageUp":
        event.preventDefault()
        this.previous()
        break
      case "Escape":
        if (this.drawerOpen) {
          event.preventDefault()
          this.closeDrawer()
        }
        break
    }
  }

  touchStart(event) {
    this.touchOrigin = event.changedTouches[0]?.clientX ?? null
  }

  touchEnd(event) {
    if (this.touchOrigin === null || this.touchOrigin === undefined) return

    const travelled = (event.changedTouches[0]?.clientX ?? this.touchOrigin) - this.touchOrigin
    this.touchOrigin = null

    if (Math.abs(travelled) < this.SWIPE_THRESHOLD) return
    travelled < 0 ? this.next() : this.previous()
  }

  // --- Ingredient drawer -------------------------------------------------

  get drawerOpen() {
    return this.hasDrawerTarget && !this.drawerTarget.hidden
  }

  toggleDrawer() {
    this.drawerOpen ? this.closeDrawer() : this.openDrawer()
  }

  openDrawer() {
    if (!this.hasDrawerTarget) return

    this.drawerTarget.hidden = false
    // The panel starts off-canvas; the transform has to change on a later frame
    // or the browser has nothing to animate from.
    requestAnimationFrame(() => {
      this.drawerPanelTarget.classList.remove("translate-x-full")
      this.drawerBackdropTarget.classList.remove("opacity-0")
    })
  }

  closeDrawer() {
    if (!this.hasDrawerTarget) return

    this.drawerPanelTarget.classList.add("translate-x-full")
    this.drawerBackdropTarget.classList.add("opacity-0")
    setTimeout(() => {
      this.drawerTarget.hidden = true
    }, 200)
  }

  toggleIngredient(event) {
    const checkbox = event.currentTarget
    this.applyIngredientState(checkbox)
    this.saveIngredients()
    this.updateRemaining()
  }

  resetIngredients() {
    this.ingredientTargets.forEach((checkbox) => {
      checkbox.checked = false
      this.applyIngredientState(checkbox)
    })
    this.saveIngredients()
    this.updateRemaining()
  }

  applyIngredientState(checkbox) {
    const row = checkbox.closest("li")
    if (!row) return
    row.classList.toggle("opacity-40", checkbox.checked)
    row.querySelector(".ingredient-label")?.classList.toggle("line-through", checkbox.checked)
  }

  updateRemaining() {
    if (!this.hasRemainingTarget) return
    const left = this.ingredientTargets.filter((checkbox) => !checkbox.checked).length
    this.remainingTarget.textContent = String(left)
  }

  // Per-recipe and per-device. Storage can be unavailable (private mode, a
  // locked-down kiosk browser), and a cook losing their ticks is not a reason to
  // take the whole view down with an exception.
  saveIngredients() {
    const state = {}
    this.ingredientTargets.forEach((checkbox) => {
      state[checkbox.value] = checkbox.checked
    })

    try {
      localStorage.setItem(this.storageKeyValue, JSON.stringify(state))
    } catch (error) {
      // Ignored on purpose - see above.
    }
  }

  restoreIngredients() {
    let state = null
    try {
      state = JSON.parse(localStorage.getItem(this.storageKeyValue) || "null")
    } catch (error) {
      state = null
    }
    if (!state) return

    this.ingredientTargets.forEach((checkbox) => {
      if (Object.prototype.hasOwnProperty.call(state, checkbox.value)) {
        checkbox.checked = Boolean(state[checkbox.value])
        this.applyIngredientState(checkbox)
      }
    })
  }
}
