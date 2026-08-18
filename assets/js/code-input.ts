// Slack-style segmented login-code input: a visually hidden <input> inside
// [data-code-input] holds the real value while one [data-code-slot] box per
// character renders it. Completing all slots auto-submits the form.

const SLOTS = 6

const sanitize = (value: string): string =>
  value.toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, SLOTS)

const paint = (container: HTMLElement, input: HTMLInputElement): void => {
  const slots = container.querySelectorAll<HTMLElement>("[data-code-slot]")
  const { value } = input
  const activeIdx = document.activeElement === input ? value.length : -1

  slots.forEach((slot, i) => {
    slot.textContent = value[i] ?? ""
    slot.classList.toggle("code-slot-filled", i < value.length)
    slot.classList.toggle("code-slot-active", i === activeIdx)
  })
}

const init = (container: HTMLElement): void => {
  if (container.dataset.codeReady) return
  const input = container.querySelector<HTMLInputElement>("input")
  if (!input) return
  container.dataset.codeReady = "true"

  const form = container.closest("form")

  const update = (): void => {
    const clean = sanitize(input.value)
    if (clean !== input.value) input.value = clean
    paint(container, input)
    if (clean.length === SLOTS && form) form.requestSubmit()
  }

  input.addEventListener("input", update)
  input.addEventListener("focus", () => paint(container, input))
  input.addEventListener("blur", () => paint(container, input))
  container.addEventListener("click", () => input.focus())

  paint(container, input)
}

document.addEventListener("DOMContentLoaded", () => {
  document.querySelectorAll<HTMLElement>("[data-code-input]").forEach(init)
})
