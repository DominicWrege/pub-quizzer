import { test, expect, createEvent, loginAsHost, waitForLiveView } from "./fixtures"

for (const viewport of [
  { width: 320, height: 568 },
  { width: 390, height: 844 },
  { width: 844, height: 390 },
  { width: 820, height: 1180 },
  { width: 1280, height: 720 },
]) {
  test(`selected QR code fits and closes at ${viewport.width}×${viewport.height}`, async ({ browser }, testInfo) => {
    const context = await browser.newContext({ viewport, hasTouch: true, isMobile: true })
    const page = await context.newPage()
    const errors: string[] = []
    page.on("console", message => { if (message.type() === "error") errors.push(message.text()) })
    page.on("pageerror", error => errors.push(error.message))

    try {
      await loginAsHost(page)
      await createEvent(page)
      await page.getByRole("link", { name: "QR-Karten" }).click()
      await waitForLiveView(page)

      const card = page.locator('[data-test="team-card"]').nth(1)
      await expect(card.getByRole("button", { name: "Kopieren", exact: true })).toBeVisible()
      const svg = await card.locator(".team-card-qr svg").innerHTML()
      const show = card.getByRole("button", { name: "Zeigen", exact: true })
      await show.tap()

      const dialog = page.locator("#team-qr-dialog")
      const qr = dialog.locator("[data-test='team-qr-code'] svg")
      await expect(dialog).toBeVisible()
      await expect(dialog).toHaveAccessibleName("Team 2")
      expect(await qr.innerHTML()).toBe(svg)
      const cards = page.locator('[data-test="team-card"]')
      await expect(cards.locator('[data-test="team-qr-placeholder"]')).toHaveCount(4)
      for (const card of await cards.all()) {
        await expect(card.locator(".team-card-qr svg")).toBeHidden()
        await expect(card.locator('[data-test="team-qr-placeholder"]')).toBeVisible()
      }
      const geometry = await qr.evaluate(element => {
        const box = element.getBoundingClientRect()
        const panel = element.closest(".modal-box")!
        const panelBox = panel.getBoundingClientRect()
        const closeBox = document.querySelector("#team-qr-dialog-close")!.getBoundingClientRect()
        const titleBox = document.querySelector("#team-qr-dialog-title")!.getBoundingClientRect()
        return {
          x: box.x, y: box.y, right: box.right, bottom: box.bottom,
          width: box.width, height: box.height,
          viewportWidth: innerWidth, viewportHeight: innerHeight,
          panelTop: panelBox.top, panelBottom: panelBox.bottom,
          scrollHeight: panel.scrollHeight, clientHeight: panel.clientHeight,
          closeWidth: closeBox.width, closeHeight: closeBox.height,
          titleCenterOffset: titleBox.x + titleBox.width / 2 - (panelBox.x + panelBox.width / 2),
        }
      })
      expect(geometry.width).toBeGreaterThanOrEqual(160)
      expect(geometry.width).toBeCloseTo(geometry.height, 0)
      expect(geometry.x).toBeGreaterThanOrEqual(0)
      expect(geometry.y).toBeGreaterThanOrEqual(0)
      expect(geometry.right).toBeLessThanOrEqual(geometry.viewportWidth)
      expect(geometry.bottom).toBeLessThanOrEqual(geometry.viewportHeight)
      expect(geometry.panelTop).toBeGreaterThanOrEqual(0)
      expect(geometry.panelBottom).toBeLessThanOrEqual(geometry.viewportHeight)
      expect(geometry.scrollHeight).toBeLessThanOrEqual(geometry.clientHeight + 1)
      expect(geometry.closeWidth).toBeGreaterThanOrEqual(44)
      expect(geometry.closeHeight).toBeGreaterThanOrEqual(44)
      expect(Math.abs(geometry.titleCenterOffset)).toBeLessThanOrEqual(1)
      await page.screenshot({ path: testInfo.outputPath("qr-dialog.png") })

      await page.locator("#team-qr-dialog-close").tap()
      await expect(dialog).toHaveCount(0)
      await expect(cards.locator('[data-test="team-qr-placeholder"]')).toHaveCount(0)
      await expect(card.locator(".team-card-qr svg")).toBeVisible()
      await show.tap()
      await expect(dialog).toBeVisible()
      await page.keyboard.press("Escape")
      await expect(dialog).toHaveCount(0)

      await page.locator('[data-test="team-card"]').first().getByRole("button", { name: "Zeigen", exact: true }).tap()
      await expect(dialog).toHaveAccessibleName("Team 1")
      await page.emulateMedia({ media: "print" })
      await expect(dialog).toBeHidden()
      await expect(page.locator('[id^="show-team-qr-"]').first()).toBeHidden()
      for (const card of await cards.all()) {
        await expect(card.locator(".team-card-qr svg")).toBeVisible()
        await expect(card.locator('[data-test="team-qr-placeholder"]')).toBeHidden()
      }
      expect(errors).toEqual([])
    } finally {
      await context.close()
    }
  })
}

test("print action shares the tablet header row but stacks on phones", async ({ hostPage }) => {
  await createEvent(hostPage)
  await hostPage.getByRole("link", { name: "QR-Karten" }).click()
  await waitForLiveView(hostPage)

  for (const width of [390, 768, 820, 1024]) {
    await hostPage.setViewportSize({ width, height: 1180 })
    const geometry = await hostPage.locator("#print-team-cards").evaluate(element => {
      const print = element.getBoundingClientRect()
      const header = element.closest("header")!
      const title = header.querySelector("h1")!.getBoundingClientRect()
      const back = header.querySelector("a")!.getBoundingClientRect()
      return { printTop: print.top, printBottom: print.bottom, titleTop: title.top, titleBottom: title.bottom, backTop: back.top, backBottom: back.bottom }
    })
    if (width < 640) {
      expect(geometry.printTop).toBeGreaterThanOrEqual(geometry.titleBottom)
    } else {
      expect(geometry.printTop).toBeLessThan(geometry.titleBottom)
      expect(geometry.printBottom).toBeGreaterThan(geometry.titleTop)
      expect(geometry.printTop).toBeLessThan(geometry.backBottom)
      expect(geometry.printBottom).toBeGreaterThan(geometry.backTop)
    }
  }
})
