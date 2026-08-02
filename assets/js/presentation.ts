// Presentation mode — hides the host console chrome and, where the browser
// supports it, takes the page fullscreen. The two states are kept in sync:
// leaving fullscreen (e.g. the browser's Escape shortcut) also leaves
// presentation mode. The class state persists across visits via localStorage;
// fullscreen itself is never auto-entered because the Fullscreen API requires
// an explicit user gesture.

const STORAGE_KEY = "pm"

export function isPresentationMode(): boolean {
  return document.body.classList.contains("presentation-mode")
}

export function setPresentationMode(active: boolean): void {
  document.body.classList.toggle("presentation-mode", active)
  localStorage.setItem(STORAGE_KEY, String(active))

  if (active) {
    if (document.fullscreenEnabled && !document.fullscreenElement) {
      document.documentElement.requestFullscreen().catch(() => {
        // Fullscreen was refused (permissions policy, iframe sandbox, …) —
        // presentation mode still works, just without fullscreen.
      })
    }
  } else if (document.fullscreenElement) {
    document.exitFullscreen().catch(() => {})
  }
}

export function togglePresentationMode(): void {
  setPresentationMode(!isPresentationMode())
}

// Restore the saved class state (class only — no fullscreen). Runs on module
// load and again from the host lobby hook on each LiveView mount, so the state
// survives live navigation back into the console.
export function restorePresentationMode(): void {
  document.body.classList.toggle(
    "presentation-mode",
    localStorage.getItem(STORAGE_KEY) === "true"
  )
}

restorePresentationMode()

// If the browser drops out of fullscreen on its own (Escape key), drop
// presentation mode too so the two never diverge.
document.addEventListener("fullscreenchange", () => {
  if (!document.fullscreenElement && isPresentationMode()) {
    setPresentationMode(false)
  }
})

// "P" toggles presentation mode, but only on the host console and never while
// typing into a field.
document.addEventListener("keydown", (e: KeyboardEvent) => {
  if (e.key !== "p" && e.key !== "P") return
  const target = e.target as HTMLElement | null
  if (target?.closest("input, textarea, select, [contenteditable='true']")) return
  if (!document.getElementById("host-lobby-main")) return
  togglePresentationMode()
})

declare global {
  interface Window {
    togglePresentation: typeof togglePresentationMode
  }
}

// Exposed for the inline onclick handlers in the host lobby template.
window.togglePresentation = togglePresentationMode
