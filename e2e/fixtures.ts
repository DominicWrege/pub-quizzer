import { test as base, expect, type Page, type Browser, type BrowserContext } from "@playwright/test"

/**
 * Shared fixtures and helpers for PubQuizzer E2E tests.
 *
 * Server: tests assume `mix phx.server` is running on :4000 (the playwright
 * config's `webServer` boots it automatically with `E2E=1`, which disables
 * Phoenix live reload to avoid page-reload races). This uses the DEV database,
 * so seeded topics/questions (from `mix ecto.setup`) are available.
 *
 * Auth: E2E uses the dev-only backdoor at `/dev/login-as/:email` which sets
 * the admin session directly — no real emails are sent. The E2E user
 * (`e2e@localhost.test`) is seeded as superadmin by `mix ecto.setup`.
 */

const ADMIN_EMAIL = "e2e@localhost.test"

/** Standard timeout for engine-state transitions (topic pick, question advance, etc.). */
const ENGINE_TIMEOUT = 20_000

/**
 * Wait until a LiveView page has connected its websocket. Clicks on `phx-click`
 * elements and `phx-submit` forms are silently dropped if they happen before
 * the socket is joined, so always wait for this after a full page load.
 */
async function waitForLiveView(page: Page): Promise<void> {
  await page.waitForFunction(
    () =>
      document.querySelector("[data-phx-main]")?.classList.contains("phx-connected") ??
      false,
    { timeout: 10_000 },
  )
}

/** Log in as moderator/superadmin via the dev auth backdoor. */
async function loginAsHost(page: Page): Promise<void> {
  await page.goto(`/dev/login-as/${encodeURIComponent(ADMIN_EMAIL)}`)
  await page.waitForURL("**/admin/topics", { timeout: 10_000 })
  await waitForLiveView(page)
}

/** Create a quiz event via the admin UI and return its 4-digit join code. */
async function createEvent(page: Page, _teamCount = 4): Promise<string> {
  await page.goto("/admin/events")
  await waitForLiveView(page)
  await page.waitForSelector("#new-event-btn", { state: "visible" })
  await page.locator("#new-event-btn").click()

  await page.waitForSelector('[data-testid="event-code"]', { timeout: 10_000 })
  await waitForLiveView(page)
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
  await page.waitForSelector('span.font-mono.font-bold:has-text("' + code + '")', {
    timeout: 10_000,
  })
}

/**
 * Create N isolated browser contexts, each joining the quiz with the given code.
 * Returns the pages and contexts for cleanup.
 */
async function joinTeams(
  browser: Browser,
  code: string,
  count: number,
): Promise<{ pages: Page[]; contexts: BrowserContext[] }> {
  const contexts: BrowserContext[] = []
  const pages: Page[] = []
  for (let i = 0; i < count; i++) {
    const ctx = await browser.newContext()
    const page = await ctx.newPage()
    await joinTeam(page, code)
    contexts.push(ctx)
    pages.push(page)
  }
  return { pages, contexts }
}

/**
 * Start the quiz (click "Quiz starten") and wait for the host lobby URL.
 * The host page must be on the event show page with a enabled start button.
 */
async function startQuiz(hostPage: Page): Promise<void> {
  await expect(hostPage.locator('[phx-click="do_start"]')).toBeEnabled({ timeout: ENGINE_TIMEOUT })
  await hostPage.locator('[phx-click="do_start"]').click()
  await expect(hostPage).toHaveURL(/\/quiz\/\d{4}\/host$/, { timeout: 10_000 })
  await waitForLiveView(hostPage)
}

/**
 * Pick the first available topic on the host lobby and wait for the question phase.
 */
async function pickTopic(hostPage: Page, index = 0): Promise<void> {
  await waitForLiveView(hostPage)
  await hostPage.waitForSelector('[phx-click="choose_topic"]', { timeout: 10_000 })
  await hostPage.locator('[phx-click="choose_topic"]').nth(index).click()
  await expect(hostPage.locator("text=Frage 1 /")).toBeVisible({ timeout: ENGINE_TIMEOUT })
}

/**
 * Full quiz setup: create event, join teams, start, pick first topic.
 * Returns the code, team pages, and contexts for cleanup.
 */
async function setupQuiz(
  hostPage: Page,
  browser: Browser,
  teamCount = 2,
): Promise<{
  code: string
  pages: Page[]
  contexts: BrowserContext[]
}> {
  const code = await createEvent(hostPage, teamCount)
  const { pages, contexts } = await joinTeams(browser, code, teamCount)
  await startQuiz(hostPage)
  await pickTopic(hostPage)
  return { code, pages, contexts }
}

/**
 * Answer all questions in the current round, then reveal it.
 * `teamAChoice` / `teamBChoice` control which option index each team picks
 * (0–3). Defaults to different options so team A wins.
 *
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
    await expect(answerBtns(teamAPage)).toHaveCount(4, { timeout: ENGINE_TIMEOUT })
    await answerBtns(teamAPage).nth(teamAChoice).click()
    await answerBtns(teamBPage).nth(teamBChoice).click()
    await expect(hostPage.locator('[data-test="answered-badge"]')).toHaveText(
      /2\s*\/\s*2/,
      { timeout: ENGINE_TIMEOUT },
    )

    await hostPage.locator('[phx-click="next_question"]').click()

    const statList = hostPage.locator('[data-test="round-stat-list"]')
    try {
      await expect(statList).toBeVisible({ timeout: 5_000 })
      break
    } catch {
      // Round not revealed yet — continue to the next question.
    }
  }

  // After reveal_round the host immediately sees the stats list + winner banner
  // (no paginated reveal — all questions are shown at once in the shadow console).
  await expect(hostPage.locator('[data-test="round-stat-list"]')).toBeVisible({
    timeout: 10_000,
  })
  await expect(
    hostPage
      .locator("text=gewinnt die Runde")
      .or(hostPage.locator("text=Remis")),
  ).toBeVisible({ timeout: 10_000 })

  if (showStandings) {
    await hostPage.locator('[phx-click="show_standings"]').click()
    await expect(hostPage.locator('[id^="standing-"]')).toHaveCount(2, {
      timeout: 10_000,
    })
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

export { expect, loginAsHost, createEvent, joinTeam, joinTeams, startQuiz, pickTopic, setupQuiz, completeRound, waitForLiveView }
export type { Page, Browser, BrowserContext }
