import { test, expect } from "./fixtures"

test.describe("smoke", () => {
  test("home page renders the team join form", async ({ page }) => {
    await page.goto("/")
    await expect(page.locator("#home-quiz-code")).toBeVisible()
    await expect(page.locator("#home-join-btn")).toBeVisible()
    // Submit button is disabled until a valid 4-digit code is entered.
    await expect(page.locator("#home-join-btn")).toBeDisabled()
  })

  test("joining with an invalid code shows an error flash", async ({ page }) => {
    await page.goto("/")
    await page.locator("#home-quiz-code").fill("0000")
    await page.locator("#home-join-btn").click()
    // Stays on home page with an error flash.
    await expect(page).toHaveURL("/")
    await expect(page.locator(".alert-error")).toBeVisible({ timeout: 5_000 })
  })

  test("host can log in via dev backdoor", async ({ hostPage }) => {
    await hostPage.goto("/admin/events")
    // If we're authenticated, we stay on /admin/events (not redirected to login).
    await expect(hostPage).toHaveURL(/\/admin\/events$/)
  })
})
