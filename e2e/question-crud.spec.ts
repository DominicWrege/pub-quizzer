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
    // Multiple links match (mini-rail, rail button, mobile FAB); target a
    // visible one at desktop width.
    await hostPage.locator("a[href*='/questions/new']:visible").click()
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

    // Back to questions list, new question appears
    await expect(hostPage).toHaveURL(/\/admin\/topics\/\d+\/questions$/, { timeout: 15_000 })
    await waitForLiveView(hostPage)
    await expect(hostPage.locator(`#questions >> text=${prompt}`)).toBeVisible({ timeout: 10_000 })

    // --- Delete ---
    await hostPage
      .locator("#questions > div", { hasText: prompt })
      .locator("[phx-click='ask_delete']")
      .click()
    await expect(hostPage.locator("#delete-question-modal")).toBeVisible({ timeout: 5_000 })
    await hostPage.locator("#delete-question-modal button", { hasText: "Löschen" }).click()

    await expect(hostPage.locator(`#questions >> text=${prompt}`)).toHaveCount(0, {
      timeout: 10_000,
    })
  })

  test("moderator can reorder questions with up/down buttons and drag & drop", async ({
    hostPage,
  }) => {
    test.setTimeout(60_000)

    await hostPage.goto("/admin/topics")
    await waitForLiveView(hostPage)

    await hostPage.locator("a[href*='/questions']").first().click()
    await expect(hostPage).toHaveURL(/\/admin\/topics\/\d+\/questions$/, { timeout: 10_000 })
    await waitForLiveView(hostPage)

    const cards = hostPage.locator("#questions .q-card")
    const prompts = hostPage.locator("#questions .font-medium.break-words")
    const count = await cards.count()
    test.skip(count < 2, "first topic has fewer than 2 questions")

    const first = ((await prompts.nth(0).textContent()) ?? "").trim()
    const second = ((await prompts.nth(1).textContent()) ?? "").trim()

    // --- Up/down buttons ---
    await cards.nth(0).locator("[phx-click='move_down']").click()
    await expect(prompts.nth(0)).toHaveText(second, { timeout: 10_000 })
    await expect(prompts.nth(1)).toHaveText(first)

    await cards.nth(1).locator("[phx-click='move_up']").click()
    await expect(prompts.nth(0)).toHaveText(first, { timeout: 10_000 })
    await expect(prompts.nth(1)).toHaveText(second)

    // --- Drag & drop (desktop only) ---
    const handle = cards.nth(0).locator(".drag-handle")
    await expect(handle).toBeVisible()
    const from = await handle.boundingBox()
    const to = await cards.nth(1).boundingBox()
    if (!from || !to) throw new Error("missing bounding boxes")

    await hostPage.mouse.move(from.x + from.width / 2, from.y + from.height / 2)
    await hostPage.mouse.down()
    // Drop on the lower half of the second card => insert after it
    await hostPage.mouse.move(to.x + to.width * 0.75, to.y + to.height * 0.75, { steps: 10 })
    await hostPage.mouse.up()

    await expect(prompts.nth(0)).toHaveText(second, { timeout: 10_000 })
    await expect(prompts.nth(1)).toHaveText(first)

    // Restore the original order
    await cards.nth(1).locator("[phx-click='move_up']").click()
    await expect(prompts.nth(0)).toHaveText(first, { timeout: 10_000 })
    await expect(prompts.nth(1)).toHaveText(second)
  })
})
