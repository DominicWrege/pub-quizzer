import { test, expect, createEvent, joinTeam } from "./fixtures"
import type { Page } from "@playwright/test"

/**
 * Full multi-player quiz flow: one host + two teams in separate browser
 * contexts, exercising the realtime WebSocket sync (LiveView + PubSub)
 * that ExUnit's LiveViewTest cannot verify.
 *
 * Assumes the dev DB has seeded topics with questions (from `mix ecto.setup`).
 * The event itself is created via the admin UI in the fixture below.
 */

test.describe("quiz flow", () => {
  test("host runs a full round; teams see synced state across tabs", async ({
    browser,
    hostPage,
  }) => {
    test.setTimeout(120_000)

    // --- Setup: create event with 2 team slots ---
    const code = await createEvent(hostPage, 2)
    expect(code).toMatch(/^\d{4}$/)

    // --- Two teams join in isolated browser contexts ---
    const teamAContext = await browser.newContext()
    const teamBContext = await browser.newContext()
    const teamAPage = await teamAContext.newPage()
    const teamBPage = await teamBContext.newPage()

    await joinTeam(teamAPage, code)
    await joinTeam(teamBPage, code)

    // Both teams see the "waiting" lobby state.
    await expect(teamAPage.locator("text=Warte auf den Quiz-Start")).toBeVisible()
    await expect(teamBPage.locator("text=Warte auf den Quiz-Start")).toBeVisible()

    // --- Host starts the quiz (button enables once both teams connect) ---
    const startBtn = hostPage.locator('[phx-click="do_start"]')
    await expect(startBtn).toBeEnabled({ timeout: 15_000 })
    await startBtn.click()
    // Starting redirects to the host lobby.
    await expect(hostPage).toHaveURL(/\/quiz\/\d{4}\/host$/, { timeout: 10_000 })

    // --- Host picks a topic ---
    await hostPage.waitForSelector('[phx-click="choose_topic"]', { timeout: 10_000 })
    const topicButtons = hostPage.locator('[phx-click="choose_topic"]')
    const topicCount = await topicButtons.count()
    expect(topicCount).toBeGreaterThan(0)

    const firstTopicName = (await topicButtons.first().textContent())?.trim()
    await topicButtons.first().click()

    // --- Teams see the first question (realtime sync) ---
    const teamAnswerBtns = (page: Page) => page.locator('[phx-click="select_answer"]')
    await expect(teamAnswerBtns(teamAPage)).toHaveCount(4, { timeout: 10_000 })
    await expect(teamAnswerBtns(teamBPage)).toHaveCount(4, { timeout: 10_000 })

    // --- Each team picks an answer (different options, just to exercise it) ---
    await teamAnswerBtns(teamAPage).nth(0).click()
    await teamAnswerBtns(teamBPage).nth(1).click()

    // Teams see the "answer submitted" confirmation.
    await expect(teamAPage.locator("text=Antwort abgegeben")).toBeVisible()
    await expect(teamBPage.locator("text=Antwort abgegeben")).toBeVisible()

    // Host sees both teams have answered (badge "2 / 2 geantwortet").
    await expect(hostPage.locator("text=2 / 2 Teams geantwortet")).toBeVisible({ timeout: 10_000 })

    // --- Host advances through all questions until the last one ---
    // The last question shows "Runde auflösen" instead of "Nächste Frage".
    while (await hostPage.locator('[phx-click="next_question"]').count()) {
      await hostPage.locator('[phx-click="next_question"]').click()
      // Teams see new question — answer buttons reset.
      await expect(teamAnswerBtns(teamAPage)).toHaveCount(4, { timeout: 10_000 })

      // Teams answer.
      await teamAnswerBtns(teamAPage).nth(2).click()
      await teamAnswerBtns(teamBPage).nth(0).click()
      await expect(hostPage.locator("text=2 / 2 Teams geantwortet")).toBeVisible({ timeout: 10_000 })
    }

    // --- Host reveals the round (now on last question) ---
    await hostPage.locator('[phx-click="reveal_round"]').click()
    await expect(hostPage.locator("text=Nächste Antwort anzeigen")).toBeVisible()

    // Reveal all answers.
    const revealNext = hostPage.locator('[phx-click="reveal_next_answer"]')
    while (await revealNext.count()) {
      await revealNext.first().click()
      // Brief wait for the LiveView to process + re-render.
      await hostPage.waitForTimeout(200)
    }

    // Show standings on host.
    await hostPage.locator('[phx-click="show_standings"]').click()
    await expect(hostPage.locator('[id^="standing-"]')).toHaveCount(2, { timeout: 10_000 })

    // --- Teams see the standings too (cross-tab PubSub sync) ---
    await expect(teamAPage.locator('[id^="team-standing-"]')).toHaveCount(2, { timeout: 10_000 })
    await expect(teamBPage.locator('[id^="team-standing-"]')).toHaveCount(2, { timeout: 10_000 })

    // Cleanup.
    await teamAContext.close()
    await teamBContext.close()
  })
})
