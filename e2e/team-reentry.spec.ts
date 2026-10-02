import { test, expect, setupQuiz, waitForLiveView, type Page } from "./fixtures"

const captureErrors = (page: Page, errors: string[]) => {
  page.on("console", message => {
    if (message.type() === "error") errors.push(message.text())
  })
  page.on("pageerror", error => errors.push(error.message))
}

test("a closed team tab can return by session or QR without losing its answer", async ({ browser, hostPage }) => {
  const errors: string[] = []
  captureErrors(hostPage, errors)
  const { code, pages: [teamPage], contexts } = await setupQuiz(hostPage, browser, 2)
  const fresh = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true })

  try {
    captureErrors(teamPage, errors)
    const teamName = await teamPage.locator("h1").textContent()
    const savedUrl = teamPage.url()
    expect(new URL(savedUrl).pathname).toMatch(new RegExp(`/quiz/${code}/lobby/[a-z]{3}$`))
    await waitForLiveView(teamPage)
    await teamPage.locator('[phx-click="select_answer"][phx-value-index="1"]').click()
    await expect(hostPage.locator('[data-test="answered-badge"]')).toHaveText(/1\s*\/\s*2/)
    await teamPage.close()

    const reopened = await contexts[0].newPage()
    captureErrors(reopened, errors)
    await reopened.goto("/")
    await reopened.locator("#home-quiz-code").fill(code)
    await reopened.locator("#home-join-btn").click()
    await expect(reopened).toHaveURL(savedUrl)
    await waitForLiveView(reopened)
    await expect(reopened.locator("h1")).toHaveText(teamName!)
    await expect(reopened.locator('[phx-value-index="1"]')).toHaveClass(/btn-primary/)

    const qrPage = await fresh.newPage()
    captureErrors(qrPage, errors)
    await qrPage.goto(savedUrl)
    await waitForLiveView(qrPage)
    await expect(qrPage.locator("h1")).toHaveText(teamName!)
    await expect(qrPage.locator('[phx-value-index="1"]')).toHaveClass(/btn-primary/)
    expect(await qrPage.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)

    const teamCode = new URL(savedUrl).pathname.split("/").at(-1)!
    await fresh.clearCookies()
    await qrPage.goto(`/quiz/join/${code}/${teamCode}`)
    await expect(qrPage).toHaveURL(savedUrl)
    await waitForLiveView(qrPage)
    await expect(qrPage.locator("h1")).toHaveText(teamName!)

    await fresh.clearCookies()
    await qrPage.goto(`/quiz/join/${code}/1`)
    await waitForLiveView(qrPage)
    await expect(qrPage.locator("h1")).toHaveText(teamName!)
    await expect(qrPage.locator('[phx-value-index="1"]')).toHaveClass(/btn-primary/)

    await qrPage.goto(`/quiz/join/${code}/4`)
    await expect(qrPage.locator("#quiz-join-blocked")).toBeVisible()
    await qrPage.clock.install()
    await qrPage.clock.fastForward(5500)
    await expect(qrPage.locator("#quiz-join-blocked")).toBeVisible()
    await qrPage.locator("#join-existing-team").click()
    await waitForLiveView(qrPage)
    await qrPage.locator(`#rejoin-teams a[href='/quiz/join/${code}/${teamCode}']`).click()
    await expect(qrPage).toHaveURL(savedUrl)
    await expect(qrPage.locator('[phx-value-index="1"]')).toHaveClass(/btn-primary/)
    await expect(hostPage.locator('[data-test="answered-badge"]')).toHaveText(/1\s*\/\s*2/)
    expect(errors).toEqual([])
  } finally {
    await fresh.close()
    for (const context of contexts) await context.close()
  }
})

test("the moderator can remove a disconnected team and continue the quiz", async ({ browser, hostPage }) => {
  const errors: string[] = []
  captureErrors(hostPage, errors)
  const { code, pages: [firstPage, secondPage], contexts } = await setupQuiz(hostPage, browser, 2)

  try {
    captureErrors(firstPage, errors)
    captureErrors(secondPage, errors)
    await waitForLiveView(firstPage)
    await firstPage.locator('[phx-click="select_answer"]').first().click()
    const advance = hostPage.locator('[data-test="advance-button"]')
    await expect(advance).toBeEnabled()
    await secondPage.close()

    await hostPage.locator("#host-teams summary").click()
    const removedRow = hostPage.locator("#host-team-list > li").last()
    await expect(removedRow.locator('[data-test="team-connection"]')).toHaveText("Offline")
    await removedRow.getByRole("button", { name: /entfernen/ }).click()
    await hostPage.locator("#remove-team-modal-cancel").click()
    await expect(advance).toBeEnabled()
    await removedRow.getByRole("button", { name: /entfernen/ }).click()
    await hostPage.locator("#remove-team-modal-confirm").click()

    await expect(hostPage.locator("#host-team-list > li")).toHaveCount(1)
    await expect(hostPage.locator('[data-test="answered-badge"]')).toHaveText(/1\s*\/\s*1/)
    await expect(advance).toBeEnabled()
    await expect(hostPage.locator('[phx-click="ask_remove_team"]')).toHaveCount(0)
    await expect(hostPage.locator('[id^="host-last-team-"]')).toContainText("Ein Team muss bleiben")

    const removedPage = await contexts[1].newPage()
    captureErrors(removedPage, errors)
    await removedPage.goto(`/quiz/join/${code}`)
    await expect(removedPage.locator("#quiz-join-blocked")).toBeVisible()
    await removedPage.goto(`/quiz/join/${code}/2`)
    await expect(removedPage).toHaveURL("/")

    await advance.click()
    await expect(firstPage.locator("#team-question-progress")).toHaveText(/Frage 2/)
    expect(errors).toEqual([])
  } finally {
    for (const context of contexts) await context.close()
  }
})
