import { test, expect } from "./fixtures"

test.describe("topic CRUD", () => {
  test("moderator can create, edit, and delete a topic", async ({ hostPage }) => {
    test.setTimeout(60_000)

    await hostPage.goto("/admin/topics")
    await hostPage.waitForSelector('[phx-click="start_new"]', { state: "visible" })

    // --- Create ---
    await hostPage.locator('[phx-click="start_new"]').click()
    await expect(hostPage.locator("#topic-form-modal")).toBeVisible({ timeout: 5_000 })

    const topicName = `E2E Topic ${Date.now()}`
    await hostPage.locator("#topic-form input[name='topic[name]']").fill(topicName)
    await hostPage.locator("#topic-form input[name='topic[description]']").fill("Created by E2E")
    await hostPage.locator("#topic-form button[type='submit']").click()

    // Topic card appears in the list
    await expect(hostPage.locator(`text=${topicName}`)).toBeVisible({ timeout: 10_000 })

    // --- Edit ---
    // Find the edit button within the same card as our topic name
    const topicCard = hostPage.locator(".card", { hasText: topicName })
    await topicCard.locator("[phx-click='start_edit']").click()
    await expect(hostPage.locator("#topic-form-modal")).toBeVisible({ timeout: 5_000 })

    const editedName = `${topicName} (edited)`
    await hostPage.locator("#topic-form input[name='topic[name]']").fill(editedName)
    await hostPage.locator("#topic-form button[type='submit']").click()
    await expect(hostPage.locator(`text=${editedName}`)).toBeVisible({ timeout: 10_000 })

    // --- Delete ---
    await hostPage.locator(".card", { hasText: editedName }).locator("[phx-click='start_edit']").click()
    await expect(hostPage.locator("#topic-form-modal")).toBeVisible({ timeout: 5_000 })

    await hostPage.locator("#topic-form-modal [phx-click='ask_delete']").click()
    await expect(hostPage.locator("#delete-topic-modal")).toBeVisible({ timeout: 5_000 })
    await hostPage.locator("#delete-topic-modal button", { hasText: "Löschen" }).click()

    // Topic is gone
    await expect(hostPage.locator(`text=${editedName}`)).toHaveCount(0, { timeout: 10_000 })
  })
})
