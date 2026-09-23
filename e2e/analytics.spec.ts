import { test, expect, setupQuiz, completeRound } from "./fixtures"

test("finished quiz retains moderator question and team statistics", async ({
  browser,
  hostPage,
}, testInfo) => {
  test.setTimeout(120_000)
  const { pages: [teamA, teamB], contexts } = await setupQuiz(hostPage, browser, 2)
  const errors: string[] = []

  try {
    hostPage.on("pageerror", (error) => errors.push(error.message))
    hostPage.on("console", (message) => {
      if (message.type() === "error") errors.push(message.text())
    })

    await completeRound(hostPage, teamA, teamB)
    await hostPage.locator('[phx-click="next_round"]').click()
    await hostPage.locator('[phx-click="ask_finish_quiz"]').click()
    await hostPage.locator('[phx-click="confirm_finish_quiz"]').click()

    await hostPage.goto("/admin/question-report")
    const questionRows = hostPage.locator('table tbody tr[id^="question-report-"]')
    await expect(questionRows).toHaveCount(5)
    await expect(questionRows.first()).toContainText("Richtig:")
    await hostPage.screenshot({ path: testInfo.outputPath("question-report-desktop.png"), fullPage: true })
    expect(errors).toEqual([])
  } finally {
    for (const context of contexts) await context.close()
  }
})
