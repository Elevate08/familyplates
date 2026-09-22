import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["popover", "trigger", "monthLabel", "calendarGrid"]
  static values = {
    selectedDate: String,    // ISO date: e.g. "2026-08-31"
    today: String,           // ISO date: e.g. "2026-09-05"
    view: { type: String, default: "week" }, // "week" or "month"
    weekStart: String,       // e.g. "2026-08-31"
    weekEnd: String,         // e.g. "2026-09-06"
    weekUrl: String,         // template: "/meal_plans?week=:date"
    monthUrl: String         // template: "/meal_plans/:id?view=month&month=:date"
  }

  connect() {
    this._boundCloseOnOutside = this.closeOnOutside.bind(this)
    this._boundCloseOnEsc = this.closeOnEsc.bind(this)
    document.addEventListener("click", this._boundCloseOnOutside)
    document.addEventListener("keydown", this._boundCloseOnEsc)

    this.resetToInitialDate()
  }

  disconnect() {
    document.removeEventListener("click", this._boundCloseOnOutside)
    document.removeEventListener("keydown", this._boundCloseOnEsc)
  }

  stopEvent(event) {
    if (event) {
      event.preventDefault()
      event.stopPropagation()
    }
  }

  resetToInitialDate() {
    const initialDate = this.parseDate(this.selectedDateValue || this.todayValue)
    this.displayedYear = initialDate.getFullYear()
    this.displayedMonth = initialDate.getMonth()
    this.renderCalendar()
  }

  toggle(event) {
    this.stopEvent(event)
    const isHidden = this.popoverTarget.classList.contains("hidden")
    if (isHidden) {
      this.open()
    } else {
      this.close()
    }
  }

  open() {
    this.resetToInitialDate()
    this.popoverTarget.classList.remove("hidden")
  }

  close() {
    if (this.hasPopoverTarget) {
      this.popoverTarget.classList.add("hidden")
    }
  }

  closeOnOutside(event) {
    if (!this.hasPopoverTarget || this.popoverTarget.classList.contains("hidden")) return
    if (this.element.contains(event.target)) return
    this.close()
  }

  closeOnEsc(event) {
    if (event.key === "Escape" && this.hasPopoverTarget && !this.popoverTarget.classList.contains("hidden")) {
      this.close()
    }
  }

  prevMonth(event) {
    this.stopEvent(event)
    this.displayedMonth--
    if (this.displayedMonth < 0) {
      this.displayedMonth = 11
      this.displayedYear--
    }
    this.renderCalendar()
  }

  nextMonth(event) {
    this.stopEvent(event)
    this.displayedMonth++
    if (this.displayedMonth > 11) {
      this.displayedMonth = 0
      this.displayedYear++
    }
    this.renderCalendar()
  }

  selectToday(event) {
    this.stopEvent(event)
    const todayDate = this.parseDate(this.todayValue)
    this.navigateToDate(todayDate)
  }

  selectDate(event) {
    this.stopEvent(event)
    const dateStr = event.currentTarget.dataset.date
    if (!dateStr) return
    const date = this.parseDate(dateStr)
    this.navigateToDate(date)
  }

  navigateToDate(date) {
    this.close()
    let targetUrl = ""
    if (this.viewValue === "month") {
      const monthStart = new Date(date.getFullYear(), date.getMonth(), 1)
      const monthStr = this.formatDate(monthStart)
      targetUrl = decodeURIComponent(this.monthUrlValue).replace(/:date|%3Adate/g, monthStr)
    } else {
      const monday = this.getMonday(date)
      const weekStr = this.formatDate(monday)
      targetUrl = decodeURIComponent(this.weekUrlValue).replace(/:date|%3Adate/g, weekStr)
    }

    if (window.Turbo) {
      window.Turbo.visit(targetUrl)
    } else {
      window.location.href = targetUrl
    }
  }

  renderCalendar() {
    if (!this.hasCalendarGridTarget) return

    const monthNames = [
      "January", "February", "March", "April", "May", "June",
      "July", "August", "September", "October", "November", "December"
    ]

    if (this.hasMonthLabelTarget) {
      this.monthLabelTarget.textContent = `${monthNames[this.displayedMonth]} ${this.displayedYear}`
    }

    const year = this.displayedYear
    const month = this.displayedMonth

    const daysInMonth = new Date(year, month + 1, 0).getDate()
    const firstDay = new Date(year, month, 1)
    const startDayOfWeek = (firstDay.getDay() + 6) % 7 // Monday = 0, Sunday = 6
    const daysInPrevMonth = new Date(year, month, 0).getDate()

    const totalCells = (startDayOfWeek + daysInMonth) > 35 ? 42 : 35

    const todayStr = this.todayValue
    const weekStartStr = this.weekStartValue
    const weekEndStr = this.weekEndValue
    const isWeekView = this.viewValue === "week"
    const selectedDateStr = this.selectedDateValue

    const cells = []

    for (let i = 0; i < totalCells; i++) {
      let cellDate
      let isCurrentMonth = true

      if (i < startDayOfWeek) {
        const dayNum = daysInPrevMonth - (startDayOfWeek - 1 - i)
        cellDate = new Date(year, month - 1, dayNum)
        isCurrentMonth = false
      } else if (i >= startDayOfWeek + daysInMonth) {
        const dayNum = i - (startDayOfWeek + daysInMonth) + 1
        cellDate = new Date(year, month + 1, dayNum)
        isCurrentMonth = false
      } else {
        const dayNum = i - startDayOfWeek + 1
        cellDate = new Date(year, month, dayNum)
      }

      const isoDate = this.formatDate(cellDate)
      const isToday = (isoDate === todayStr)
      const isInSelectedWeek = isWeekView && (isoDate >= weekStartStr && isoDate <= weekEndStr)

      let cellClasses = "w-8 h-8 sm:w-9 sm:h-9 text-xs font-semibold rounded-xl flex items-center justify-center transition-all cursor-pointer relative "

      if (isInSelectedWeek) {
        cellClasses += "bg-primary-100 dark:bg-primary-950/80 text-primary-900 dark:text-primary-200 font-extrabold shadow-2xs "
      } else if (isCurrentMonth) {
        cellClasses += "text-slate-800 dark:text-slate-200 hover:bg-slate-100 dark:hover:bg-slate-800 "
      } else {
        cellClasses += "text-slate-300 dark:text-slate-600 hover:bg-slate-50 dark:hover:bg-slate-800/40 "
      }

      if (isToday) {
        cellClasses += "ring-2 ring-primary-500 font-black "
      }

      cells.push(`
        <button type="button"
                data-action="click->date-picker#selectDate"
                data-date="${isoDate}"
                class="${cellClasses}"
                title="${isoDate}${isToday ? ' (Today)' : ''}">
          ${cellDate.getDate()}
          ${isToday ? '<span class="absolute bottom-1 w-1 h-1 rounded-full bg-primary-500"></span>' : ''}
        </button>
      `)
    }

    this.calendarGridTarget.innerHTML = cells.join("")
  }

  getMonday(d) {
    const date = new Date(d.getFullYear(), d.getMonth(), d.getDate())
    const day = (date.getDay() + 6) % 7
    date.setDate(date.getDate() - day)
    return date
  }

  parseDate(str) {
    if (!str) return new Date()
    const parts = str.split("-").map(n => parseInt(n, 10))
    return new Date(parts[0], parts[1] - 1, parts[2] || 1)
  }

  formatDate(d) {
    const year = d.getFullYear()
    const month = String(d.getMonth() + 1).padStart(2, "0")
    const day = String(d.getDate()).padStart(2, "0")
    return `${year}-${month}-${day}`
  }
}
