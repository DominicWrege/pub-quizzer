import { test, expect, loginAsHost } from "./fixtures"

test.describe("first-login guide", () => {
  test("guide appears on events page and can be skipped", async ({ browser }) => {
    test.setTimeout(30_000)

    const ctx = await browser.newContext()
    const page = await ctx.newPage()
    // The onboarding guide only shows for moderators, not superadmins.
    // Reset guide_seen to false so the guide always appears.
    await page.goto(`/dev/login-as/mod-e2e@localhost.test?reset_guide=true`)
    await page.waitForURL("**/admin/topics", { timeout: 10_000 })

    // Guide popover appears on /admin/topics
    await expect(page.locator(".driver-popover-title")).toBeVisible({ timeout: 10_000 })
    await expect(page.locator(".driver-popover-title")).toHaveText(/Willkommen/)

    // Click "Überspringen" to skip
    await page.locator(".driver-popover-footer-btn", { hasText: "Überspringen" }).click()

    // Guide is gone
    await expect(page.locator(".driver-popover-title")).toHaveCount(0, { timeout: 5_000 })

    // Reload — guide does NOT reappear (server persisted guide_seen)
    await page.reload()
    await page.waitForLoadState("networkidle")

    const seenAfterReload = await page.evaluate(() =>
      document.querySelector("header")?.getAttribute("data-guide-seen")
    )
    expect(seenAfterReload).toBe("true")
    await expect(page.locator(".driver-popover-title")).toHaveCount(0)

    await ctx.close()
  })
})
