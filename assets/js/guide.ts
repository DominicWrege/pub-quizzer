import { driver, type Driver } from "driver.js"

async function markGuideSeen(): Promise<void> {
  const csrfMeta = document.querySelector("meta[name='csrf-token']")
  const csrfToken = csrfMeta?.getAttribute("content") ?? ""
  try {
    await fetch("/admin/guide/seen", {
      method: "POST",
      credentials: "same-origin",
      headers: { "X-CSRF-Token": csrfToken }
    })
  } catch {
    // Ignore network errors — guide_seen will be false, guide may reappear
  }
}

function startGuide(): void {
  const driverObj: Driver = driver({
    showProgress: true,
    showButtons: ["next", "close"],
    allowClose: true,
    nextBtnText: "Weiter",
    prevBtnText: "Zurück",
    doneBtnText: "Fertig",
    popoverClass: "pubquiz-guide",
    onDestroyed: () => {
      markGuideSeen()
    },
    onPopoverRender: (popover) => {
      const footer = popover.footerButtons.closest(".driver-popover-footer")
      if (!footer) return
      if (footer.querySelector(".pubquiz-skip-btn")) return
      const skipBtn = document.createElement("button")
      skipBtn.innerText = "Überspringen"
      skipBtn.classList.add("driver-popover-footer-btn", "pubquiz-skip-btn")
      skipBtn.addEventListener("click", async () => {
        await markGuideSeen()
        driverObj.destroy()
      })
      footer.insertBefore(skipBtn, footer.firstChild)
    },
    steps: [
      {
        popover: {
          title: "Willkommen bei Quiz for a better life! 🏆",
          description: "Hier ist eine kurze Einführung. Du kannst sie jederzeit überspringen.",
        },
      },
      {
        element: 'a[href="/admin/events"]',
        popover: {
          title: "Quiz-Events",
          description: "Hier erstellst du neue Quiz-Events, startest sie und siehst die Ergebnisse.",
          side: "bottom",
          align: "start",
        },
      },
      {
        element: 'a[href="/admin/topics"]',
        popover: {
          title: "Themen & Fragen",
          description: "Hier legst du Themen und die zugehörigen Fragen an, aus denen die Quiz-Runden bestehen.",
          side: "bottom",
          align: "start",
        },
      },
      {
        element: "#new-event-btn",
        popover: {
          title: "Neues Quiz erstellen",
          description: "Klicke hier, um ein neues Event zu erstellen. Teams treten dann mit dem 4-stelligen Code bei.",
          side: "bottom",
          align: "end",
        },
      },
      {
        popover: {
          title: "So läuft ein Quiz ab",
          description:
            "Event erstellen → Teams beitreten mit Code → Quiz starten → Thema wählen → Teams antworten → Antworten auflösen → Ergebnisse anzeigen!",
        },
      },
    ],
  })

  driverObj.drive()
}

function maybeStartGuide(): void {
  const header = document.querySelector("header[data-guide-seen]")
  if (header?.getAttribute("data-guide-seen") === "true") return
  // The onboarding tour is for moderators only — superadmins know the ropes.
  if (header?.getAttribute("data-guide-role") === "superadmin") return
  if (!window.location.pathname.startsWith("/admin/events")) return

  const check = setInterval(() => {
    const navTab = document.querySelector('a[href="/admin/events"]')
    const newBtn = document.querySelector("#new-event-btn")
    if (navTab && newBtn) {
      clearInterval(check)
      startGuide()
    }
  }, 200)

  setTimeout(() => clearInterval(check), 10_000)
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", maybeStartGuide)
} else {
  maybeStartGuide()
}
