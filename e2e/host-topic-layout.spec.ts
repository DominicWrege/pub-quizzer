import { test, expect, createEvent, joinTeams, startQuiz } from "./fixtures"

test("topic buttons stay within the moderator viewport on a phone", async ({ browser, hostPage }) => {
  const code = await createEvent(hostPage)
  const { contexts } = await joinTeams(browser, code, 2)

  try {
    await startQuiz(hostPage)
    await hostPage.setViewportSize({ width: 390, height: 844 })

    const topics = hostPage.locator('[phx-click="choose_topic"]')
    await expect(topics.first()).toBeVisible()

    for (const topic of await topics.all()) {
      const button = await topic.boundingBox()
      const label = await topic.locator("span.font-bold").boundingBox()
      expect(button).not.toBeNull()
      expect(label).not.toBeNull()
      expect(button!.x).toBeGreaterThanOrEqual(0)
      expect(button!.x + button!.width).toBeLessThanOrEqual(390)
      expect(label!.x).toBeGreaterThanOrEqual(button!.x)
      expect(label!.x + label!.width).toBeLessThanOrEqual(button!.x + button!.width)
    }
  } finally {
    for (const context of contexts) await context.close()
  }
})
