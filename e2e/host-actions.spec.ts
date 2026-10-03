import { test, expect, createEvent, joinTeams, startQuiz, pickTopic, completeRound, setupQuiz } from "./fixtures"

test.describe("host actions", () => {
  test("host can kick a team; team is redirected home", async ({ browser, hostPage }) => {
    test.setTimeout(120_000)

    const code = await createEvent(hostPage, 2)
    const { pages: [pageA], contexts } = await joinTeams(browser, code, 1)

    // Team A is registered. Connection status is secondary and never gates start.
    await expect(hostPage.locator("#event-teams >> text=Angemeldet")).toBeVisible({
      timeout: 10_000,
    })

    // Host kicks team A
    await hostPage.locator("#event-teams [phx-click='kick_team']").first().click()

    // Team A sees the kicked flash and is redirected to home
    await expect(pageA.locator("text=Du wurdest vom Moderator aus dem Team entfernt")).toBeVisible({
      timeout: 10_000,
    })
    await expect(pageA).toHaveURL("/", { timeout: 10_000 })

    for (const ctx of contexts) await ctx.close()
  })

  test("host can go straight to the next topic without opening the stats panel", async ({
    browser,
    hostPage,
  }) => {
    test.setTimeout(120_000)

    const code = await createEvent(hostPage, 2)
    const { pages: [pageA, pageB], contexts } = await joinTeams(browser, code, 2)
    await startQuiz(hostPage)
    await pickTopic(hostPage)

    // Complete the round without touching the collapsed stats panel
    await completeRound(hostPage, pageA, pageB, 0, 1, false)

    // Winner or tie banner sits next to the next-topic button
    await expect(
      hostPage
        .locator("text=gewinnt die Runde")
        .or(hostPage.locator("text=Remis")),
    ).toBeVisible({ timeout: 10_000 })
    await expect(hostPage.locator('[phx-click="next_round"]')).toBeVisible()

    // Stats stay collapsed; the open ranking panel is host-only
    await expect(hostPage.locator("#host-round-stats[open]")).toHaveCount(0)
    await expect(hostPage.locator("#host-round-standings[open]")).toHaveCount(1)
    await expect(pageA.locator('[id^="team-standing-"]')).toHaveCount(0)

    // Go straight to the next topic
    await hostPage.locator('[phx-click="next_round"]').click()

    // Topic selection reappears for next round
    await hostPage.waitForSelector('[phx-click="choose_topic"]', { timeout: 10_000 })

    for (const ctx of contexts) await ctx.close()
  })

  test("host can cancel the finish-quiz modal", async ({ browser, hostPage }) => {
    test.setTimeout(120_000)

    const { contexts } = await setupQuiz(hostPage, browser, 2)

    // Open finish modal
    await hostPage.locator("#host-finish-quiz").click()
    await expect(hostPage.locator("#finish-quiz-modal")).toBeVisible({ timeout: 5_000 })

    // Cancel it
    await hostPage.locator("#finish-quiz-modal button[aria-label='Schließen']").click()
    await expect(hostPage.locator("#finish-quiz-modal")).not.toBeVisible({ timeout: 5_000 })

    // Quiz is still running — "Nächste Frage" or question text still visible
    await expect(hostPage.locator("text=Frage 1 /")).toBeVisible({ timeout: 5_000 })

    for (const ctx of contexts) await ctx.close()
  })
})
