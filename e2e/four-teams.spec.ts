import { test, expect, createEvent, joinTeams, startQuiz, pickTopic } from "./fixtures"
import type { Page, BrowserContext } from "./fixtures"

const ENGINE_TIMEOUT = 20_000
const ROUNDS = 4

test.describe("four teams", () => {
  test("host runs 4 rounds with 4 teams; standings accumulate", async ({ browser, hostPage }) => {
    test.setTimeout(180_000)

    const code = await createEvent(hostPage, 4)
    const { pages: teams, contexts } = await joinTeams(browser, code, 4)
    const [t0, t1, t2, t3] = teams
    const choices = [0, 1, 2, 3]

    await startQuiz(hostPage)

    for (let round = 0; round < ROUNDS; round++) {
      // Pick first available topic for this round
      await pickTopic(hostPage, 0)

      // Answer all questions in this round
      const answerBtns = (page: Page) => page.locator('[phx-click="select_answer"]')
      for (;;) {
        await expect(answerBtns(t0)).toHaveCount(4, { timeout: ENGINE_TIMEOUT })
        for (let i = 0; i < teams.length; i++) {
          await answerBtns(teams[i]).nth(choices[i]).click()
        }

        await expect(hostPage.locator('[data-test="answered-badge"]')).toHaveText(
          /4\s*\/\s*4/,
          { timeout: ENGINE_TIMEOUT },
        )

        await hostPage.locator('[phx-click="next_question"]').click()

        const reveal = hostPage.locator('[phx-click="next_round"]')
        try {
          await expect(reveal).toBeVisible({ timeout: 5_000 })
          break
        } catch {
          // Round not revealed yet — continue to the next question.
        }
      }

      // After reveal_round the host shows the winner next to the next-topic button
      await expect(hostPage.locator('[phx-click="next_round"]')).toBeVisible({
        timeout: 10_000,
      })

      // Ranking is host-only and open by default — all 4 teams ranked
      await expect(hostPage.locator('[id^="standing-"]')).toHaveCount(4, { timeout: 10_000 })
      // Teams never see the ranking
      await expect(t0.locator('[id^="team-standing-"]')).toHaveCount(0)

      // Advance to next round (if not the last) — pickTopic waits for the
      // topic-selection UI on the next iteration
      if (round < ROUNDS - 1) {
        await hostPage.locator('[phx-click="next_round"]').click()
      }
    }

    for (const ctx of contexts) await ctx.close()
  })
})
