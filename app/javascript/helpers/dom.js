// Scraped titles, tags, and names are free text. textContent and setAttribute
// only — interpolating them into innerHTML executes markup.

export function el(tag, { className, text, attrs } = {}, children = []) {
  const node = document.createElement(tag)

  if (className) node.className = className
  if (text !== undefined && text !== null) node.textContent = String(text)

  if (attrs) {
    for (const [name, value] of Object.entries(attrs)) {
      if (value !== undefined && value !== null) node.setAttribute(name, String(value))
    }
  }

  for (const child of children) {
    if (child) node.appendChild(child)
  }

  return node
}

export function replaceChildren(target, ...children) {
  target.replaceChildren(...children.filter(Boolean))
  return target
}

// Substring, then sequential letters ("bft" matches "breakfast").
export function fuzzyMatch(pattern, str) {
  if (!pattern) return true
  if (!str) return false
  if (str.includes(pattern)) return true

  let patternIdx = 0
  let strIdx = 0
  while (patternIdx < pattern.length && strIdx < str.length) {
    if (pattern[patternIdx] === str[strIdx]) {
      patternIdx++
    }
    strIdx++
  }
  return patternIdx === pattern.length
}

// WebAuthn exchanges base64url, not standard base64.
export function bufferToBase64url(buffer) {
  const bytes = new Uint8Array(buffer)
  let binary = ""
  for (let i = 0; i < bytes.byteLength; i++) {
    binary += String.fromCharCode(bytes[i])
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
}

export function base64urlToBuffer(base64url) {
  const padding = "=".repeat((4 - (base64url.length % 4)) % 4)
  const base64 = (base64url + padding).replace(/-/g, "+").replace(/_/g, "/")
  const rawData = atob(base64)
  const outputArray = new Uint8Array(rawData.length)
  for (let i = 0; i < rawData.length; ++i) {
    outputArray[i] = rawData.charCodeAt(i)
  }
  return outputArray.buffer
}

// Both passkey controllers share these two targets.
export function setStatus(controller, msg) {
  if (controller.hasStatusTarget) {
    controller.statusTarget.textContent = msg
    controller.statusTarget.classList.remove("hidden")
  }
  if (controller.hasErrorTarget) {
    controller.errorTarget.classList.add("hidden")
  }
}

export function showError(controller, msg) {
  if (controller.hasErrorTarget) {
    controller.errorTarget.textContent = msg
    controller.errorTarget.classList.remove("hidden")
  }
  if (controller.hasStatusTarget) {
    controller.statusTarget.classList.add("hidden")
  }
}

// The chevron themed-select paints on a <select>, as a DOM node, so custom
// dropdown triggers can show the identical arrow instead of a text glyph.
export function chevron(className = "w-4 h-4 shrink-0 ml-2 text-slate-500 dark:text-slate-400") {
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
  svg.setAttribute("viewBox", "0 0 24 24")
  svg.setAttribute("fill", "none")
  svg.setAttribute("stroke", "currentColor")
  svg.setAttribute("stroke-width", "2.5")
  svg.setAttribute("stroke-linecap", "round")
  svg.setAttribute("stroke-linejoin", "round")
  svg.setAttribute("aria-hidden", "true")
  svg.setAttribute("class", className)

  const path = document.createElementNS("http://www.w3.org/2000/svg", "path")
  path.setAttribute("d", "M19 9l-7 7-7-7")
  svg.appendChild(path)

  return svg
}
