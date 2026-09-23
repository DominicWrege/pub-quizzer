import { test, expect, createEvent, joinTeam, waitForLiveView } from "./fixtures"

test.use({ video: "off" })

test("host reacquires screen wake lock after Safari restores the page", async ({ hostPage }) => {
  const errors: string[] = []
  hostPage.on("pageerror", error => errors.push(error.message))
  hostPage.on("console", message => {
    if (message.type() === "error") errors.push(message.text())
  })
  await hostPage.setViewportSize({ width: 390, height: 844 })
  await hostPage.addInitScript(() => {
    const browser = window as typeof window & {
      wakeRequests: number
      releaseWakeLock: () => void
    }
    browser.wakeRequests = 0
    Object.defineProperty(navigator, "wakeLock", {
      configurable: true,
      value: {
        request: async () => {
          browser.wakeRequests++
          let onRelease = () => {}
          const sentinel = {
            released: false,
            addEventListener: (_type: string, callback: () => void) => { onRelease = callback },
            release: async () => {
              sentinel.released = true
              onRelease()
            },
          }
          browser.releaseWakeLock = () => { void sentinel.release() }
          return sentinel
        },
      },
    })
  })

  const code = await createEvent(hostPage)
  await hostPage.goto(`/quiz/${code}/host`)
  await waitForLiveView(hostPage)
  await expect.poll(() => hostPage.evaluate(() => (window as any).wakeRequests)).toBe(1)

  await hostPage.evaluate(() => {
    (window as any).releaseWakeLock()
    window.dispatchEvent(new PageTransitionEvent("pageshow"))
  })
  await expect.poll(() => hostPage.evaluate(() => (window as any).wakeRequests)).toBe(2)
  expect(errors).toEqual([])
})

test("team lobby still holds a screen wake lock", async ({ hostPage, browser }) => {
  const code = await createEvent(hostPage)
  const context = await browser.newContext({ viewport: { width: 390, height: 844 } })
  const teamPage = await context.newPage()
  const errors: string[] = []
  teamPage.on("pageerror", error => errors.push(error.message))
  teamPage.on("console", message => {
    if (message.type() === "error") errors.push(message.text())
  })
  await teamPage.addInitScript(() => {
    (window as any).wakeRequests = 0
    Object.defineProperty(navigator, "wakeLock", {
      configurable: true,
      value: { request: async () => {
        (window as any).wakeRequests++
        return { addEventListener: () => {} }
      } },
    })
  })

  try {
    await joinTeam(teamPage, code)
    await expect.poll(() => teamPage.evaluate(() => (window as any).wakeRequests)).toBe(1)
    expect(errors).toEqual([])
  } finally {
    await context.close()
  }
})
