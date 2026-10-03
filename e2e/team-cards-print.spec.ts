import { test, expect, createEvent, waitForLiveView } from "./fixtures"
import { execFileSync } from "node:child_process"
import { readFileSync } from "node:fs"

function verifyPrintedSheets(path: string, teams: number): void {
  const info = execFileSync("pdfinfo", ["-f", "1", "-l", String(teams), path], { encoding: "utf8" })
  const sizes = [...info.matchAll(/Page\s+\d+ size:\s+([\d.]+) x ([\d.]+) pts/g)]
  expect(sizes).toHaveLength(teams)
  for (const [, width, height] of sizes) {
    expect(Math.abs(Number(width) - 595.28)).toBeLessThan(1)
    expect(Math.abs(Number(height) - 841.89)).toBeLessThan(1)
  }
  for (let page = 1; page <= teams; page++) {
    const prefix = `${path}-page-${page}`
    execFileSync("pdftoppm", ["-f", String(page), "-l", String(page), "-singlefile", "-r", "24", path, prefix])
    const ppm = readFileSync(`${prefix}.ppm`)
    const header = /^P6\s+(\d+)\s+(\d+)\s+255\s/.exec(ppm.toString("latin1"))!
    expect(header).not.toBeNull()
    const width = Number(header[1])
    const height = Number(header[2])
    const pixels = ppm.subarray(header[0].length)
    let coloredPixels = 0
    let darkPixels = 0
    let edgeViolations = 0
    let firstDarkRow = height
    let lastDarkRow = -1
    for (let i = 0; i < pixels.length; i += 3) {
      const r = pixels[i]
      const g = pixels[i + 1]
      const b = pixels[i + 2]
      if (Math.max(r, g, b) - Math.min(r, g, b) > 1) coloredPixels++
      if (r < 100 && g < 100 && b < 100) {
        darkPixels++
        const y = Math.floor(i / 3 / width)
        if (y < firstDarkRow) firstDarkRow = y
        if (y > lastDarkRow) lastDarkRow = y
      }
      const x = (i / 3) % width
      const y = Math.floor(i / 3 / width)
      if ((x < 2 || x >= width - 2 || y < 2 || y >= height - 2) && (r !== 255 || g !== 255 || b !== 255)) {
        edgeViolations++
      }
    }
    expect(edgeViolations, `page ${page} paper edge must be white`).toBe(0)
    expect(coloredPixels, `page ${page} must be entirely neutral black/white`).toBe(0)
    expect(darkPixels, `page ${page} must contain printed content`).toBeGreaterThan(50)
    // Content must sit inside the sheet with visible white margins: never
    // clipped at an edge (the old layout cut the last card off mid-page).
    expect(firstDarkRow, `page ${page} content must start below the top edge`).toBeGreaterThan(height * 0.05)
    expect(lastDarkRow, `page ${page} content must end above the bottom edge`).toBeLessThan(height * 0.95)
    // One centered card per sheet: roughly balanced white margins above/below.
    expect(Math.abs(firstDarkRow - (height - lastDarkRow)), `page ${page} content must be vertically centered`).toBeLessThan(height * 0.15)
    const text = execFileSync("pdftotext", ["-f", String(page), "-l", String(page), path, "-"], { encoding: "utf8" }).replace(/\s+/g, " ")
    expect(text).toContain(`Team ${page}`)
    expect(text).toContain("QR-Code scannen oder Link im Browser eingeben")
  }
}

// A4 in CSS pixels (1px = 1/96in) — the page box the cards must never overflow.
const MM_TO_PX = 96 / 25.4
const A4_HEIGHT_PX = 297 * MM_TO_PX

/** Count pages in a Playwright PDF without pulling in a PDF-parsing dependency. */
function pdfPageCount(pdf: Buffer): number {
  // Chromium writes one `/Type /Page` object per page; the tree root is `/Type /Pages`.
  return (pdf.toString("latin1").match(/\/Type\s*\/Page[^s]/g) ?? []).length
}

test.describe("team-card print layout", () => {
  // Generating and pixel-checking six PDFs per team count is heavy; give the
  // suite room so a slow CI machine cannot turn it into a false failure.
  test.setTimeout(300_000)

  for (const teamCount of [1, 4, 12]) {
    test(`${teamCount} teams produce exactly ${teamCount} PDF pages with CSS page sizing`, async ({ hostPage }) => {
      const errors: string[] = []
      hostPage.on("console", message => { if (message.type() === "error") errors.push(message.text()) })
      hostPage.on("pageerror", error => errors.push(error.message))
      await createEvent(hostPage)
      await hostPage.setViewportSize({ width: 390, height: 844 })
      for (let count = 4; count > teamCount; count--) {
        await hostPage.locator('button[id^="remove-team-"]').last().click()
        await expect(hostPage.locator('button[id^="remove-team-"]')).toHaveCount(count - 1)
      }
      for (let count = 4; count < teamCount; count++) {
        await hostPage.locator('[phx-click="add_slot"]').click()
        await expect(hostPage.locator('button[id^="remove-team-"]')).toHaveCount(count + 1)
      }
      await hostPage.getByRole("link", { name: "QR-Karten" }).click()
      await waitForLiveView(hostPage)
      await expect(hostPage.locator('[data-test="team-card"]')).toHaveCount(teamCount)
      await hostPage.evaluate(() => {
        window.print = () => { document.documentElement.dataset.printRequested = "true" }
      })
      await hostPage.locator("#print-team-cards").click()
      await expect(hostPage.locator("html")).toHaveAttribute("data-print-requested", "true")
      for (const scale of [1, 1.25, 1.5]) {
        for (const preferCSSPageSize of [true, false]) {
          const pdf = await hostPage.pdf({
            path: test.info().outputPath(`teams-${teamCount}-css-${preferCSSPageSize}-scale-${scale}.pdf`),
            format: "A4", preferCSSPageSize, scale, printBackground: true,
          })
          expect(pdfPageCount(pdf)).toBe(teamCount)
          verifyPrintedSheets(test.info().outputPath(`teams-${teamCount}-css-${preferCSSPageSize}-scale-${scale}.pdf`), teamCount)
        }
      }
      expect(errors).toEqual([])
    })
  }
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
