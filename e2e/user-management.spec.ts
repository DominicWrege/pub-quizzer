import { test, expect } from "./fixtures"

test.describe("user management", () => {
  test("superadmin can invite and delete a moderator", async ({ hostPage }) => {
    test.setTimeout(60_000)

    await hostPage.goto("/admin/users")
    // Wait for LiveView to connect so form values aren't wiped by re-render
    await hostPage.waitForSelector("#add-user-form")
    await hostPage.waitForLoadState("networkidle")

    const email = `e2e-test-${Date.now()}@localhost.test`
    const name = `E2E Test User`

    // Fill name first, email last (email survives any re-render between fills)
    const form = hostPage.locator("#add-user-form")
    await form.locator("input[name='name']").fill(name)
    await form.locator("input[name='email']").fill(email)
    await form.locator("button[type='submit']").click()

    // User appears in the list
    const userRow = hostPage.locator(`#users tr`, { hasText: email })
    await expect(userRow).toBeVisible({ timeout: 15_000 })

    // --- Delete ---
    await userRow.locator('[phx-click="ask_delete"]').click()
    await expect(hostPage.locator("#delete-user-modal")).toBeVisible({ timeout: 5_000 })
    await hostPage.locator("#delete-user-modal button", { hasText: "Löschen" }).click()

    // User is gone
    await expect(hostPage.locator(`text=${email}`)).toHaveCount(0, { timeout: 10_000 })
  })
})
