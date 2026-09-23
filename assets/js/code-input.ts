// Segmented 6-digit login-code input (Slack-style). Six bare input boxes share
// one hidden `name="code"` field, so exactly one code value is ever submitted.
// Submit is fired at most once per page load: any second submit event while a
// POST is in flight is cancelled before it can reach the server.

const SLOTS = 6

const sanitize = (value: string): string =>
  value.toUpperCase().replace(/[^A-Z0-9]/g, "")

const init = (container: HTMLElement): void => {
  if (container.dataset.codeReady) return
  const segments = Array.from(
    container.querySelectorAll<HTMLInputElement>("input[data-code-seg]")
  )
  const hidden = container.querySelector<HTMLInputElement>("input[name='code']")
  if (segments.length !== SLOTS || !hidden) return
  container.dataset.codeReady = "true"

  const form = container.closest("form") as HTMLFormElement | null
  const button = form?.querySelector<HTMLButtonElement>("#admin-code-submit") ?? null
  let submitting = false

  // No-JS fallback: the button renders enabled in HTML. Once this script
  // runs, lock it until all six slots are filled.
  if (button) button.disabled = true

  const setButtonState = (complete: boolean) => {
    if (!button) return
    button.disabled = submitting || !complete
    if (!submitting) button.classList.toggle("btn-disabled", !complete)
  }

  const sync = (): string => {
    const value = sanitize(
      segments.map(seg => seg.value).join("")
    ).slice(0, SLOTS)
    hidden.value = value
    setButtonState(value.length === SLOTS)
    return value
  }

  if (form) {
    form.addEventListener("submit", event => {
      // Cancel any submit event that arrives while a submission is already
      // running (auto-submit on the last key + pressed button, Enter + click,
      // rapid double click). The FIRST event always goes through untouched.
      if (submitting) {
        event.preventDefault()
        return
      }

      const filled = sanitize(
        segments.map(seg => seg.value).join("")
      ).length
      if (filled !== SLOTS) {
        event.preventDefault()
        const firstEmpty = segments.findIndex(seg => !seg.value)
        if (firstEmpty >= 0) segments[firstEmpty].focus()
        return
      }

      submitting = true
      sync()
    })
  }

  segments.forEach((seg, index) => {
    seg.addEventListener("input", () => {
      if (submitting) return

      const clean = sanitize(seg.value)

      // Multi-character entry (paste, autofill, swipe keyboard): distribute
      // characters across the remaining boxes and bump the trailing focus.
      if (clean.length > 1) {
        let i = index
        for (const char of clean.split("")) {
          if (i >= segments.length) break
          segments[i].value = char
          i++
        }
        if (i < segments.length) segments[i].focus()
      } else {
        seg.value = clean
        if (clean.length === 1 && index < SLOTS - 1) segments[index + 1].focus()
      }

      const value = sync()
      // Auto-submit exactly once when all six slots are filled.
      if (value.length === SLOTS && form && !submitting) {
        form.requestSubmit()
      }
    })

    seg.addEventListener("keydown", event => {
      if (submitting) return
      if (event.key === "Backspace" && !seg.value && index > 0) {
        const prev = segments[index - 1]
        prev.focus()
        prev.select()
        event.preventDefault()
      } else if (event.key === "ArrowLeft" && index > 0) {
        segments[index - 1].focus()
        event.preventDefault()
      } else if (event.key === "ArrowRight" && index < SLOTS - 1) {
        segments[index + 1].focus()
        event.preventDefault()
      }
    })

    seg.addEventListener("focus", () => seg.select())
    seg.addEventListener("paste", event => {
      const text = event.clipboardData?.getData("text") ?? ""
      const clean = sanitize(text).slice(0, SLOTS)
      if (clean.length <= 1) return
      event.preventDefault()
      for (let i = 0; i < segments.length; i++) {
        segments[i].value = clean[i] ?? ""
      }
      if (clean.length < SLOTS) segments[Math.min(clean.length, SLOTS - 1)].focus()
      const value = sync()
      if (value.length === SLOTS && form && !submitting) {
        form.requestSubmit()
      }
    })
  })
}

document.addEventListener("DOMContentLoaded", () => {
  document.querySelectorAll<HTMLElement>("[data-code-boxes]").forEach(init)
})
