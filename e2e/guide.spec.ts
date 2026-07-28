import { test, expect, loginAsHost } from "./fixtures"

test.describe("first-login guide", () => {
  test("guide appears on events page and can be skipped", async ({ browser }) => {
    test.setTimeout(30_000)

    // Fresh context — no localStorage, so guide should show
    const ctx = await browser.newContext()
    const page = await ctx.newPage()
    await loginAsHost(page)

    // Guide popover appears on /admin/events
    await expect(page.locator(".driver-popover-title")).toBeVisible({ timeout: 10_000 })
    await expect(page.locator(".driver-popover-title")).toHaveText(/Willkommen/)

    // Click "Überspringen" to skip
    await page.locator(".driver-popover-footer-btn", { hasText: "Überspringen" }).click()

    // Guide is gone
    await expect(page.locator(".driver-popover-title")).toHaveCount(0, { timeout: 5_000 })

    // localStorage flag is set (onDestroyed fires async)
    await page.waitForFunction(
      () => localStorage.getItem("guide_seen") === "true",
      {},
      { timeout: 5_000 },
    )

    // Reload — guide does NOT reappear
    await page.reload()
    await page.waitForLoadState("networkidle")
    await expect(page.locator(".driver-popover-title")).toHaveCount(0)

    await ctx.close()
  })
})
