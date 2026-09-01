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
