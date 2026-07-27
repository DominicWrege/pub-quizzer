import { test, expect, createEvent, joinTeam, completeRound } from "./fixtures"

test.describe("edge cases", () => {
  test("round reveal → standings → next round topic selection", async ({ browser, hostPage }) => {
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

    // Pick topic
    await hostPage.waitForSelector('[phx-click="choose_topic"]', { timeout: 10_000 })
    await hostPage.locator('[phx-click="choose_topic"]').first().click()

    // Wait for quiz to transition to question phase
    await expect(hostPage.locator("text=Frage 1 /")).toBeVisible({ timeout: 15_000 })

    // Play round with default answers (team A wins) then reveal + show standings.
    await completeRound(hostPage, pageA, pageB)

    // Standings are shown — click "Nächste Runde"
    await hostPage.locator('[phx-click="next_round"]').click()
    await hostPage.waitForSelector('[phx-click="choose_topic"]', { timeout: 10_000 })

    await ctxA.close()
    await ctxB.close()
  })

  test("team can change answer before host advances", async ({ browser, hostPage }) => {
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

    // Pick topic
    await hostPage.waitForSelector('[phx-click="choose_topic"]', { timeout: 10_000 })
    await hostPage.locator('[phx-click="choose_topic"]').first().click()

    // First question appears on host, then team pages get answer buttons
    await expect(hostPage.locator("text=Frage 1 /")).toBeVisible({ timeout: 15_000 })
    const answerBtns = pageA.locator('[phx-click="select_answer"]')
    await expect(answerBtns).toHaveCount(4, { timeout: 10_000 })

    // Team A picks option 0
    await answerBtns.nth(0).click()
    await expect(pageA.locator("text=Antwort abgegeben")).toBeVisible()

    // Team A changes to option 2
    await answerBtns.nth(2).click()
    await expect(pageA.locator("text=Antwort abgegeben")).toBeVisible()

    // Team B picks option 1
    await pageB.locator('[phx-click="select_answer"]').nth(1).click()

    // Host sees both answered
    await expect(hostPage.locator("text=2 / 2 Teams geantwortet")).toBeVisible({ timeout: 10_000 })

    await ctxA.close()
    await ctxB.close()
  })
})
