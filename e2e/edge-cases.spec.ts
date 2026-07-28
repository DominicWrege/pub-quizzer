import { test, expect, createEvent, joinTeams, startQuiz, pickTopic, completeRound } from "./fixtures"

test.describe("edge cases", () => {
  test("round reveal → standings → next round topic selection", async ({ browser, hostPage }) => {
    test.setTimeout(120_000)

    const code = await createEvent(hostPage, 2)
    const { pages: [pageA, pageB], contexts } = await joinTeams(browser, code, 2)
    await startQuiz(hostPage)
    await pickTopic(hostPage)

    // Play round with default answers (team A wins) then reveal + show standings.
    await completeRound(hostPage, pageA, pageB)

    // Standings are shown — click "Nächste Runde"
    await hostPage.locator('[phx-click="next_round"]').click()
    await hostPage.waitForSelector('[phx-click="choose_topic"]', { timeout: 10_000 })

    for (const ctx of contexts) await ctx.close()
  })

  test("team can change answer before host advances", async ({ browser, hostPage }) => {
    test.setTimeout(120_000)

    const code = await createEvent(hostPage, 2)
    const { pages: [pageA, pageB], contexts } = await joinTeams(browser, code, 2)
    await startQuiz(hostPage)
    await pickTopic(hostPage)

    // Team pages get answer buttons
    const answerBtns = pageA.locator('[phx-click="select_answer"]')
    await expect(answerBtns).toHaveCount(4, { timeout: 15_000 })

    // Team A picks option 0
    await answerBtns.nth(0).click()
    await expect(pageA.locator("text=Antwort abgegeben")).toBeVisible()

    // Team A changes to option 2
    await answerBtns.nth(2).click()
    await expect(pageA.locator("text=Antwort abgegeben")).toBeVisible()

    // Team B picks option 1
    await pageB.locator('[phx-click="select_answer"]').nth(1).click()

    // Host sees both answered
    await expect(hostPage.locator("text=2 / 2 Teams geantwortet")).toBeVisible({ timeout: 15_000 })

    for (const ctx of contexts) await ctx.close()
  })
})
