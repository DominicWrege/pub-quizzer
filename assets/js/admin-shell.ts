// The authenticated admin layout is a viewport-locked flex shell whose <main>
// is the scroll container (see Layouts.app). This module adds two behaviors to
// that shell:
//
// 1. Scroll elevation: toggles `body.app-scrolled` once the list has scrolled,
//    which gives [data-sticky-bar] toolbars a hairline border + soft shadow —
//    the native-app "bar gains elevation on scroll" affordance.
//
// 2. Scroll memory: window-scroll restoration no longer applies now that the
//    list scrolls inside <main>, so we persist scrollTop per pathname and
//    restore it after back/forward navigation (e.g. edit question -> back).

function startAdminShell(): void {
  const main = document.querySelector<HTMLElement>("[data-app-shell] main")
  if (!main) return

  const scrollKey = () => `admin-scroll:${location.pathname}`
  let ticking = false

  const onScroll = () => {
    if (ticking) return
    ticking = true
    requestAnimationFrame(() => {
      ticking = false
      document.body.classList.toggle("app-scrolled", main.scrollTop > 4)
      sessionStorage.setItem(scrollKey(), String(main.scrollTop))
    })
  }

  const restore = () => {
    const saved = sessionStorage.getItem(scrollKey())
    if (saved !== null) main.scrollTop = parseInt(saved, 10) || 0
  }

  main.addEventListener("scroll", onScroll, { passive: true })

  // Only restore on history traversal. Restoring on every
  // phx:page-loading-stop would risk applying the old path's position to a
  // freshly live-navigated page (the URL updates late in that cycle).
  let restoreNext = false
  window.addEventListener("popstate", () => {
    restoreNext = true
  })
  window.addEventListener("phx:page-loading-stop", () => {
    if (!restoreNext) return
    restoreNext = false
    restore()
  })

  restore()
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", startAdminShell)
} else {
  startAdminShell()
}
