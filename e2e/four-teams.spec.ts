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

        await expect(hostPage.locator("text=4 / 4 Teams geantwortet")).toBeVisible({
          timeout: ENGINE_TIMEOUT,
        })

        const revealBtn = hostPage.locator('[phx-click="reveal_round"]')
        if (await revealBtn.count()) {
          await revealBtn.click()
          break
        }
        await hostPage.locator('[phx-click="next_question"]').click()
      }

      // Reveal answers
      await expect(hostPage.locator("text=Nächste Antwort anzeigen")).toBeVisible()
      const revealNext = hostPage.locator('[phx-click="reveal_next_answer"]')
      while (await revealNext.count()) {
        await revealNext.click({ force: true })
        await hostPage.waitForTimeout(1000)
      }

      // Show standings — all 4 teams ranked
      await hostPage.locator('[phx-click="show_standings"]').click()
      await expect(hostPage.locator('[id^="standing-"]')).toHaveCount(4, { timeout: 10_000 })
      await expect(t0.locator('[id^="team-standing-"]')).toHaveCount(4, { timeout: 10_000 })

      // Advance to next round (if not the last)
      if (round < ROUNDS - 1) {
        await hostPage.waitForTimeout(2000)
        await hostPage.locator('[phx-click="next_round"]').click()
      }
    }

    for (const ctx of contexts) await ctx.close()
  })
})
