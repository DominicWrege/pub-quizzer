import { test, expect, createEvent, joinTeams, startQuiz, pickTopic, completeRound } from "./fixtures"

test.describe("multi-round", () => {
  test("host runs two rounds; standings accumulate across rounds", async ({
    browser,
    hostPage,
  }) => {
    test.setTimeout(180_000)

    const code = await createEvent(hostPage, 2)
    const { pages: [pageA, pageB], contexts } = await joinTeams(browser, code, 2)
    await startQuiz(hostPage)
    await pickTopic(hostPage)

    // Complete round 1
    await completeRound(hostPage, pageA, pageB)

    // Click next_round — pause briefly to let the engine flush stale state
    await hostPage.waitForTimeout(2000)
    await hostPage.locator('[phx-click="next_round"]').click()

    // Topic selection reappears for round 2 — pick a different topic
    await hostPage.waitForSelector('[phx-click="choose_topic"]', { timeout: 10_000 })
    const topics = hostPage.locator('[phx-click="choose_topic"]')
    await expect(topics).toHaveCount(5, { timeout: 10_000 })
    await topics.nth(1).click()

    // Teams see the first question of round 2
    const answerBtns = (page: typeof pageA) => page.locator('[phx-click="select_answer"]')
    await expect(answerBtns(pageA)).toHaveCount(4, { timeout: 15_000 })
    await expect(answerBtns(pageB)).toHaveCount(4, { timeout: 15_000 })

    // Teams answer first question of round 2
    await answerBtns(pageA).nth(0).click()
    await answerBtns(pageB).nth(1).click()
    await expect(hostPage.locator("text=2 / 2 Teams geantwortet")).toBeVisible({ timeout: 15_000 })

    for (const ctx of contexts) await ctx.close()
  })

  test("final results reveal after early finish", async ({ browser, hostPage }) => {
    test.setTimeout(120_000)

    const code = await createEvent(hostPage, 2)
    const { pages: [pageA, pageB], contexts } = await joinTeams(browser, code, 2)
    await startQuiz(hostPage)
    await pickTopic(hostPage)

    // Finish early (instead of playing all 6 rounds)
    await hostPage.locator('[phx-click="ask_finish_quiz"]').click()
    await expect(hostPage.locator("#finish-quiz-modal")).toBeVisible({ timeout: 5_000 })
    await hostPage.locator('[phx-click="confirm_finish_quiz"]').click()

    // Reveal final results
    const revealFinal = hostPage.locator('[phx-click="reveal_final_results"]')
    await expect(revealFinal).toBeVisible({ timeout: 10_000 })
    await revealFinal.click()

    // Host shows compact winner line (final podium was minimized away)
    await expect(hostPage.locator("#host-winner-line")).toBeVisible({ timeout: 10_000 })

    // Teams see the final podium
    await expect(pageA.locator('[id^="team-final-"]')).toHaveCount(2, { timeout: 10_000 })
    await expect(pageB.locator('[id^="team-final-"]')).toHaveCount(2, { timeout: 10_000 })

    for (const ctx of contexts) await ctx.close()
  })
})
