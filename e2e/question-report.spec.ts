import { test, expect, setupQuiz, waitForLiveView } from "./fixtures"

test("question analysis lives only in the shared report, with compact responsive highlights", async ({ browser, hostPage }, testInfo) => {
  const errors: string[] = []
  hostPage.on("console", message => {
    if (message.type() === "error") errors.push(message.text())
  })
  hostPage.on("pageerror", error => errors.push(error.message))

  const { code, pages, contexts } = await setupQuiz(hostPage, browser, 2)
  try {
    for (let number = 1; number <= 5; number++) {
      await expect(hostPage.locator(`text=Frage ${number} /`)).toBeVisible()
      await pages[0].locator('[phx-click="select_answer"]').nth(0).click()
      await pages[1].locator('[phx-click="select_answer"]').nth(1).click()
      await expect(hostPage.locator('[data-test="answered-badge"]')).toHaveText(/2\s*\/\s*2/)
      await hostPage.locator('[phx-click="next_question"]').click()
    }
    await expect(hostPage.locator('[phx-click="next_round"]')).toBeVisible()
    await hostPage.locator("#host-finish-quiz").click()
    await hostPage.locator('#finish-quiz-modal [phx-click="confirm_finish_quiz"]').click()
    await expect(hostPage.locator('[phx-click="reveal_final_results"]')).toBeVisible()

    await hostPage.goto("/admin/events")
    await waitForLiveView(hostPage)
    await expect(hostPage.locator('main a[href$="/report"]')).toHaveCount(0)

    await hostPage.goto("/admin/question-report")
    await waitForLiveView(hostPage)
    const eventID = await hostPage.locator("#question-report-quiz option").filter({ hasText: code }).getAttribute("value")
    expect(eventID).toBeTruthy()
    await hostPage.locator("#question-report-quiz").selectOption(eventID!)
    const highlights = hostPage.locator("#question-report-highlights")
    await expect(highlights.locator('[data-test="highlight-question"]')).toHaveCount(3)
    for (const label of await highlights.locator('[data-test="highlight-question"]').allTextContents()) {
      expect(label.trim()).toMatch(/^.+ · Frage [1-5]$/)
    }
    await expect(hostPage.locator('#question-report-hardest [data-test="highlight-value"]')).toHaveText(/\d+ % richtig/)
    await expect(hostPage.locator('#question-report-trap [data-test="highlight-value"]')).toHaveText(/[A-D] · \d+× gewählt/)

    await hostPage.locator('[id^="view-question-"]').first().click()
    const prompt = await hostPage.locator("#question-report-details p").innerText()
    await expect(highlights).not.toContainText(prompt)
    await hostPage.locator("#question-report-details-close").click()
    await expect(hostPage.locator("#question-report-details")).toHaveCount(0)

    for (const viewport of [
      { width: 390, height: 844 },
      { width: 768, height: 1024 },
      { width: 1280, height: 800 },
    ]) {
      await hostPage.setViewportSize(viewport)
      await expect(highlights).toBeVisible()
      expect(await hostPage.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
      await hostPage.screenshot({ path: testInfo.outputPath(`question-report-${viewport.width}.png`), animations: "disabled" })
    }

    await hostPage.locator("#question-report-quiz").selectOption("")
    await expect(highlights).toBeVisible()
    const oldReport = await hostPage.request.get(`/admin/events/${eventID}/report`)
    expect(oldReport.status()).toBe(404)
    expect(errors).toEqual([])
  } finally {
    for (const context of contexts) await context.close()
  }
})
