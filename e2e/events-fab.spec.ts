import { test, expect, createEvent, waitForLiveView } from "./fixtures"

test("new quiz stays reachable at the bottom right on phone, tablet and desktop", async ({ hostPage }, testInfo) => {
  const errors: string[] = []
  hostPage.on("console", message => {
    if (message.type() === "error") errors.push(message.text())
  })
  hostPage.on("pageerror", error => errors.push(error.message))

  // Enough real cards to exercise scrolling rather than just an empty page.
  for (let i = 0; i < 9; i++) await createEvent(hostPage)
  await hostPage.goto("/admin/events")
  await waitForLiveView(hostPage)
  const fab = hostPage.locator("#new-event-btn")
  await expect(fab).toHaveAccessibleName("Neues Quiz")

  for (const viewport of [
    { width: 390, height: 844 },
    { width: 768, height: 1024 },
    { width: 1280, height: 720 },
  ]) {
    await hostPage.setViewportSize(viewport)
    await hostPage.goto("/admin/topics")
    await waitForLiveView(hostPage)
    const adminSpacing = await hostPage.locator("#topic-search").evaluate(element =>
      element.getBoundingClientRect().top - document.querySelector("header")!.getBoundingClientRect().bottom
    )
    await hostPage.goto("/admin/events")
    await waitForLiveView(hostPage)
    for (const scroll of [false, true]) {
      await hostPage.evaluate(atBottom => {
        const main = document.querySelector("main")!
        main.scrollTop = atBottom ? main.scrollHeight : 0
        window.scrollTo(0, atBottom ? document.documentElement.scrollHeight : 0)
      }, scroll)
      if (!scroll) {
        const cardSpacing = await hostPage.locator('[id^="event-"]').first().evaluate(element =>
          element.getBoundingClientRect().top - document.querySelector("header")!.getBoundingClientRect().bottom
        )
        expect(cardSpacing).toBeCloseTo(adminSpacing, 0)
      }
      await expect.poll(() => fab.evaluate(element => {
        const box = element.getBoundingClientRect()
        return innerHeight - box.bottom
      })).toBeGreaterThanOrEqual(12)
      const geometry = await fab.evaluate(element => {
        const box = element.getBoundingClientRect()
        return {
          width: box.width,
          height: box.height,
          rightGap: innerWidth - box.right,
          bottomGap: innerHeight - box.bottom,
          text: element.textContent?.trim(),
          clickable: element.contains(document.elementFromPoint(box.x + box.width / 2, box.y + box.height / 2)),
        }
      })
      expect(geometry.width).toBeGreaterThanOrEqual(44)
      expect(geometry.width).toBeLessThanOrEqual(64)
      expect(geometry.height).toBe(geometry.width)
      expect(geometry.rightGap).toBeGreaterThanOrEqual(12)
      expect(geometry.rightGap).toBeLessThanOrEqual(32)
      expect(geometry.bottomGap).toBeLessThanOrEqual(32)
      expect(geometry.text).toBe("")
      expect(geometry.clickable).toBe(true)
    }
    await hostPage.screenshot({ path: testInfo.outputPath(`events-fab-${viewport.width}.png`), animations: "disabled" })
  }

  const remainingSpace = await hostPage.evaluate(() => {
    const lastCardBottom = Math.max(...Array.from(document.querySelectorAll('[id^="event-"]')).map(element => element.getBoundingClientRect().bottom))
    return document.querySelector("#new-event-btn")!.getBoundingClientRect().top - lastCardBottom
  })
  expect(remainingSpace).toBeGreaterThanOrEqual(8)

  await fab.focus()
  await hostPage.keyboard.press("Enter")
  await expect(hostPage).toHaveURL(/\/admin\/events\/\d+$/)
  await expect(hostPage.locator('[data-testid="event-code"]')).toBeVisible()
  expect(errors).toEqual([])
})
