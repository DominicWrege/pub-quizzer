import { test, expect, createEvent, joinTeams, startQuiz, pickTopic, waitForLiveView } from "./fixtures"

for (const width of [390, 1280]) {
  test(`host switches between live results and the console without losing the current question at ${width}px`, async ({ browser, hostPage }) => {
    const errors: string[] = []
    hostPage.on("console", message => {
      if (message.type() === "error") errors.push(message.text())
    })
    hostPage.on("pageerror", error => errors.push(error.message))
    await hostPage.setViewportSize({ width, height: 844 })
    const code = await createEvent(hostPage)
    const { pages, contexts } = await joinTeams(browser, code, 1)
    try {
      await startQuiz(hostPage)
      await pickTopic(hostPage)
      await pages[0].locator("#team-answer-0").click()
      await expect(hostPage.locator("#host-answer-count")).toHaveText("1 / 1")
      const prompt = await hostPage.locator("[data-test='question-prompt']").textContent()
      const live = hostPage.locator("header #host-live-values")
      await expect(live).toBeVisible()
      await expect(live.locator("svg")).toBeVisible()
      expect((await live.boundingBox())!.height).toBeGreaterThanOrEqual(44)
      await live.click()
      await expect(hostPage).toHaveURL(/\/admin\/events\/\d+\/results$/)
      await waitForLiveView(hostPage)
      await expect(hostPage.locator("#results-nav-title")).toBeVisible()
      await expect(hostPage.locator("#nav-drawer-toggle")).toHaveCount(0)
      await expect(hostPage.locator("header a[href='/']")).toHaveCount(0)
      await expect(hostPage.locator("#results-host-console")).toHaveText("Moderator")
      await expect(hostPage.locator("#results-host-console svg")).toBeVisible()
      expect((await hostPage.locator("#results-host-console").boundingBox())!.height).toBeGreaterThanOrEqual(44)
      expect(await hostPage.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)).toBe(true)
      await hostPage.locator("#results-host-console").click()
      await expect(hostPage).toHaveURL(`/quiz/${code}/host`)
      await waitForLiveView(hostPage)
      await expect(hostPage.locator("[data-test='question-prompt']")).toHaveText(prompt!)
      await expect(hostPage.locator("#host-answer-count")).toHaveText("1 / 1")
      expect(await hostPage.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)).toBe(true)
      expect(errors).toEqual([])
    } finally {
      await Promise.all(contexts.map(context => context.close()))
    }
  })
}
