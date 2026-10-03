// Android's "Desktop site" can ignore the viewport meta tag and squeeze a
// 980px layout onto a phone. Compensate using screen dimensions and touch input,
// not the user agent, which desktop mode deliberately spoofs. CSS zoom reflows
// the page at the phone's width; it is not a transform of a desktop-sized page.
function fitPhoneViewport(): void {
  const { width, height } = window.screen
  const phone = navigator.maxTouchPoints > 0 && Math.min(width, height) <= 600
  const oversized = width > 0 && window.innerWidth > width * 1.25
  const zoom = phone && oversized ? window.innerWidth / width : 1

  document.documentElement.style.setProperty("--phone-viewport-zoom", `${zoom}`)
}

fitPhoneViewport()
window.addEventListener("resize", fitPhoneViewport)
window.addEventListener("orientationchange", fitPhoneViewport)
