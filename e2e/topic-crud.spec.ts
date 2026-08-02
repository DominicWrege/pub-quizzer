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
    // The card's primary button now navigates to the question list, where the
    // topic editor lives in the header.
    const topicCard = hostPage.locator(".card", { hasText: topicName })
    await topicCard.locator("a[href*='/questions']").click()
    await expect(hostPage).toHaveURL(/\/admin\/topics\/\d+\/questions$/, { timeout: 10_000 })
    await waitForLiveView(hostPage)

    await hostPage.locator("button[phx-click='start_edit_topic']").click()
    await expect(hostPage.locator("#topic-form-modal")).toBeVisible({ timeout: 5_000 })

    const editedName = `${topicName} (edited)`
    await hostPage.locator("#topic-form input[name='topic[name]']").fill(editedName)
    await hostPage.locator("#topic-form button[type='submit']").click()
    await expect(hostPage.locator(`text=${editedName}`)).toBeVisible({ timeout: 10_000 })

    // --- Delete ---
    await hostPage.locator("button[phx-click='start_edit_topic']").click()
    await expect(hostPage.locator("#topic-form-modal")).toBeVisible({ timeout: 5_000 })

    await hostPage.locator("#topic-form-modal [phx-click='ask_delete_topic']").click()
    await expect(hostPage.locator("#delete-topic-modal")).toBeVisible({ timeout: 5_000 })
    await hostPage.locator("#delete-topic-modal button", { hasText: "Löschen" }).click()

    // Deleting redirects back to the overview, where the topic is gone
    await expect(hostPage).toHaveURL(/\/admin\/topics$/, { timeout: 10_000 })
    await expect(hostPage.locator(`text=${editedName}`)).toHaveCount(0, { timeout: 10_000 })
  })

  test("cancelling the delete confirmation keeps the edit dialog open", async ({ hostPage }) => {
    await hostPage.goto("/admin/topics")
    await waitForLiveView(hostPage)
    await hostPage.waitForSelector('[phx-click="start_new"]', { state: "visible" })

    // Open the first topic's question list, then its topic editor
    await hostPage.locator(".card").first().locator("a[href*='/questions']").click()
    await expect(hostPage).toHaveURL(/\/admin\/topics\/\d+\/questions$/, { timeout: 10_000 })
    await waitForLiveView(hostPage)

    await hostPage.locator("button[phx-click='start_edit_topic']").click()
    await expect(hostPage.locator("#topic-form-modal")).toBeVisible({ timeout: 5_000 })

    // Open the nested delete confirmation, then cancel it
    await hostPage.locator("#topic-form-modal [phx-click='ask_delete_topic']").click()
    await expect(hostPage.locator("#delete-topic-modal")).toBeVisible({ timeout: 5_000 })
    await hostPage.locator("#delete-topic-modal button[aria-label='Schließen']").click()
    await expect(hostPage.locator("#delete-topic-modal")).toHaveCount(0, { timeout: 5_000 })

    // The edit dialog must still be open and usable (regression: morphdom used
    // to strip the imperative `open` attr, silently closing it and - on Firefox -
    // leaving the whole page unresponsive).
    await expect(hostPage.locator("#topic-form-modal")).toBeVisible({ timeout: 5_000 })
    await expect(hostPage.locator("#topic-form-modal")).toHaveAttribute("open", "", { timeout: 5_000 })
    await expect(hostPage.locator("#topic-form-modal button[type='submit']")).toBeEnabled()

    // Closing the edit dialog restores the page behind it
    await hostPage.locator("#topic-form-modal button[aria-label='Schließen']").click()
    await expect(hostPage.locator("#topic-form-modal")).toHaveCount(0, { timeout: 5_000 })
  })
})
