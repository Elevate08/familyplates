import { Controller } from "@hotwired/stimulus"

function bufferToBase64url(buffer) {
  const bytes = new Uint8Array(buffer)
  let binary = ""
  for (let i = 0; i < bytes.byteLength; i++) {
    binary += String.fromCharCode(bytes[i])
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
}

function base64urlToBuffer(base64url) {
  const padding = "=".repeat((4 - (base64url.length % 4)) % 4)
  const base64 = (base64url + padding).replace(/-/g, "+").replace(/_/g, "/")
  const rawData = atob(base64)
  const outputArray = new Uint8Array(rawData.length)
  for (let i = 0; i < rawData.length; ++i) {
    outputArray[i] = rawData.charCodeAt(i)
  }
  return outputArray.buffer
}

export default class extends Controller {
  static targets = ["email", "status", "error", "button"]
  static values = {
    optionsUrl: { type: String, default: "/passkeys/authentication_options" },
    callbackUrl: { type: String, default: "/passkeys/callback" }
  }

  async authenticate(event) {
    event.preventDefault()

    if (!window.PublicKeyCredential) {
      this.showError("WebAuthn / Passkeys are not supported by your browser.")
      return
    }

    this.setStatus("Verifying your passkey with Face ID, Touch ID, or security key...")

    try {
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
      const headers = {
        "Content-Type": "application/json",
        "Accept": "application/json"
      }
      if (csrfToken) headers["X-CSRF-Token"] = csrfToken

      const email = this.hasEmailTarget ? this.emailTarget.value : null

      // 1. Fetch authentication options
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

      // Convert challenge
      options.challenge = base64urlToBuffer(options.challenge)

      // Convert allowCredentials if present
      if (options.allowCredentials && Array.isArray(options.allowCredentials)) {
        options.allowCredentials = options.allowCredentials.map(c => ({
          ...c,
          id: base64urlToBuffer(c.id)
        }))
      }

      // 2. Prompt for passkey assertion
      const assertion = await navigator.credentials.get({ publicKey: options })

      // 3. Encode assertion buffers back to Base64URL
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

      // 4. Send assertion to server callback
      const callbackResponse = await fetch(this.callbackUrlValue, {
        method: "POST",
        headers: headers,
        body: JSON.stringify(payload)
      })

      const callbackResult = await callbackResponse.json()

      if (callbackResponse.ok) {
        this.setStatus("Passkey verified! Redirecting to kitchen...")
        window.location.href = callbackResult.redirect_url || "/"
      } else {
        throw new Error(callbackResult.error || "Passkey verification failed.")
      }
    } catch (error) {
      if (error.name === "NotAllowedError") {
        this.showError("Passkey sign-in was cancelled.")
      } else {
        this.showError(error.message || "Passkey sign-in failed.")
      }
    }
  }

  setStatus(msg) {
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = msg
      this.statusTarget.classList.remove("hidden")
    }
    if (this.hasErrorTarget) {
      this.errorTarget.classList.add("hidden")
    }
  }

  showError(msg) {
    if (this.hasErrorTarget) {
      this.errorTarget.textContent = msg
      this.errorTarget.classList.remove("hidden")
    }
    if (this.hasStatusTarget) {
      this.statusTarget.classList.add("hidden")
    }
  }
}
