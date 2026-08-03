// iOS Safari's dynamic bottom URL bar is not tracked reliably by the *vh
// units: `100dvh` can still extend behind the bar, clipping the bottom of the
// viewport-locked admin shell and the slide-in drawer. We mirror the real
// visible viewport height into a CSS custom property so those containers
// always match what is actually on screen.
function setAppHeight(): void {
  document.documentElement.style.setProperty("--app-height", `${window.innerHeight}px`)
}

setAppHeight()
window.addEventListener("resize", setAppHeight)
window.addEventListener("orientationchange", setAppHeight)
window.visualViewport?.addEventListener("resize", setAppHeight)
