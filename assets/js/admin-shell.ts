// The authenticated admin layout is a flex shell (see Layouts.app): on lg+ it is
// locked to the viewport and <main> is the scroll container; below lg the
// document scrolls naturally so iOS Safari's floating URL bar collapses on
// scroll instead of permanently clipping the shell's bottom. This module adds:
//
// 1. Scroll elevation: toggles `body.app-scrolled` once the list has scrolled,
//    which gives [data-sticky-bar] toolbars a hairline border + soft shadow —
//    the native-app "bar gains elevation on scroll" affordance.
//
// 2. Sticky offset: publishes the header height as `--header-h` on the shell so
//    [data-sticky-bar] toolbars pin flush below the sticky header while the
//    document scrolls on mobile.
//
// 3. Scroll memory: persists the scroll position per pathname and restores it
//    after back/forward navigation (e.g. edit question -> back).

function startAdminShell(): void {
  const shell = document.querySelector<HTMLElement>("[data-app-shell]")
  if (!shell) return
  const main = shell.querySelector<HTMLElement>("main")
  const header = shell.querySelector<HTMLElement>("header")
  if (!main || !header) return

  const desktop = window.matchMedia("(min-width: 1024px)")
  const scrollKey = () => `admin-scroll:${location.pathname}`
  let ticking = false
  let initialLoad = true

  const scrollTop = (): number => (desktop.matches ? main.scrollTop : window.scrollY)

  const onScroll = (): void => {
    if (ticking) return
    ticking = true
    requestAnimationFrame(() => {
      ticking = false
      document.body.classList.toggle("app-scrolled", scrollTop() > 4)
      sessionStorage.setItem(scrollKey(), String(scrollTop()))
    })
  }

  const setHeaderHeight = (): void => {
    shell.style.setProperty("--header-h", `${header.offsetHeight}px`)
  }

  const setScrollTop = (top: number): void => {
    if (desktop.matches) main.scrollTop = top
    else window.scrollTo(0, top)
  }

  const restore = (): void => {
    const saved = sessionStorage.getItem(scrollKey())
    setScrollTop(saved === null ? 0 : parseInt(saved, 10) || 0)
  }

  main.addEventListener("scroll", onScroll, { passive: true })
  window.addEventListener("scroll", onScroll, { passive: true })
  window.addEventListener("resize", setHeaderHeight)
  desktop.addEventListener("change", () => {
    setHeaderHeight()
    onScroll()
  })

  // Only restore on history traversal. Restoring on every
  // phx:page-loading-stop would risk applying the old path's position to a
  // freshly live-navigated page (the URL updates late in that cycle).
  let restoreNext = false
  window.addEventListener("popstate", () => {
    restoreNext = true
  })
  window.addEventListener("phx:page-loading-stop", () => {
    setHeaderHeight()
    if (restoreNext) {
      restoreNext = false
      restore()
    } else if (!initialLoad) {
      setScrollTop(0)
    }
    initialLoad = false
  })

  setHeaderHeight()
  restore()
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", startAdminShell)
} else {
  startAdminShell()
}
