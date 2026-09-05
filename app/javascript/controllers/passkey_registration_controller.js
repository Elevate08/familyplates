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
  static targets = ["nickname", "button", "status", "error"]
  static values = {
    optionsUrl: { type: String, default: "/passkeys/registration_options" },
    createUrl: { type: String, default: "/passkeys" }
  }

  async register(event) {
    event.preventDefault()

    if (!window.PublicKeyCredential) {
      this.showError("WebAuthn is not supported by your browser.")
      return
    }

    this.setStatus("Prompting for Face ID, Touch ID, or security key...")

    try {
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
      const headers = {
        "Content-Type": "application/json",
        "Accept": "application/json"
      }
      if (csrfToken) headers["X-CSRF-Token"] = csrfToken

      // 1. Fetch registration options
      const optResponse = await fetch(this.optionsUrlValue, {
        method: "POST",
        headers: headers
      })

      if (!optResponse.ok) {
        const err = await optResponse.json()
        throw new Error(err.error || "Could not retrieve passkey registration options.")
      }

      const options = await optResponse.json()

      // Convert challenge
      options.challenge = base64urlToBuffer(options.challenge)

      // Convert user.id
      if (options.user && typeof options.user.id === "string") {
        options.user.id = new TextEncoder().encode(options.user.id)
      }

      // Convert excludeCredentials if any
      if (options.excludeCredentials) {
        options.excludeCredentials = options.excludeCredentials.map(c => ({
          ...c,
          id: base64urlToBuffer(c.id)
        }))
      }

      // 2. Create credential via WebAuthn API
      const credential = await navigator.credentials.create({ publicKey: options })

      // 3. Encode response buffers back to Base64URL
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

      // 4. Send to server for verification
      const saveResponse = await fetch(this.createUrlValue, {
        method: "POST",
        headers: headers,
        body: JSON.stringify(payload)
      })

      const saveResult = await saveResponse.json()

      if (saveResponse.ok) {
        this.setStatus("Passkey registered successfully! Refreshing...")
        window.location.reload()
      } else {
        throw new Error(saveResult.error || "Passkey registration failed on the server.")
      }
    } catch (error) {
      if (error.name === "NotAllowedError") {
        this.showError("Passkey registration was cancelled.")
      } else {
        this.showError(error.message || "An unexpected error occurred.")
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
