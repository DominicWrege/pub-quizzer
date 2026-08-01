// Auto-forwards the "check your email" tab once the user completes the magic
// link login in the tab their mail client opened. The session cookie is shared
// across same-origin tabs, so polling /admin/login/status reveals the login.
// Browsers refuse window.close() on tabs opened by navigation, so we redirect
// this tab to the dashboard instead of leaving it dangling.

async function isAuthenticated(): Promise<boolean> {
  try {
    const res = await fetch("/admin/login/status", { credentials: "same-origin" })
    if (!res.ok) return false
    const data = await res.json()
    return data.authenticated === true
  } catch {
    return false
  }
}

function startLoginWait(): void {
  const statusEl = document.querySelector<HTMLElement>("#login-wait-status")
  if (!statusEl) return

  const timer = setInterval(async () => {
    if (!(await isAuthenticated())) return
    clearInterval(timer)
    statusEl.textContent = "Angemeldet! Du wirst weitergeleitet…"
    window.location.href = "/admin/events"
  }, 1500)
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", startLoginWait)
} else {
  startLoginWait()
}
