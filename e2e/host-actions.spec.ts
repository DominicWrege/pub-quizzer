import { test, expect, createEvent, joinTeams, startQuiz, pickTopic, completeRound, setupQuiz } from "./fixtures"

test.describe("host actions", () => {
  test("host can kick a team; team is redirected home", async ({ browser, hostPage }) => {
    test.setTimeout(120_000)

    const code = await createEvent(hostPage, 2)
    const { pages: [pageA], contexts } = await joinTeams(browser, code, 1)

    // Team A is connected (shows "Beigetreten" badge in the desktop table)
    await expect(hostPage.locator("#event-teams >> text=Beigetreten")).toBeVisible({
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

  test("host can skip standings (Weiter zur Kategorie) and go straight to next topic", async ({
    browser,
    hostPage,
  }) => {
    test.setTimeout(120_000)

    const code = await createEvent(hostPage, 2)
    const { pages: [pageA, pageB], contexts } = await joinTeams(browser, code, 2)
    await startQuiz(hostPage)
    await pickTopic(hostPage)

    // Complete round WITHOUT showing standings
    await completeRound(hostPage, pageA, pageB, 0, 1, false)

    // Winner or tie banner is visible (team-facing options are shuffled, so a
    // clear winner is not guaranteed) but standings are NOT shown
    await expect(
      hostPage
        .locator("text=gewinnt Runde")
        .or(hostPage.locator("text=Remis! Kein eindeutiger Gewinner.")),
    ).toBeVisible({ timeout: 10_000 })
    await expect(hostPage.locator('[id^="standing-"]')).toHaveCount(0)

    // Click "Weiter zur Kategorie" to skip standings
    await hostPage.locator("button", { hasText: "Weiter zur Kategorie" }).click()

    // Topic selection reappears for next round
    await hostPage.waitForSelector('[phx-click="choose_topic"]', { timeout: 10_000 })

    for (const ctx of contexts) await ctx.close()
  })

  test("host can cancel the finish-quiz modal", async ({ browser, hostPage }) => {
    test.setTimeout(120_000)

    const { contexts } = await setupQuiz(hostPage, browser, 2)

    // Open finish modal
    await hostPage.locator('[phx-click="ask_finish_quiz"]').click()
    await expect(hostPage.locator("#finish-quiz-modal")).toBeVisible({ timeout: 5_000 })

    // Cancel it
    await hostPage.locator("#finish-quiz-modal button", { hasText: "Abbrechen" }).click()
    await expect(hostPage.locator("#finish-quiz-modal")).not.toBeVisible({ timeout: 5_000 })

    // Quiz is still running — "Nächste Frage" or question text still visible
    await expect(hostPage.locator("text=Frage 1 /")).toBeVisible({ timeout: 5_000 })

    for (const ctx of contexts) await ctx.close()
  })
})
