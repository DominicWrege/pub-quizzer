import { test, expect, createEvent, joinTeams, startQuiz, pickTopic, completeRound, waitForLiveView } from "./fixtures"

test.describe("results page", () => {
  test("results page shows per-round answer matrix after a round", async ({ browser, hostPage }) => {
    test.setTimeout(120_000)

    const code = await createEvent(hostPage, 2)
    const { pages: [pageA, pageB], contexts } = await joinTeams(browser, code, 2)
    await startQuiz(hostPage)
    await pickTopic(hostPage)

    // Play one full round with standings
    await completeRound(hostPage, pageA, pageB)

    // Navigate to the results page via the "Live" link on the event show page.
    // We need the event ID — extract from the host lobby URL code.
    const hostUrl = hostPage.url()
    const quizCode = hostUrl.match(/\/quiz\/(\d{4})\/host/)?.[1] ?? ""

    // Go to events index, find the event, and navigate to results
    await hostPage.goto("/admin/events")
    await waitForLiveView(hostPage)

    // Filter by our quiz code so the results link resolves to OUR event even
    // when other tests run in parallel and add events to the shared list.
    const search = hostPage.locator('[phx-change="search"] input')
    await expect(search).toBeVisible({ timeout: 10_000 })
    await search.fill(quizCode)

    const liveLink = hostPage.locator(`a[href*="/results"]`).first()
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
