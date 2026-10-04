import { test, expect, loginAsHost, setupQuiz, type BrowserContext } from "./fixtures"

test("the host can read all A–D answers at 23px on an 11-inch portrait tablet", async ({ browser }) => {
  const context = await browser.newContext({
    baseURL: "http://localhost:4001",
    viewport: { width: 834, height: 1194 },
    hasTouch: true,
  })
  const host = await context.newPage()
  const errors: string[] = []
  host.on("console", message => {
    if (message.type() === "error") errors.push(message.text())
  })
  host.on("pageerror", error => errors.push(error.message))
  const teamContexts: BrowserContext[] = []

  try {
    await loginAsHost(host)
    const quiz = await setupQuiz(host, browser, 1)
    teamContexts.push(...quiz.contexts)

    const question = host.locator('[data-test="question-prompt"]')
    const rows = host.locator('[data-test="distribution-row"]')
    await expect(question).toBeVisible()
    await expect(rows).toHaveCount(4)
    await expect(host.locator("#host-question-card h2, #host-question-card h3, #host-question-card h4"))
      .toHaveCount(1)

    for (const viewport of [{ width: 834, height: 1194 }, { width: 820, height: 1180 }]) {
      await host.setViewportSize(viewport)
      await expect(question).toHaveCSS("font-size", "23px")
      expect(Number.parseFloat(await question.evaluate(element => getComputedStyle(element).lineHeight)))
        .toBeGreaterThanOrEqual(32)

      const layout = await rows.evaluateAll(elements => elements.map(row => {
        const letter = row.children[0]
        const answer = row.children[1]
        const letterBox = letter.getBoundingClientRect()
        const answerBox = answer.getBoundingClientRect()
        const style = getComputedStyle(answer)
        return {
          letter: letter.textContent?.trim(),
          fontSize: style.fontSize,
          lineHeight: Number.parseFloat(style.lineHeight),
          letterTop: letterBox.top,
          answerTop: answerBox.top,
          answerLeft: answerBox.left,
          answerBottom: answerBox.bottom,
          rowBottom: row.getBoundingClientRect().bottom,
          whiteSpace: style.whiteSpace,
        }
      }))
      expect(layout.map(row => row.letter)).toEqual(["A", "B", "C", "D"])
      for (const row of layout) {
        expect(row.fontSize).toBe("23px")
        expect(row.lineHeight).toBeGreaterThanOrEqual(32)
        expect(Math.abs(row.letterTop - row.answerTop)).toBeLessThanOrEqual(2)
        expect(row.answerLeft).toBeCloseTo(layout[0].answerLeft, 0)
        expect(row.rowBottom).toBeGreaterThan(row.answerBottom)
        expect(row.whiteSpace).not.toBe("nowrap")
      }
      expect(await host.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)).toBe(true)
      expect(await host.locator("#host-question-card").evaluate(element => getComputedStyle(element).maxHeight))
        .toBe("none")
      await expect(host.locator("#host-teams")).toHaveCSS("margin-top", "64px")
      await rows.last().scrollIntoViewIfNeeded()
      await expect(rows.last()).toBeInViewport()
    }

    const team = quiz.pages[0]
    await team.locator('[phx-click="select_answer"]').first().click()
    await expect(host.locator("#host-answer-count")).toHaveText(/1\s*\/\s*1/)
    await expect(rows).toHaveCount(4)
    await expect(host.locator("#host-answer-text-0")).toHaveCSS("font-size", "23px")
    await host.locator("#host-answer-count").click()
    await expect(host.locator("#host-pending-teams")).toBeVisible()
    await host.locator('[data-test="advance-button"]').click()
    await expect(host.locator("header h3")).toHaveText("Frage 2 / 5")
    await expect(host.locator("#host-pending-teams")).toBeHidden()
    await expect(question).toHaveCSS("font-size", "23px")
    expect(errors).toEqual([])
  } finally {
    for (const teamContext of teamContexts) await teamContext.close()
    await context.close()
  }
})
