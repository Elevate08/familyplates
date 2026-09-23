import { Controller } from "@hotwired/stimulus"
import { bufferToBase64url, base64urlToBuffer, setStatus, showError } from "helpers/dom"

export default class extends Controller {
  static targets = ["email", "status", "error", "button"]
  static values = {
    optionsUrl: { type: String, default: "/passkeys/authentication_options" },
    callbackUrl: { type: String, default: "/passkeys/callback" }
  }

  async authenticate(event) {
    event.preventDefault()

    if (!window.PublicKeyCredential) {
      showError(this, "WebAuthn / Passkeys are not supported by your browser.")
      return
    }

    setStatus(this, "Verifying your passkey with Face ID, Touch ID, or security key...")

    try {
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
      const headers = {
        "Content-Type": "application/json",
        "Accept": "application/json"
      }
      if (csrfToken) headers["X-CSRF-Token"] = csrfToken

      const email = this.hasEmailTarget ? this.emailTarget.value : null

      const optResponse = await fetch(this.optionsUrlValue, {
        method: "POST",
        headers: headers,
        body: JSON.stringify({ email: email })
      })

      if (!optResponse.ok) {
        const err = await optResponse.json()
        throw new Error(err.error || "Could not retrieve passkey authentication options.")
      }

      const options = await optResponse.json()

      options.challenge = base64urlToBuffer(options.challenge)

      if (options.allowCredentials && Array.isArray(options.allowCredentials)) {
        options.allowCredentials = options.allowCredentials.map(c => ({
          ...c,
          id: base64urlToBuffer(c.id)
        }))
      }

      const assertion = await navigator.credentials.get({ publicKey: options })

      const payload = {
        credential: {
          id: assertion.id,
          rawId: bufferToBase64url(assertion.rawId),
          type: assertion.type,
          response: {
            clientDataJSON: bufferToBase64url(assertion.response.clientDataJSON),
            authenticatorData: bufferToBase64url(assertion.response.authenticatorData),
            signature: bufferToBase64url(assertion.response.signature),
            userHandle: assertion.response.userHandle ? bufferToBase64url(assertion.response.userHandle) : null
          }
        }
      }

      const callbackResponse = await fetch(this.callbackUrlValue, {
        method: "POST",
        headers: headers,
        body: JSON.stringify(payload)
      })

      const callbackResult = await callbackResponse.json()

      if (callbackResponse.ok) {
        setStatus(this, "Passkey verified! Redirecting to kitchen...")
        window.location.href = callbackResult.redirect_url || "/"
      } else {
        throw new Error(callbackResult.error || "Passkey verification failed.")
      }
    } catch (error) {
      if (error.name === "NotAllowedError") {
        showError(this, "Passkey sign-in was cancelled.")
      } else {
        showError(this, error.message || "Passkey sign-in failed.")
      }
    }
  }
}
