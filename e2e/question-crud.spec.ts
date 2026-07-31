import { test, expect, waitForLiveView } from "./fixtures"

test.describe("question CRUD", () => {
  test("moderator can create and delete a question", async ({ hostPage }) => {
    test.setTimeout(60_000)

    await hostPage.goto("/admin/topics")
    await waitForLiveView(hostPage)

    // Click "Fragen" on the first topic card
    await hostPage.locator("a[href*='/questions']").first().click()
    await expect(hostPage).toHaveURL(/\/admin\/topics\/\d+\/questions$/, { timeout: 10_000 })
    await waitForLiveView(hostPage)

    // --- Create ---
    await hostPage.locator("a[href*='/questions/new']").click()
    await expect(hostPage).toHaveURL(/\/questions\/new$/, { timeout: 10_000 })
    await waitForLiveView(hostPage)

    const prompt = `E2E test question ${Date.now()}?`
    await hostPage.locator("#question_prompt").fill(prompt)
    await hostPage.locator("#question_options_0").fill("Correct answer")
    await hostPage.locator("#question_options_1").fill("Wrong 1")
    await hostPage.locator("#question_options_2").fill("Wrong 2")
    await hostPage.locator("#question_options_3").fill("Wrong 3")

    // Select option A (index 0) as correct — click the letter label, not the
    // textarea (which has stopPropagation on click).
    await hostPage.locator('[phx-click="select_correct"] .font-mono').first().click()
    // Wait for the server to confirm the selection
    await expect(hostPage.locator("text=Richtige Antwort:")).toBeVisible({ timeout: 10_000 })

    // Submit the form directly (the submit button is outside the form via form= attr)
    await hostPage.locator("#question-form").evaluate((el: HTMLFormElement) => el.requestSubmit())

    // Back to questions list, new question appears (scoped to desktop table)
    await expect(hostPage).toHaveURL(/\/admin\/topics\/\d+\/questions$/, { timeout: 15_000 })
    await waitForLiveView(hostPage)
    await expect(hostPage.locator(`#questions >> text=${prompt}`)).toBeVisible({ timeout: 10_000 })

    // --- Delete ---
    await hostPage
      .locator("#questions tr", { hasText: prompt })
      .locator("[phx-click='ask_delete']")
      .click()
    await expect(hostPage.locator("#delete-question-modal")).toBeVisible({ timeout: 5_000 })
    await hostPage.locator("#delete-question-modal button", { hasText: "Löschen" }).click()

    await expect(hostPage.locator(`#questions >> text=${prompt}`)).toHaveCount(0, {
      timeout: 10_000,
    })
  })
})
