import { test, expect, createEvent, startQuiz, pickTopic } from "./fixtures"

test("a phone requesting a desktop viewport stays readable through joining and quiz start", async ({ browser, hostPage }) => {
  const errors: string[] = []
  hostPage.on("console", message => {
    if (message.type() === "error") errors.push(message.text())
  })
  hostPage.on("pageerror", error => errors.push(error.message))
  const code = await createEvent(hostPage)
  // Desktop mode keeps the phone screen/touch input but exposes a 980px layout
  // viewport and a desktop UA. Chromium emulation cannot toggle Samsung's setting.
  const context = await browser.newContext({
    baseURL: "http://localhost:4001",
    viewport: { width: 980, height: 1800 },
    screen: { width: 390, height: 844 },
    hasTouch: true,
    deviceScaleFactor: 3,
  })
  const phone = await context.newPage()
  phone.on("console", message => {
    if (message.type() === "error") errors.push(message.text())
  })
  phone.on("pageerror", error => errors.push(error.message))

  try {
    await phone.goto("/")
    await expect(phone.locator("header button[aria-label='Menü']")).toBeVisible()
    await expect.poll(() => phone.evaluate(() => {
      const input = document.querySelector("#home-quiz-code")!
      return input.getBoundingClientRect().height * screen.width / innerWidth
    })).toBeGreaterThanOrEqual(44)
    expect(await phone.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)).toBe(true)

    await phone.goto(`/quiz/join/${code}/1`)
    await expect(phone.locator("#team-registration")).toBeVisible()
    await expect.poll(() => phone.evaluate(() => {
      const registration = document.querySelector("#team-registration")!
      const scale = Number.parseFloat(getComputedStyle(document.documentElement).zoom) || 1
      return Number.parseFloat(getComputedStyle(registration).fontSize) * scale * screen.width / innerWidth
    })).toBeGreaterThanOrEqual(16)

    await expect(hostPage.locator("#event-registration-summary")).toHaveText("1 von 4 Teams angemeldet")
    await startQuiz(hostPage)
    await expect(phone.getByText("Wartet, bis das Thema gewählt ist.")).toBeVisible()
    await pickTopic(hostPage)
    const answer = phone.locator("button[phx-click='select_answer']").first()
    await expect(answer).toBeVisible()
    expect(await answer.evaluate(element => element.getBoundingClientRect().height * screen.width / innerWidth)).toBeGreaterThanOrEqual(44)
    await answer.click()
    await expect(answer).toHaveClass(/btn-primary/)
    expect(await phone.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)).toBe(true)
    await phone.emulateMedia({ media: "print" })
    expect(await phone.evaluate(() => Number.parseFloat(getComputedStyle(document.documentElement).zoom))).toBe(1)
    expect(errors).toEqual([])
  } finally {
    await context.close()
  }
})

for (const device of [
  { name: "ordinary mobile", width: 390, height: 844, touch: true },
  { name: "desktop", width: 1280, height: 900, touch: false },
  { name: "tablet", width: 820, height: 1180, touch: true },
  { name: "non-touch small screen", width: 980, height: 1800, touch: false, screenWidth: 390, screenHeight: 844 },
]) {
  test(`${device.name} keeps its normal viewport sizing`, async ({ browser }) => {
    const context = await browser.newContext({
      baseURL: "http://localhost:4001",
      viewport: { width: device.width, height: device.height },
      screen: { width: device.screenWidth ?? device.width, height: device.screenHeight ?? device.height },
      hasTouch: device.touch,
    })
    const page = await context.newPage()
    const errors: string[] = []
    page.on("console", message => {
      if (message.type() === "error") errors.push(message.text())
    })
    page.on("pageerror", error => errors.push(error.message))
    try {
      await page.goto("/")
      await expect(page.locator("#home-quiz-code")).toBeVisible()
      expect(await page.evaluate(() => Number.parseFloat(getComputedStyle(document.documentElement).zoom) || 1)).toBe(1)
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)).toBe(true)
      expect(errors).toEqual([])
    } finally {
      await context.close()
    }
  })
}
