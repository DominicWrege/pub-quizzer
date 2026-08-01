import { test, expect, waitForLiveView } from "./fixtures"

test.describe("topic CRUD", () => {
  test("moderator can create, edit, and delete a topic", async ({ hostPage }) => {
    test.setTimeout(60_000)

    await hostPage.goto("/admin/topics")
    await waitForLiveView(hostPage)
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

  test("cancelling the delete confirmation keeps the edit dialog open", async ({ hostPage }) => {
    await hostPage.goto("/admin/topics")
    await waitForLiveView(hostPage)
    await hostPage.waitForSelector('[phx-click="start_new"]', { state: "visible" })

    // Open the edit dialog for the first topic
    await hostPage.locator(".card").first().locator("[phx-click='start_edit']").click()
    await expect(hostPage.locator("#topic-form-modal")).toBeVisible({ timeout: 5_000 })

    // Open the nested delete confirmation, then cancel it
    await hostPage.locator("#topic-form-modal [phx-click='ask_delete']").click()
    await expect(hostPage.locator("#delete-topic-modal")).toBeVisible({ timeout: 5_000 })
    await hostPage.locator("#delete-topic-modal button", { hasText: "Abbrechen" }).click()
    await expect(hostPage.locator("#delete-topic-modal")).toHaveCount(0, { timeout: 5_000 })

    // The edit dialog must still be open and usable (regression: morphdom used
    // to strip the imperative `open` attr, silently closing it and - on Firefox -
    // leaving the whole page unresponsive).
    await expect(hostPage.locator("#topic-form-modal")).toBeVisible({ timeout: 5_000 })
    await expect(hostPage.locator("#topic-form-modal")).toHaveAttribute("open", "", { timeout: 5_000 })
    await expect(hostPage.locator("#topic-form-modal button[type='submit']")).toBeEnabled()

    // Closing the edit dialog restores the page behind it
    await hostPage.locator("#topic-form-modal button", { hasText: "Abbrechen" }).click()
    await expect(hostPage.locator("#topic-form-modal")).toHaveCount(0, { timeout: 5_000 })
    await expect(hostPage.locator('[phx-click="start_new"]')).toBeEnabled()
  })
})
