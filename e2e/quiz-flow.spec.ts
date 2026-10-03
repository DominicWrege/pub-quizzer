import { test, expect, setupQuiz, completeRound } from "./fixtures"

test.describe("quiz flow", () => {
  test("host runs a full round; teams see synced state across tabs", async ({
    browser,
    hostPage,
  }) => {
    test.setTimeout(120_000)

    const { code, pages: [teamAPage, teamBPage], contexts } = await setupQuiz(hostPage, browser, 2)
    expect(code).toMatch(/^\d{4}$/)

    // Teams see the first question (realtime sync)
    const teamAnswerBtns = (page: { locator: (s: string) => ReturnType<typeof teamAPage.locator> }) =>
      page.locator('[phx-click="select_answer"]')
    await expect(teamAnswerBtns(teamAPage)).toHaveCount(4, { timeout: 15_000 })
    await expect(teamAnswerBtns(teamBPage)).toHaveCount(4, { timeout: 15_000 })

    // Play the full round using the shared helper (answer → advance → reveal)
    await completeRound(hostPage, teamAPage, teamBPage)

    // Teams see the round winner (cross-tab PubSub sync) but never the ranking
    await expect(
      teamAPage
        .locator("text=hat Runde 1 gewonnen")
        .or(teamAPage.locator("text=Remis!")),
    ).toBeVisible({ timeout: 10_000 })
    await expect(teamAPage.locator('[id^="team-standing-"]')).toHaveCount(0)
    await expect(teamBPage.locator('[id^="team-standing-"]')).toHaveCount(0)

    for (const ctx of contexts) await ctx.close()
  })
})
