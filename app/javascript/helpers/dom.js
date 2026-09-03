// Builders for DOM nodes carrying values that came from the database.
//
// Recipe titles, tags, ingredient names, units and pantry icons are all free
// text, and the recipe scraper writes several of them straight from whatever
// third-party page a user imported. Interpolating any of that into innerHTML
// executes it. These helpers set text through textContent and attributes through
// setAttribute, so a value is always data and never markup.

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
