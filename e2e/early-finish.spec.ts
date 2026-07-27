import { test, expect, createEvent, joinTeam } from "./fixtures"

test.describe("early finish", () => {
  test("host can end quiz early via confirm modal", async ({ browser, hostPage }) => {
    test.setTimeout(120_000)

    const code = await createEvent(hostPage, 2)

    const ctxA = await browser.newContext()
    const ctxB = await browser.newContext()
    const pageA = await ctxA.newPage()
    const pageB = await ctxB.newPage()

    await joinTeam(pageA, code)
    await joinTeam(pageB, code)

    // Start
    await expect(hostPage.locator('[phx-click="do_start"]')).toBeEnabled({ timeout: 15_000 })
    await hostPage.locator('[phx-click="do_start"]').click()
    await expect(hostPage).toHaveURL(/\/quiz\/\d{4}\/host$/, { timeout: 10_000 })

    // Pick topic and get to question phase
    await hostPage.waitForSelector('[phx-click="choose_topic"]', { timeout: 10_000 })
    await hostPage.locator('[phx-click="choose_topic"]').first().click()
    await expect(hostPage.locator("text=Frage 1 /")).toBeVisible({ timeout: 10_000 })

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

    await ctxA.close()
    await ctxB.close()
  })
})
