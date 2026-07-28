import { test, expect } from "./fixtures"

test.describe("profile & auth", () => {
  test("user can edit their profile name", async ({ hostPage }) => {
    test.setTimeout(30_000)

    await hostPage.goto("/admin/profile")

    const newName = `E2E Host ${Date.now()}`
    await hostPage.locator("#profile-form input[name='user[name]']").fill(newName)
    await hostPage.locator("#profile-form button[type='submit']").click()

    // Flash confirms save
    await expect(hostPage.locator(".alert-info")).toBeVisible({ timeout: 10_000 })

    // Input keeps the new value
    await expect(hostPage.locator("#profile-form input[name='user[name]']")).toHaveValue(newName)
  })

  test("email field is disabled on profile", async ({ hostPage }) => {
    test.setTimeout(15_000)

    await hostPage.goto("/admin/profile")
    await expect(hostPage.locator("#profile-form input[name='user[email]']")).toBeDisabled()
  })

  test("logging out redirects to login page", async ({ hostPage }) => {
    test.setTimeout(15_000)

    await hostPage.goto("/admin/logout")
    await expect(hostPage).toHaveURL(/\/admin\/login$/, { timeout: 10_000 })
  })

  test("unauthenticated user hitting admin is redirected to login", async ({ browser }) => {
    test.setTimeout(15_000)

    const ctx = await browser.newContext()
    const page = await ctx.newPage()

    await page.goto("/admin/events")
    await expect(page).toHaveURL(/\/admin\/login$/, { timeout: 10_000 })

    await ctx.close()
  })

  test("unauthenticated user hitting host lobby is redirected to login", async ({ browser }) => {
    test.setTimeout(15_000)

    const ctx = await browser.newContext()
    const page = await ctx.newPage()

    await page.goto("/quiz/0000/host")
    await expect(page).toHaveURL(/\/admin\/login$/, { timeout: 10_000 })

    await ctx.close()
  })
})
