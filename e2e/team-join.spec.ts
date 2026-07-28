import { test, expect, createEvent, joinTeam, startQuiz } from "./fixtures"

test.describe("team join", () => {
  test("joining an already-started quiz shows an error", async ({ browser, hostPage }) => {
    test.setTimeout(60_000)

    const code = await createEvent(hostPage, 2)
    const ctxA = await browser.newContext()
    const pageA = await ctxA.newPage()
    await joinTeam(pageA, code)
    await startQuiz(hostPage)

    // Now try to join as a new team — quiz has started
    const ctxB = await browser.newContext()
    const pageB = await ctxB.newPage()
    await pageB.goto("/")
    await pageB.locator("#home-quiz-code").fill(code)
    await pageB.locator("#home-join-btn").click()

    await expect(pageB.locator(".alert-error")).toBeVisible({ timeout: 10_000 })
    await expect(pageB).toHaveURL("/")

    await ctxA.close()
    await ctxB.close()
  })

  test("joining a full quiz shows an error", async ({ browser, hostPage }) => {
    test.setTimeout(60_000)

    const code = await createEvent(hostPage, 2)

    // Fill both slots
    const ctxA = await browser.newContext()
    const ctxB = await browser.newContext()
    const pageA = await ctxA.newPage()
    const pageB = await ctxB.newPage()
    await joinTeam(pageA, code)
    await joinTeam(pageB, code)

    // Try a third team
    const ctxC = await browser.newContext()
    const pageC = await ctxC.newPage()
    await pageC.goto("/")
    await pageC.locator("#home-quiz-code").fill(code)
    await pageC.locator("#home-join-btn").click()

    await expect(pageC.locator(".alert-error")).toBeVisible({ timeout: 10_000 })
    await expect(pageC).toHaveURL("/")

    await ctxA.close()
    await ctxB.close()
    await ctxC.close()
  })

  test("team can reclaim its slot by rejoining with the same session", async ({ browser, hostPage }) => {
    test.setTimeout(60_000)

    const code = await createEvent(hostPage, 2)

    const ctxA = await browser.newContext()
    const pageA = await ctxA.newPage()
    await joinTeam(pageA, code)

    // Navigate back to home and rejoin with same context (same session cookie)
    await pageA.goto("/")
    await pageA.locator("#home-quiz-code").fill(code)
    await pageA.locator("#home-join-btn").click()

    // Should end up back in the team lobby (reclaim, not "full" error)
    await expect(pageA).toHaveURL(new RegExp(`/quiz/${code}/lobby`), { timeout: 10_000 })

    await ctxA.close()
  })

  test("direct URL join via /quiz/join/:code works", async ({ browser }) => {
    test.setTimeout(60_000)

    const ctx = await browser.newContext()
    const page = await ctx.newPage()

    // Use a code that won't exist
    await page.goto("/quiz/join/0000")
    await expect(page.locator(".alert-error")).toBeVisible({ timeout: 10_000 })
    await expect(page).toHaveURL("/")

    await ctx.close()
  })
})
