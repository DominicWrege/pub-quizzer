// Quiz font-size controller — persists an integer in [-2, 3] to localStorage and
// reflects it on `<body data-quiz-font-size>` plus the `#qfz-label` readout.
// The CSS reads the data attribute to scale the host console text.
//
// Exposed on `window.adjustFontSize` for the host console's inline onclick
// buttons, matching the presentation.ts pattern (the values and label table
// lived inline in the template before this — they had drifted from app.ts).

const STORAGE_KEY = "qfz"
const MIN = -2
const MAX = 3
const LABELS = ["80%", "90%", "100%", "125%", "150%", "200%"]

function applyFontSize(value: number): void {
  document.body.dataset.quizFontSize = String(value)
  const label = document.getElementById("qfz-label")
  if (label) {
    label.textContent = LABELS[value + 2]
  }
}

/** Reads the persisted value and applies it. Call on host console mount. */
export function restoreFontSize(): void {
  const stored = parseInt(localStorage.getItem(STORAGE_KEY) ?? "") || 0
  applyFontSize(stored)
}

/** Adjusts the persisted value by `delta` (clamped), then applies it. */
export function adjustFontSize(delta: number): void {
  const current = parseInt(localStorage.getItem(STORAGE_KEY) ?? "") || 0
  const next = Math.max(MIN, Math.min(MAX, current + delta))
  localStorage.setItem(STORAGE_KEY, String(next))
  applyFontSize(next)
}

declare global {
  interface Window {
    adjustFontSize: typeof adjustFontSize
  }
}

// Exposed for the inline onclick handlers in the host lobby template.
window.adjustFontSize = adjustFontSize
