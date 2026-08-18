// daisyUI dropdowns stay open while their toggle holds focus (:focus-within).
// Touch devices never blur the toggle on outside taps, so dismiss manually:
// tap outside closes, and a second tap on the toggle toggles it shut.

let openBeforePointerDown = false

document.addEventListener("pointerdown", (e: Event) => {
  const target = e.target
  const dropdown = target instanceof HTMLElement ? target.closest(".dropdown") : null
  openBeforePointerDown = !!dropdown && dropdown.contains(document.activeElement)
})

document.addEventListener("click", (e: Event) => {
  const target = e.target
  if (!(target instanceof HTMLElement)) return
  const active = document.activeElement
  const dismissable = active instanceof HTMLElement && active !== document.body

  const dropdown = target.closest(".dropdown")
  if (dropdown) {
    if (openBeforePointerDown && !target.closest("a") && dismissable) active.blur()
    return
  }

  if (dismissable && active.closest(".dropdown")) active.blur()
})
