import { test as base, expect, type Page, type Browser } from "@playwright/test"

/**
 * Shared fixtures and helpers for PubQuizzer E2E tests.
 *
 * Server: tests assume `mix phx.server` is running on :4000 (the playwright
 * config's `webServer` boots it automatically). This uses the DEV database,
 * so seeded topics/questions (from `mix ecto.setup`) are available.
 *
 * Auth: E2E uses the dev-only backdoor at `/dev/login-as/:email` which sets
 * the admin session directly — no real emails are sent. The E2E user
 * (`e2e@localhost.test`) is seeded as superadmin by `mix ecto.setup`.
 */

const ADMIN_EMAIL = "e2e@localhost.test"

/** Log in as moderator/superadmin via the dev auth backdoor. */
async function loginAsHost(page: Page): Promise<void> {
  await page.goto(`/dev/login-as/${encodeURIComponent(ADMIN_EMAIL)}`)
  await page.waitForURL("**/admin/events", { timeout: 10_000 })
}

/** Create a quiz event via the admin UI and return its 4-digit join code. */
async function createEvent(page: Page, teamCount: number): Promise<string> {
  await page.goto("/admin/events/new")
  // Wait for LiveView WebSocket to connect so our fill isn't overwritten
  // by the server re-rendering the form with default values.
  await page.waitForSelector("#event-form", { state: "attached" })
  await page.waitForLoadState("networkidle")

  const input = page.locator('input[name="team_count"]')
  await input.click({ clickCount: 3 })
  await input.fill(String(teamCount))

  await page.locator("#event-form button[type='submit']").click()

  // After save, the LiveView push_navigates to /admin/events/:id (show page).
  await page.waitForSelector('[data-testid="event-code"]', { timeout: 10_000 })
  const code = (await page.locator('[data-testid="event-code"]').textContent())?.trim()
  if (!code) throw new Error("Event code not found on show page")
  return code
}

/**
 * Join a quiz as a team. Each team must use its own browser context so the
 * session cookie (:team_id) is isolated — two tabs in one context would
 * share the same team.
 */
async function joinTeam(page: Page, code: string): Promise<void> {
  await page.goto("/")
  await page.locator("#home-quiz-code").fill(code)
  await page.locator("#home-join-btn").click()
  // Team lobby renders once the LiveView connects.
  await page.waitForSelector('span.font-mono.font-bold:has-text("' + code + '")', {
    timeout: 10_000,
  })
}

/**
 * Answer all questions in the current round, then reveal it.
 * `teamAChoice` / `teamBChoice` control which option index each team picks
 * (0–3). Defaults to different options so team A wins.
 */
/**
 * Answer all questions in the current round, then reveal them.
 * When `showStandings` is true (default), standings are shown automatically.
 * Pass `false` to inspect the winner/tie announcement before showing standings.
 */
async function completeRound(
  hostPage: Page,
  teamAPage: Page,
  teamBPage: Page,
  teamAChoice = 0,
  teamBChoice = 1,
  showStandings = true,
): Promise<void> {
  const answerBtns = (page: Page) => page.locator('[phx-click="select_answer"]')

  for (;;) {
    await expect(answerBtns(teamAPage)).toHaveCount(4, { timeout: 15_000 })
    await answerBtns(teamAPage).nth(teamAChoice).click()
    await answerBtns(teamBPage).nth(teamBChoice).click()
    await expect(hostPage.locator("text=2 / 2 Teams geantwortet")).toBeVisible({ timeout: 10_000 })

    const revealBtn = hostPage.locator('[phx-click="reveal_round"]')
    if (await revealBtn.count()) {
      await revealBtn.click()
      break
    }
    await hostPage.locator('[phx-click="next_question"]').click()
  }
  await expect(hostPage.locator("text=Nächste Antwort anzeigen")).toBeVisible()

  // Reveal all answers. reveal_round starts at index 1; each click increments by 1.
  // Exit when all answers are shown (button disappears).
  const revealNext = hostPage.locator('[phx-click="reveal_next_answer"]')
  while (await revealNext.count()) {
    await revealNext.click({ force: true })
    await hostPage.waitForTimeout(1000)
  }

  if (showStandings) {
    await hostPage.locator('[phx-click="show_standings"]').click()
    await expect(hostPage.locator('[id^="standing-"]')).toHaveCount(2, { timeout: 10_000 })
  }
}

export type Fixtures = {
  hostPage: Page
}

/**
 * Custom test fixture that provides a pre-authenticated host page.
 * Usage: `test("...", async ({ hostPage }) => { ... })`
 */
export const test = base.extend<Fixtures>({
  hostPage: async ({ browser }, use) => {
    const context = await browser.newContext()
    const page = await context.newPage()
    await loginAsHost(page)
    await use(page)
    await context.close()
  },
})

export { expect, loginAsHost, createEvent, joinTeam, completeRound }
export type { Page, Browser }
