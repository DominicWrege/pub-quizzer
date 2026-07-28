import { test, expect, setupQuiz } from "./fixtures"

test.describe("early finish", () => {
  test("host can end quiz early via confirm modal", async ({ browser, hostPage }) => {
    test.setTimeout(120_000)

    const { contexts } = await setupQuiz(hostPage, browser, 2)

    // Host clicks "Quiz beenden"
    await hostPage.locator('[phx-click="ask_finish_quiz"]').click()

    // Confirm modal appears
    const modal = hostPage.locator("#finish-quiz-modal")
    await expect(modal).toBeVisible({ timeout: 5_000 })

    // Confirm
    await hostPage.locator('[phx-click="confirm_finish_quiz"]').click()

    // Both host and teams transition to finished state
    await expect(hostPage.locator('[phx-click="reveal_final_results"]')).toBeVisible({
      timeout: 10_000,
    })

    for (const ctx of contexts) await ctx.close()
  })
})
