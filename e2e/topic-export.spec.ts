import { test, expect, waitForLiveView } from "./fixtures"
import { readFileSync } from "node:fs"

test.describe("topic PDF export", () => {
  test("downloads a PDF on desktop and hides the button on mobile", async ({ hostPage }) => {
    await hostPage.goto("/admin/topics")
    await waitForLiveView(hostPage)
    await hostPage.waitForSelector(".card", { state: "visible" })

    const exportLink = hostPage.locator(".card a[href$='/export']").first()

    // Desktop (1280px viewport): the button is visible and triggers a download
    await expect(exportLink).toBeVisible()

    const [download] = await Promise.all([
      hostPage.waitForEvent("download"),
      exportLink.click(),
    ])

    expect(download.suggestedFilename()).toMatch(/^thema-.*\.pdf$/)

    const bytes = readFileSync(await download.path())
    expect(bytes.subarray(0, 5).toString("latin1")).toBe("%PDF-")

    // Mobile viewport: the export button is hidden (desktop-only feature)
    await hostPage.setViewportSize({ width: 375, height: 667 })
    await expect(exportLink).toBeHidden()
  })
})
