import { test, expect, createEvent, startQuiz, pickTopic, waitForLiveView } from "./fixtures"

test("two phones register one team, can both disconnect, and can rejoin after the host starts", async ({ browser, hostPage }) => {
  const errors: string[] = []
  hostPage.on("console", message => {
    if (message.type() === "error") errors.push(message.text())
  })
  hostPage.on("pageerror", error => errors.push(error.message))
  await hostPage.setViewportSize({ width: 390, height: 844 })
  const code = await createEvent(hostPage)
  const name = hostPage.locator("#event-team-cards input").first()
  expect(await name.evaluate(element => element.getBoundingClientRect().width)).toBeGreaterThan(200)
  await expect(hostPage.locator("#start-quiz")).toBeDisabled()

  const contexts = await Promise.all([
    browser.newContext({ baseURL: "http://localhost:4001" }),
    browser.newContext({ baseURL: "http://localhost:4001" }),
  ])
  try {
    const phones = await Promise.all(contexts.map(context => context.newPage()))
    for (const phone of phones) {
      phone.on("console", message => {
        if (message.type() === "error") errors.push(message.text())
      })
      phone.on("pageerror", error => errors.push(error.message))
      await phone.goto(`/quiz/join/${code}/1`)
      await waitForLiveView(phone)
      await expect(phone.locator("#team-registration")).toBeVisible()
    }

    await expect(hostPage.locator("#event-registration-summary")).toHaveText("1 von 4 Teams angemeldet")
    const card = hostPage.locator("#event-team-cards > div").first()
    await expect(card.getByText("Angemeldet", { exact: true })).toBeVisible()
    await Promise.all(phones.map(phone => phone.close()))
    await expect(card.getByText("Zurzeit offline", { exact: true })).toBeVisible()
    await expect(hostPage.locator("#start-quiz")).toBeEnabled()
    await startQuiz(hostPage)
    await pickTopic(hostPage)

    const returning = await Promise.all(contexts.map(context => context.newPage()))
    for (const phone of returning) {
      phone.on("console", message => {
        if (message.type() === "error") errors.push(message.text())
      })
      phone.on("pageerror", error => errors.push(error.message))
      await phone.goto(`/quiz/join/${code}/1`)
      await waitForLiveView(phone)
    }
    await returning[0].locator("#team-answer-0").click()
    await expect(hostPage.locator("#host-answer-count")).toHaveText("1 / 1")
    await expect(returning[1].locator("#team-answer-0")).toHaveClass(/btn-primary/)
    await returning[1].locator("#team-answer-1").click()
    for (const phone of returning) {
      await expect(phone.locator("#team-answer-1")).toHaveClass(/btn-primary/)
      await expect(phone.locator("#team-answer-0")).not.toHaveClass(/btn-primary/)
    }
    expect(errors).toEqual([])
  } finally {
    await Promise.all(contexts.map(context => context.close()))
  }
})
