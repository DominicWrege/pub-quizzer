import { test, expect, setupQuiz, waitForLiveView } from "./fixtures"

test("a hybrid round collects complete paper sheets before revealing", async ({ hostPage, browser }, testInfo) => {
  const errors: string[] = []
  const capture = (page: typeof hostPage) => {
    page.on("console", message => {
      if (message.type() === "error") errors.push(message.text())
    })
    page.on("pageerror", error => errors.push(error.message))
  }
  capture(hostPage)
  const { pages, contexts } = await setupQuiz(hostPage, browser, 2)
  pages.forEach(capture)

  try {
    const [paperPhone, digitalPhone] = pages
    // A mid-round failure must not lose answers already submitted digitally.
    await paperPhone.locator("#team-answer-0").click()
    await expect(paperPhone.locator("#team-answer-0")).toHaveClass(/btn-primary/)
    await hostPage.locator("#host-teams summary").click()
    const modeButton = hostPage.locator('[id^="host-paper-team-"]').first()
    expect((await modeButton.boundingBox())!.height).toBeLessThanOrEqual(30)
    const fallbackStyle = await modeButton.evaluate(element => {
      const style = getComputedStyle(element)
      return {
        background: style.backgroundColor,
        border: style.borderWidth,
        noShadow: style.boxShadow === "none" ||
          style.boxShadow.replaceAll("rgba(0, 0, 0, 0)", "").replaceAll("0px", "").replace(/[\s,]/g, "") === "",
      }
    })
    expect(fallbackStyle).toEqual({ background: "rgba(0, 0, 0, 0)", border: "0px", noShadow: true })
    await hostPage.locator('[id^="host-paper-team-"]').first().click()
    await expect(modeButton).toContainText("Zurück zum Handy")
    await expect(modeButton.locator("svg")).toHaveCount(0)
    await expect(hostPage.locator("#host-paper-round svg")).toHaveCount(0)
    await expect(paperPhone.locator("#team-paper-mode")).toBeVisible()
    await expect(paperPhone.locator('[phx-click="select_answer"]')).toHaveCount(0)

    const progress = await paperPhone.locator("#team-question-progress").textContent()
    const questionCount = Number(progress?.match(/\/\s*(\d+)/)?.[1])
    expect(questionCount).toBeGreaterThan(1)

    // The host can advance every question without a missing-answer dialog for the paper team.
    for (let question = 1; question <= questionCount; question++) {
      await expect(digitalPhone.locator("#team-question-progress")).toContainText(`Frage ${question} /`)
      await digitalPhone.locator("#team-answer-0").click()
      await expect(hostPage.locator("#host-answer-count")).toHaveText(/1\s*\/\s*1/)
      await hostPage.locator('[data-test="advance-button"]').click()
      await expect(hostPage.locator("#next-question-modal")).toHaveCount(0)
    }

    const dialog = hostPage.locator("#paper-answers-dialog")
    await expect(dialog).toBeVisible()
    await expect(hostPage.locator("#host-round-standings")).toHaveCount(0)
    await expect(hostPage.locator("#paper-save")).toBeDisabled()
    await expect(hostPage.locator('[data-test="advance-button"] svg')).toHaveCount(0)

    // Reload/rejoin also preserves the round's paper assignment.
    await paperPhone.reload()
    await waitForLiveView(paperPhone)
    await expect(paperPhone.locator("#team-paper-mode")).toBeVisible()

    const rows = dialog.locator("fieldset")
    await expect(rows).toHaveCount(questionCount)
    await hostPage.setViewportSize({ width: 1024, height: 768 })
    const entryButton = hostPage.locator('[id^="host-enter-paper-"]').first()
    expect((await entryButton.boundingBox())!.height).toBeLessThanOrEqual(30)
    expect(await entryButton.evaluate(element => getComputedStyle(element).borderWidth)).toBe("0px")
    expect(await entryButton.evaluate(element => getComputedStyle(element).backgroundColor)).toBe("rgba(0, 0, 0, 0)")
    const layout = await dialog.evaluate(element => {
      const rowElements = Array.from(element.querySelectorAll("fieldset"))
      const bounds = rowElements.map(row => row.getBoundingClientRect())
      const footer = element.querySelector("#paper-save")!.parentElement!.getBoundingClientRect()
      const choices = Array.from(element.querySelectorAll("fieldset button")).map(button => button.getBoundingClientRect())
      return {
        tallestRow: Math.max(...bounds.map(box => box.height)),
        lastRowBottom: bounds.at(-1)!.bottom,
        footerTop: footer.top,
        largestChoice: Math.max(...choices.map(box => Math.max(box.width, box.height))),
        smallestChoice: Math.min(...choices.map(box => Math.min(box.width, box.height))),
        inlineChoices: rowElements.every(row => {
          const buttons = Array.from(row.querySelectorAll("button")).map(button => button.getBoundingClientRect())
          return buttons.every(box => Math.abs(box.top - buttons[0].top) < 1)
        }),
      }
    })
    expect(layout.tallestRow).toBeLessThanOrEqual(76)
    expect(layout.largestChoice).toBeLessThanOrEqual(50)
    expect(layout.smallestChoice).toBeGreaterThanOrEqual(44)
    expect(layout.inlineChoices).toBe(true)
    expect(layout.lastRowBottom).toBeLessThanOrEqual(layout.footerTop)
    await expect(rows.first().locator('[id^="paper-existing-"]')).toContainText("Digital")
    for (let question = 0; question < questionCount; question++) {
      await rows.nth(question).getByRole("button", { name: "B", exact: true }).click()
      await expect(rows.nth(question).getByRole("button", { name: "B", exact: true })).toHaveAttribute("aria-pressed", "true")
    }
    await expect(hostPage.locator("#paper-save")).toBeEnabled()
    await expect(dialog.locator("[data-phx-ref-loading]")).toHaveCount(0)
    await hostPage.mouse.move(0, 0)
    await expect.poll(async () => {
      const primary = await hostPage.locator("#paper-save").evaluate(element => getComputedStyle(element).backgroundColor)
      const selected = await dialog.locator('fieldset button[aria-pressed="true"]').evaluateAll(elements => elements.map(element => getComputedStyle(element).backgroundColor))
      return selected.length === questionCount && selected.every(color => color === primary)
    }).toBe(true)
    const primaryBackground = await hostPage.locator("#paper-save").evaluate(element => getComputedStyle(element).backgroundColor)

    // Actual touch input in landscape and portrait, without saving a second draft.
    const tabletContext = await browser.newContext({ hasTouch: true, viewport: { width: 1024, height: 768 } })
    await tabletContext.addCookies(await hostPage.context().cookies())
    try {
      const tablet = await tabletContext.newPage()
      capture(tablet)
      await tablet.goto(hostPage.url())
      await waitForLiveView(tablet)
      await tablet.locator('[id^="host-enter-paper-"]').first().tap()
      const tabletDialog = tablet.locator("#paper-answers-dialog")
      for (const viewport of [{ width: 1024, height: 768 }, { width: 768, height: 1024 }]) {
        await tablet.setViewportSize(viewport)
        const bounds = await tabletDialog.evaluate(element => {
          const buttons = Array.from(element.querySelectorAll("fieldset button")).map(button => button.getBoundingClientRect())
          const lastRow = element.querySelector("fieldset:last-child")!.getBoundingClientRect()
          const footer = element.querySelector("#paper-save")!.parentElement!.getBoundingClientRect()
          return {
            smallestTarget: Math.min(...buttons.map(box => Math.min(box.width, box.height))),
            allRowsVisible: lastRow.bottom <= footer.top,
            fits: element.scrollWidth <= element.clientWidth,
          }
        })
        expect(bounds.smallestTarget).toBeGreaterThanOrEqual(44)
        expect(bounds.allRowsVisible).toBe(true)
        expect(bounds.fits).toBe(true)
        const choice = tabletDialog.locator("fieldset").first().getByRole("button", { name: "B", exact: true })
        await choice.tap()
        await expect(choice).toHaveAttribute("aria-pressed", "true")
        await expect(tabletDialog.locator("fieldset").first().getByRole("button", { name: "A", exact: true })).toHaveAttribute("aria-pressed", "false")
      }
      const blank = tabletDialog.locator("fieldset").last().getByRole("button", { name: "Keine Antwort", exact: true })
      await blank.tap()
      await expect(blank).toHaveAttribute("aria-pressed", "true")
      await expect.poll(() => blank.evaluate(element => getComputedStyle(element).backgroundColor)).toBe(primaryBackground)
      await tablet.locator("#paper-answers-close").tap()
    } finally {
      await tabletContext.close()
    }

    // The same sheet is usable on a phone-sized moderator screen, without clipping.
    await hostPage.setViewportSize({ width: 390, height: 844 })
    await expect(dialog).toBeVisible()
    const fits = await dialog.evaluate(element => element.scrollWidth <= element.clientWidth)
    expect(fits).toBe(true)
    const mobileChoices = await dialog.locator("fieldset button").evaluateAll(elements => elements.map(element => element.getBoundingClientRect().width))
    expect(Math.max(...mobileChoices)).toBeLessThanOrEqual(40)
    await hostPage.screenshot({ path: testInfo.outputPath("paper-entry-mobile.png"), animations: "disabled" })
    await hostPage.setViewportSize({ width: 1024, height: 900 })
    await hostPage.screenshot({ path: testInfo.outputPath("paper-entry-tablet.png"), animations: "disabled" })

    await hostPage.locator("#paper-save").click()
    await expect(hostPage.locator("#paper-overwrite-warning")).toBeVisible()
    await expect(hostPage.locator("#paper-overwrite-warning")).toContainText("Frage 1")
    await hostPage.locator("#paper-confirm-overwrite").click()
    await expect(dialog).toHaveCount(0)
    await expect(hostPage.locator('[id^="host-paper-status-"]')).toHaveText("Erfasst")
    await expect(hostPage.locator("#flash-info")).toHaveCount(0)
    await hostPage.mouse.move(0, 0)
    await hostPage.screenshot({ path: testInfo.outputPath("paper-fallback.png"), animations: "disabled" })
    await hostPage.locator('[data-test="advance-button"]').click()
    await expect(hostPage.locator("#host-round-standings")).toBeVisible()
    await hostPage.locator("#host-live-values").click()
    await expect(hostPage.locator('[id^="result-paper-"]')).toHaveCount(questionCount)
    await expect(hostPage.locator("#result-timing")).toContainText("Digitale Antwortzeit")
    expect(errors).toEqual([])
  } finally {
    for (const context of contexts) await context.close()
  }
})
