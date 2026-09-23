// Use a visible input so iOS Safari can offer the one-time code above the
// keyboard. Completing six characters auto-submits the form exactly once.

const SLOTS = 6

const sanitize = (value: string): string =>
  value.toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, SLOTS)

const init = (container: HTMLElement): void => {
  if (container.dataset.codeReady) return
  const input = container.querySelector<HTMLInputElement>("input")
  if (!input) return
  container.dataset.codeReady = "true"

  const form = container.closest("form")
  let submitting = false

  form?.addEventListener("submit", event => {
    if (submitting) {
      event.preventDefault()
      return
    }

    submitting = true
    input.readOnly = true
    const button = form.querySelector<HTMLButtonElement>('button[type="submit"]')
    if (button) {
      button.disabled = true
      button.textContent = "Anmelden…"
    }
  })

  const update = (event: Event): void => {
    if (submitting || (event instanceof InputEvent && event.isComposing)) return
    const clean = sanitize(input.value)
    if (clean !== input.value) input.value = clean
    if (clean.length === SLOTS && form) form.requestSubmit()
  }

  input.addEventListener("input", update)
}

document.addEventListener("DOMContentLoaded", () => {
  document.querySelectorAll<HTMLElement>("[data-code-input]").forEach(init)
})
