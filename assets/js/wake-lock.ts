import type { ViewHook } from "phoenix_live_view"

interface HostScreenHook extends ViewHook {
  onForeground: () => void
  cleanupScreen: () => void
}

// The host owns its wake lock for exactly as long as its LiveView is mounted.
// Safari releases screen locks when a tab is backgrounded or restored from the
// back/forward cache, so check both visibilitychange and pageshow.
const HostScreen = {
  mounted(this: HostScreenHook) {
    let wakeLock: WakeLockSentinel | null = null
    let acquiring = false
    let destroyed = false

    const acquire = async () => {
      if (destroyed || document.visibilityState !== "visible" || acquiring || (wakeLock && !wakeLock.released)) return
      if (!("wakeLock" in navigator)) return

      acquiring = true
      try {
        const lock = await navigator.wakeLock.request("screen")
        if (destroyed || document.visibilityState !== "visible") {
          await lock.release()
          return
        }
        wakeLock = lock
        lock.addEventListener("release", () => {
          if (wakeLock === lock) wakeLock = null
        })
      } catch {
        // silent
      } finally {
        acquiring = false
      }
    }

    this.onForeground = () => {
      if (document.visibilityState !== "visible") return
      void acquire()
      this.pushEvent("refresh", {})
    }
    const onVisibility = () => this.onForeground()
    const onPageShow = () => this.onForeground()
    document.addEventListener("visibilitychange", onVisibility)
    window.addEventListener("pageshow", onPageShow)

    this.cleanupScreen = () => {
      destroyed = true
      document.removeEventListener("visibilitychange", onVisibility)
      window.removeEventListener("pageshow", onPageShow)
      void wakeLock?.release()
    }

    void acquire()
  },

  reconnected(this: HostScreenHook) {
    this.onForeground()
  },

  destroyed(this: HostScreenHook) {
    this.cleanupScreen()
  },
}

export default HostScreen

// Team pages already relied on a screen lock while answering. They have no
// host refresh action, so keep their lightweight lock independent of the
// moderator-only hook above.
if (/^\/quiz\/[^/]+\/lobby$/.test(location.pathname)) {
  let teamLock: WakeLockSentinel | null = null

  const acquireTeamLock = async () => {
    if (!("wakeLock" in navigator) || teamLock || document.visibilityState !== "visible") return
    try {
      teamLock = await navigator.wakeLock.request("screen")
      teamLock.addEventListener("release", () => { teamLock = null })
    } catch {
      teamLock = null
    }
  }

  void acquireTeamLock()
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") void acquireTeamLock()
  })
  window.addEventListener("pageshow", () => { void acquireTeamLock() })
}
