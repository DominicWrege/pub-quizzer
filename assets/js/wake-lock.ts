// Screen Wake Lock — keeps host console and team devices awake during a quiz.
// Active on /quiz/:code/host and /quiz/:code/lobby only. The browser releases
// the lock automatically when the tab is hidden, so it is re-acquired whenever
// the document becomes visible again. Unsupported browsers (or non-secure
// contexts) are silently ignored via feature detection.

let wakeLock: WakeLockSentinel | null = null

async function acquire(): Promise<void> {
  if (!("wakeLock" in navigator) || wakeLock) return
  try {
    wakeLock = await navigator.wakeLock.request("screen")
    wakeLock.addEventListener("release", () => {
      wakeLock = null
    })
  } catch {
    // Refused — battery saver, permissions policy, hidden document, …
    wakeLock = null
  }
}

const isQuizPage = /^\/quiz\/[^/]+\/(host|lobby)$/.test(location.pathname)

if (isQuizPage) {
  void acquire()
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") void acquire()
  })
}
