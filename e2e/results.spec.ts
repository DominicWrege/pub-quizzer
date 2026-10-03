import { test, expect, createEvent, joinTeams, startQuiz, pickTopic, completeRound, waitForLiveView } from "./fixtures"

test.describe("results page", () => {
  test("results page shows per-round answer matrix after a round", async ({ browser, hostPage }) => {
    test.setTimeout(120_000)

    const code = await createEvent(hostPage, 2)
    const eventId = new URL(hostPage.url()).pathname.split("/").filter(Boolean).pop()!
    const { pages: [pageA, pageB], contexts } = await joinTeams(browser, code, 2)
    await startQuiz(hostPage)
    await pickTopic(hostPage)

    // Play one full round with standings
    await completeRound(hostPage, pageA, pageB)

    // Go to the events index and open the results page via our event card.
    await hostPage.goto("/admin/events")
    await waitForLiveView(hostPage)

    const liveLink = hostPage.locator(`#event-${eventId} a[href*="/results"]`).first()
    await expect(liveLink).toBeVisible({ timeout: 10_000 })
    await liveLink.click()

    await expect(hostPage).toHaveURL(/\/admin\/events\/\d+\/results$/, { timeout: 10_000 })

    // Results page shows the standings header and at least one round table
    await expect(hostPage.locator("text=Gesamtwertung")).toBeVisible({ timeout: 10_000 })
    await expect(hostPage.locator("text=Runde 1:")).toBeVisible({ timeout: 10_000 })

    // Verify the per-question answer cells exist (2 teams × N questions)
    const answerCells = hostPage.locator("table tbody td:has(.font-mono)")
    await expect(answerCells.first()).toBeVisible({ timeout: 10_000 })

    for (const ctx of contexts) await ctx.close()
  })
})
