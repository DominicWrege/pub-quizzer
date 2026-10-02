import { test, expect, createEvent, joinTeam, joinTeams, startQuiz, pickTopic, waitForLiveView, type Page } from "./fixtures"

const captureErrors = (page: Page, errors: string[]) => {
  page.on("console", message => {
    if (message.type() === "error") errors.push(message.text())
  })
  page.on("pageerror", error => errors.push(error.message))
}

test("the host has compact removal controls and sees missing answers without opening team management", async ({ browser, hostPage }) => {
  const errors: string[] = []
  captureErrors(hostPage, errors)
  const code = await createEvent(hostPage)
  const { pages, contexts } = await joinTeams(browser, code, 2)

  try {
    await startQuiz(hostPage)
    await hostPage.locator("#host-teams summary").click()
    const button = hostPage.locator('[phx-click="ask_remove_team"]').first()
    await button.click()
    await expect(hostPage.locator("#remove-team-modal")).toBeVisible()
    await hostPage.locator("#remove-team-modal-cancel").click()
    const box = await button.boundingBox()
    expect(box!.width).toBeGreaterThanOrEqual(24)
    expect(box!.width).toBeLessThanOrEqual(220)
    expect(box!.height).toBeGreaterThanOrEqual(36)
    expect(box!.height).toBeLessThanOrEqual(48)
    await expect(button).toContainText("Team entfernen")
    await hostPage.locator("#host-teams summary").click()

    await pickTopic(hostPage)
    const [first, second] = pages
    const firstName = (await first.locator("h1").innerText()).trim()
    const secondName = (await second.locator("h1").innerText()).trim()
    await expect(hostPage.locator("#host-pending-teams")).toBeHidden()
    await hostPage.locator("#host-answer-count").click()
    await expect(hostPage.locator("#host-pending-teams")).toBeVisible()
    await expect(hostPage.locator("#host-pending-teams")).toContainText(firstName)
    await expect(hostPage.locator("#host-pending-teams")).toContainText(secondName)
    await waitForLiveView(first)
    await first.locator('[phx-click="select_answer"]').first().click()
    await expect(hostPage.locator("#host-pending-teams")).not.toContainText(firstName)
    await expect(hostPage.locator("#host-pending-teams")).toContainText(secondName)
    expect(errors).toEqual([])
  } finally {
    for (const context of contexts) await context.close()
  }
})

test("the team's timer counts up without resets on answers and restarts for the next question", async ({ browser, hostPage }) => {
  const errors: string[] = []
  captureErrors(hostPage, errors)
  const code = await createEvent(hostPage)
  const contexts = [await browser.newContext(), await browser.newContext()]

  try {
    const first = await contexts[0].newPage()
    const second = await contexts[1].newPage()
    captureErrors(first, errors)
    captureErrors(second, errors)
    await first.clock.install()
    await joinTeam(first, code)
    await joinTeam(second, code)
    await first.clock.pauseAt(new Date(Date.now() + 1000))
    await startQuiz(hostPage)
    await pickTopic(hostPage)
    const timer = first.locator("#team-question-timer [data-timer-value]")
    await expect(timer).toHaveText("00:00")
    const initialClass = await first.locator("#team-question-timer").getAttribute("class")
    await expect(first.locator("main")).not.toContainText("geantwortet")

    await first.clock.runFor(5000)
    await expect(timer).toHaveText("00:05")
    await second.locator('[phx-click="select_answer"]').first().click()
    await expect(hostPage.locator('[data-test="answered-badge"]')).toHaveText(/1\s*\/\s*2/)
    await expect(timer).toHaveText("00:05")

    await first.locator('[phx-click="select_answer"]').first().click()
    await expect(first.locator('[phx-click="select_answer"]').first()).toHaveClass(/btn-primary/)
    await expect(first.locator("main")).not.toContainText("Antwort abgegeben")
    await first.clock.runFor(2000)
    await expect(timer).toHaveText("00:07")
    await first.clock.runFor(54000)
    await expect(timer).toHaveText("01:01")
    await expect(first.locator("#team-question-timer")).toHaveAttribute("class", initialClass!)

    await hostPage.locator('[data-test="advance-button"]').click()
    await expect(first.locator("#team-question-progress")).toContainText("Frage 2")
    await expect(timer).toHaveText("00:00")
    await first.clock.runFor(3000)
    await expect(timer).toHaveText("00:03")

    await hostPage.locator("#host-quiz-menu > summary").click()
    await hostPage.locator("#host-finish-quiz").click()
    await hostPage.locator("#finish-quiz-modal-confirm").click()
    await expect(first.locator("#team-question-timer")).toHaveCount(0)
    expect(errors).toEqual([])
  } finally {
    for (const context of contexts) await context.close()
  }
})
