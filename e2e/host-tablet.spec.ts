import { test, expect, setupQuiz, createEvent, joinTeams, startQuiz, pickTopic } from "./fixtures"

test("the moderator's question and answers use compact tablet typography with a touch-sized advance button", async ({ browser, hostPage }) => {
  await hostPage.setViewportSize({ width: 820, height: 1180 })
  const { contexts } = await setupQuiz(hostPage, browser, 2)

  try {
    const promptSize = await hostPage.locator('[data-test="question-prompt"]').evaluate(element => parseFloat(getComputedStyle(element).fontSize))
    const answerSize = await hostPage.locator('[data-test="distribution-row"] > span').nth(1).evaluate(element => parseFloat(getComputedStyle(element).fontSize))
    expect(promptSize).toBeGreaterThan(20)
    expect(promptSize).toBeLessThanOrEqual(21)
    expect(answerSize).toBeGreaterThan(18)
    expect(answerSize).toBeLessThanOrEqual(19)
    await expect(hostPage.locator('[data-test="distribution-row"] > span:nth-child(3)')).toHaveCount(0)
    const button = await hostPage.locator('[data-test="advance-button"]').boundingBox()
    expect(button!.height).toBeGreaterThanOrEqual(44)
    expect(await hostPage.evaluate(() => document.documentElement.scrollWidth > innerWidth)).toBe(false)
  } finally {
    for (const context of contexts) await context.close()
  }
})

test("the answer count toggles missing teams and skipped answers require confirmation", async ({ browser, hostPage }) => {
  const errors: string[] = []
  const capture = (page: typeof hostPage) => {
    page.on("console", message => { if (message.type() === "error") errors.push(message.text()) })
    page.on("pageerror", error => errors.push(error.message))
  }
  capture(hostPage)
  const code = await createEvent(hostPage, 2)
  const { pages: [first, second], contexts } = await joinTeams(browser, code, 2)
  capture(first)
  capture(second)

  try {
    await startQuiz(hostPage)
    await pickTopic(hostPage)
    const pending = hostPage.locator("#host-pending-teams")
    await expect(pending).toBeHidden()
    await hostPage.locator("#host-answer-count").click()
    await expect(pending).toBeVisible()
    await expect(pending).toContainText("Team 1")
    await expect(pending).toContainText("Team 2")
    await hostPage.locator("#host-answer-count").click()
    await expect(pending).toBeHidden()
    await hostPage.locator("#host-answer-count").click()

    await first.locator('[phx-click="select_answer"]').first().click()
    await expect(pending).not.toContainText("Team 1")
    await expect(pending).toContainText("Team 2")
    const advance = hostPage.locator('[data-test="advance-button"]')
    await expect(advance).toBeEnabled()
    await advance.click()
    await expect(hostPage.locator("#next-question-modal")).toContainText("Team 2")
    await expect(hostPage.locator("#next-question-modal")).not.toContainText("Team 1")
    await hostPage.locator("#next-question-modal-cancel").click()
    await expect(first.locator("#team-question-progress")).toContainText("Frage 1")
    await advance.click()
    await hostPage.locator("#next-question-modal-confirm").click()
    await expect(second.locator("#team-question-progress")).toContainText("Frage 2")
    await expect(pending).toBeHidden()
    await hostPage.locator("#host-answer-count").click()
    await expect(pending).toBeVisible()

    await hostPage.locator("#host-quiz-menu > summary").click()
    await hostPage.locator("#host-finish-quiz").click()
    await expect(hostPage.locator("#host-quiz-menu")).not.toHaveAttribute("open")
    await expect(hostPage.locator("#finish-quiz-modal")).toBeVisible()
    await hostPage.locator("#finish-quiz-modal-cancel").click()
    expect(errors).toEqual([])
  } finally {
    for (const context of contexts) await context.close()
  }
})
