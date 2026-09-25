import { test, expect, setupQuiz } from "./fixtures"

test("team sees topic, question progress and choices on a phone without the prompt or overflow", async ({
  browser,
  hostPage,
}, testInfo) => {
  const { pages: [team], contexts } = await setupQuiz(hostPage, browser, 2)
  const errors: string[] = []

  try {
    team.on("pageerror", (error) => errors.push(error.message))
    team.on("console", (message) => {
      if (message.type() === "error") errors.push(message.text())
    })
    await team.setViewportSize({ width: 390, height: 844 })

    const prompt = (await hostPage.locator('[data-test="question-prompt"]').innerText()).trim()
    const topic = (await hostPage.locator("h3:has-text('Frage 1 /') + span").innerText()).trim()
    await expect(team.locator("#team-question-topic")).toHaveText(topic)
    await expect(team.locator("#team-question-progress")).toContainText(/Frage 1 \/ \d+/)
    await expect(team.locator("#team-question-prompt")).toHaveCount(0)
    await expect(team.locator("main")).not.toContainText(prompt)
    await expect(team.locator('[phx-click="select_answer"]')).toHaveCount(4)
    await expect(team.locator("main")).not.toContainText("Richtige Antwort:")

    const { viewport, content } = await team.evaluate(() => ({
      viewport: window.innerWidth,
      content: document.documentElement.scrollWidth,
    }))
    expect(content).toBeLessThanOrEqual(viewport)

    await team.screenshot({ path: testInfo.outputPath("team-question-mobile.png"), fullPage: true })
    await hostPage.screenshot({ path: testInfo.outputPath("moderator-question-desktop.png"), fullPage: true })
    expect(errors).toEqual([])
  } finally {
    for (const context of contexts) await context.close()
  }
})
