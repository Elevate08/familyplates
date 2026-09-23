import { Controller } from "@hotwired/stimulus"
import { bufferToBase64url, base64urlToBuffer, setStatus, showError } from "helpers/dom"

export default class extends Controller {
  static targets = ["nickname", "button", "status", "error"]
  static values = {
    optionsUrl: { type: String, default: "/passkeys/registration_options" },
    createUrl: { type: String, default: "/passkeys" }
  }

  async register(event) {
    event.preventDefault()

    if (!window.PublicKeyCredential) {
      showError(this, "WebAuthn is not supported by your browser.")
      return
    }

    setStatus(this, "Prompting for Face ID, Touch ID, or security key...")

    try {
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
      const headers = {
        "Content-Type": "application/json",
        "Accept": "application/json"
      }
      if (csrfToken) headers["X-CSRF-Token"] = csrfToken

      const optResponse = await fetch(this.optionsUrlValue, {
        method: "POST",
        headers: headers
      })

      if (!optResponse.ok) {
        const err = await optResponse.json()
        throw new Error(err.error || "Could not retrieve passkey registration options.")
      }

      const options = await optResponse.json()

      options.challenge = base64urlToBuffer(options.challenge)

      if (options.user && typeof options.user.id === "string") {
        options.user.id = new TextEncoder().encode(options.user.id)
      }

      if (options.excludeCredentials) {
        options.excludeCredentials = options.excludeCredentials.map(c => ({
          ...c,
          id: base64urlToBuffer(c.id)
        }))
      }

      const credential = await navigator.credentials.create({ publicKey: options })

      const payload = {
        nickname: this.hasNicknameTarget ? this.nicknameTarget.value : null,
        credential: {
          id: credential.id,
          rawId: bufferToBase64url(credential.rawId),
          type: credential.type,
          response: {
            clientDataJSON: bufferToBase64url(credential.response.clientDataJSON),
            attestationObject: bufferToBase64url(credential.response.attestationObject)
          }
        }
      }

      const saveResponse = await fetch(this.createUrlValue, {
        method: "POST",
        headers: headers,
        body: JSON.stringify(payload)
      })

      const saveResult = await saveResponse.json()

      if (saveResponse.ok) {
        setStatus(this, "Passkey registered successfully! Refreshing...")
        window.location.reload()
      } else {
        throw new Error(saveResult.error || "Passkey registration failed on the server.")
      }
    } catch (error) {
      if (error.name === "NotAllowedError") {
        showError(this, "Passkey registration was cancelled.")
      } else {
        showError(this, error.message || "An unexpected error occurred.")
      }
    }
  }
}
