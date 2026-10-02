import { test, expect, createEvent } from "./fixtures"

// A4 in CSS pixels (1px = 1/96in) — the page box the cards must never overflow.
const MM_TO_PX = 96 / 25.4
const A4_HEIGHT_PX = 297 * MM_TO_PX

/** Count pages in a Playwright PDF without pulling in a PDF-parsing dependency. */
function pdfPageCount(pdf: Buffer): number {
  // Chromium writes one `/Type /Page` object per page; the tree root is `/Type /Pages`.
  return (pdf.toString("latin1").match(/\/Type\s*\/Page[^s]/g) ?? []).length
}

test.describe("team-card print layout", () => {
  test("one QR card per page — no blank pages, small centered QR", async ({ hostPage }) => {
    await createEvent(hostPage) // new event, 4 team slots
    const eventId = new URL(hostPage.url()).pathname.split("/").filter(Boolean).pop()!
    await hostPage.goto(`/admin/events/${eventId}/team-cards`)

    const cards = hostPage.locator('[data-test="team-card"]')
    await expect(cards.first()).toBeVisible({ timeout: 10_000 })
    const cardCount = await cards.count()
    expect(cardCount).toBeGreaterThan(0)

    await hostPage.emulateMedia({ media: "print" })

    // Root-cause guard: a card must never be tall enough to fill/overflow the
    // sheet. The old layout forced `min-height: 296mm`, so real print-dialog
    // margins pushed an empty page out after every card (10 teams -> 20 pages).
    const cardHeights = await cards.evaluateAll((els) =>
      els.map((el) => el.getBoundingClientRect().height),
    )
    for (const height of cardHeights) {
      expect(height).toBeLessThan(A4_HEIGHT_PX - 30 * MM_TO_PX)
    }

    // QR must stay modest (it regressed to ~90mm once); 65mm is the ceiling.
    const qrWidth = await hostPage
      .locator(".team-card .team-card-qr svg")
      .first()
      .evaluate((el) => el.getBoundingClientRect().width)
    expect(qrWidth).toBeLessThanOrEqual(65 * MM_TO_PX)

    // Exactly one page per card under A4, under explicit print margins, and
    // under Letter (a shorter sheet).
    const pdfs = await Promise.all([
      hostPage.pdf({ format: "A4", printBackground: true }),
      hostPage.pdf({
        format: "A4",
        printBackground: true,
        margin: { top: "10mm", bottom: "10mm", left: "10mm", right: "10mm" },
      }),
      hostPage.pdf({ format: "Letter", printBackground: true }),
    ])
    for (const pdf of pdfs) {
      expect(pdfPageCount(pdf)).toBe(cardCount)
    }
  })
})
