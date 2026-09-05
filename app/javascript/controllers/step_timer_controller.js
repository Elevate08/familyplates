import { Controller } from "@hotwired/stimulus"

// A one-tap countdown for a duration found in the step text ("simmer for 15
// minutes"). Counts against a wall-clock deadline rather than accumulating
// ticks, because a backgrounded tab is throttled to roughly one timer callback
// a second and an interval-counted timer drifts minutes late over a long bake.
export default class extends Controller {
  static targets = ["display", "state", "reset"]
  static values = { seconds: Number }

  TICK_MS = 250

  connect() {
    this.remaining = this.secondsValue
    this.deadline = null
    this.finished = false
    this.render()
  }

  disconnect() {
    this.stopTicking()
    this.closeAudio()
  }

  toggle() {
    if (this.finished) return this.reset()
    this.deadline ? this.pause() : this.start()
  }

  start() {
    if (this.remaining <= 0) return

    this.deadline = Date.now() + this.remaining * 1000
    this.stopTicking()
    this.ticker = setInterval(() => this.tick(), this.TICK_MS)
    this.render()
  }

  pause() {
    if (!this.deadline) return

    this.remaining = Math.max(Math.round((this.deadline - Date.now()) / 1000), 0)
    this.deadline = null
    this.stopTicking()
    this.render()
  }

  reset() {
    this.stopTicking()
    this.remaining = this.secondsValue
    this.deadline = null
    this.finished = false
    this.render()
  }

  tick() {
    if (!this.deadline) return

    this.remaining = Math.max(Math.round((this.deadline - Date.now()) / 1000), 0)
    if (this.remaining <= 0) return this.finish()

    this.render()
  }

  finish() {
    this.stopTicking()
    this.deadline = null
    this.remaining = 0
    this.finished = true
    this.alert()
    this.render()
  }

  stopTicking() {
    if (this.ticker) clearInterval(this.ticker)
    this.ticker = null
  }

  get running() {
    return Boolean(this.deadline)
  }

  render() {
    if (this.hasDisplayTarget) {
      this.displayTarget.textContent = this.formatted
    }

    if (this.hasStateTarget) {
      this.stateTarget.textContent = this.finished ? "Time's up" : this.running ? "Tap to pause" : "Tap to start"
    }

    if (this.hasResetTarget) {
      this.resetTarget.hidden = !this.running && this.remaining === this.secondsValue && !this.finished
    }

    this.element.classList.toggle("cook-timer-running", this.running)
    this.element.classList.toggle("cook-timer-finished", this.finished)
  }

  get formatted() {
    const total = Math.max(this.remaining, 0)
    const hours = Math.floor(total / 3600)
    const minutes = Math.floor((total % 3600) / 60)
    const seconds = total % 60
    const pad = (value) => String(value).padStart(2, "0")

    return hours > 0 ? `${hours}:${pad(minutes)}:${pad(seconds)}` : `${minutes}:${pad(seconds)}`
  }

  // Kitchens are loud and a cook is rarely looking at the screen, so the finish
  // is a sound and a buzz as well as a colour change. Both are best-effort:
  // audio needs a user gesture on some platforms and vibration is phone-only.
  alert() {
    try {
      const AudioContextClass = window.AudioContext || window.webkitAudioContext
      if (AudioContextClass) {
        this.audio ||= new AudioContextClass()
        const start = this.audio.currentTime
        for (let beep = 0; beep < 3; beep++) {
          this.beep(start + beep * 0.45)
        }
      }
    } catch (error) {
      // No audio available; the visual state still changes.
    }

    if (navigator.vibrate) navigator.vibrate([ 200, 100, 200, 100, 400 ])
  }

  beep(at) {
    const oscillator = this.audio.createOscillator()
    const gain = this.audio.createGain()

    oscillator.type = "sine"
    oscillator.frequency.setValueAtTime(880, at)
    // A square-edged gain change clicks; ramp it instead.
    gain.gain.setValueAtTime(0.0001, at)
    gain.gain.exponentialRampToValueAtTime(0.3, at + 0.02)
    gain.gain.exponentialRampToValueAtTime(0.0001, at + 0.3)

    oscillator.connect(gain)
    gain.connect(this.audio.destination)
    oscillator.start(at)
    oscillator.stop(at + 0.32)
  }

  closeAudio() {
    if (!this.audio) return
    this.audio.close().catch(() => {})
    this.audio = null
  }
}
