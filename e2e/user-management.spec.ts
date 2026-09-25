import { test, expect, loginAsHost } from "./fixtures"

test.describe("user management", () => {
  test("shows login time in the viewer's timezone on desktop and mobile", async ({ browser }) => {
    const context = await browser.newContext({ timezoneId: "Europe/Berlin" })
    const page = await context.newPage()
    const errors: string[] = []
    page.on("pageerror", (error) => errors.push(error.message))
    page.on("console", (message) => {
      if (message.type() === "error") errors.push(message.text())
    })

    try {
      await loginAsHost(page)
      await page.goto("/admin/users")

      const desktop = page.locator("#users time").first()
      const mobile = page.locator("#users-cards time").first()
      const utc = await desktop.getAttribute("datetime")
      expect(utc).toMatch(/Z$/)

      const date = new Date(utc!)
      const expected = `${new Intl.DateTimeFormat("de-DE", {
        timeZone: "Europe/Berlin", day: "2-digit", month: "2-digit", year: "2-digit",
      }).format(date)} ${new Intl.DateTimeFormat("de-DE", {
        timeZone: "Europe/Berlin", hour: "2-digit", minute: "2-digit",
      }).format(date)}`

      await expect(desktop).toHaveText(expected)
      await expect(mobile).toHaveText(expected)
      expect(await mobile.getAttribute("datetime")).toBe(utc)

      for (const input of await page.locator("#add-user-form input").all()) {
        await expect(input).toHaveAttribute("autocomplete", "off")
        await expect(input).toHaveAttribute("data-bwignore", "")
      }
      expect(errors).toEqual([])
    } finally {
      await context.close()
    }
  })

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
