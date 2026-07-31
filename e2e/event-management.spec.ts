import { test, expect, createEvent, joinTeams } from "./fixtures"

test.describe("event management", () => {
  test("host can rename a team", async ({ browser, hostPage }) => {
    test.setTimeout(60_000)

    const code = await createEvent(hostPage, 2)
    const { contexts } = await joinTeams(browser, code, 1)

    // Find the first team name input in the (desktop) table and change it
    const nameInput = hostPage.locator("#event-teams input[phx-blur='rename_team']").first()
    await nameInput.fill("Die Superhirne")
    await nameInput.blur()

    // The name should persist (re-render shows new value)
    await expect(
      hostPage.locator("#event-teams input[phx-blur='rename_team']").first(),
    ).toHaveValue("Die Superhirne", { timeout: 10_000 })

    for (const ctx of contexts) await ctx.close()
  })

  test("host can add and remove team slots", async ({ hostPage }) => {
    test.setTimeout(60_000)

    await createEvent(hostPage, 2)

    // Initially 2 team rows
    await expect(hostPage.locator("tbody#event-teams tr")).toHaveCount(2, { timeout: 10_000 })

    // Add a slot
    await hostPage.locator('[phx-click="add_slot"]').click()
    await expect(hostPage.locator("tbody#event-teams tr")).toHaveCount(3, { timeout: 10_000 })

    // Remove a slot (removes last unclaimed)
    await hostPage.locator('[phx-click="remove_slot"]').click()
    await expect(hostPage.locator("tbody#event-teams tr")).toHaveCount(2, { timeout: 10_000 })
  })

  test("host can search events by code", async ({ browser, hostPage }) => {
    test.setTimeout(60_000)

    const code = await createEvent(hostPage, 2)

    // Go to events index
    await hostPage.goto("/admin/events")

    // Search by code
    await hostPage.locator("#event-search input[name='query']").fill(code)
    await hostPage.waitForTimeout(500)

    // The event card with our code should be visible
    await expect(hostPage.locator(`text=${code}`)).toBeVisible({ timeout: 10_000 })
  })

  test("host can delete an event from the show page", async ({ browser, hostPage }) => {
    test.setTimeout(60_000)

    const code = await createEvent(hostPage, 2)

    // Click delete on the show page
    await hostPage.locator('[phx-click="ask_delete_event"]').click()
    await expect(hostPage.locator("#delete-event-modal")).toBeVisible({ timeout: 5_000 })

    // Confirm deletion
    await hostPage.locator("#delete-event-modal button", { hasText: "Löschen" }).click()

    // Redirected to events index, code no longer visible
    await expect(hostPage).toHaveURL(/\/admin\/events$/, { timeout: 10_000 })
    await hostPage.waitForTimeout(500)
    await expect(hostPage.locator(`text=${code}`)).toHaveCount(0)
  })

  test("host can remove a team from the lobby", async ({ browser, hostPage }) => {
    test.setTimeout(60_000)

    const code = await createEvent(hostPage, 2)
    const { contexts } = await joinTeams(browser, code, 1)

    // Remove the first team in the (desktop) table
    await hostPage.locator("#event-teams [phx-click='remove_team']").first().click()

    // One team row gone (was 2, now 1)
    await expect(hostPage.locator("tbody#event-teams tr")).toHaveCount(1, { timeout: 10_000 })

    for (const ctx of contexts) await ctx.close()
  })
})
