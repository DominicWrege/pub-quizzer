import { test, expect, createEvent, joinTeams } from "./fixtures"

test("event edit action shares the iPad header row but stacks on phones", async ({ hostPage }, testInfo) => {
  const errors: string[] = []
  hostPage.on("console", message => { if (message.type() === "error") errors.push(message.text()) })
  hostPage.on("pageerror", error => errors.push(error.message))
  await createEvent(hostPage)

  for (const viewport of [
    { width: 390, height: 844 },
    { width: 768, height: 1024 },
    { width: 820, height: 1180 },
    { width: 1024, height: 768 },
    { width: 1180, height: 820 },
  ]) {
    await hostPage.setViewportSize(viewport)
    const edit = hostPage.locator('[phx-click="open_edit_name"]')
    const geometry = await edit.evaluate(element => {
      const action = element.getBoundingClientRect()
      const header = element.closest("header")!
      const title = header.querySelector("h1")!.getBoundingClientRect()
      const back = header.querySelector("a")!.getBoundingClientRect()
      return {
        actionTop: action.top, actionBottom: action.bottom,
        titleTop: title.top, titleBottom: title.bottom,
        backTop: back.top, backBottom: back.bottom,
        pageWidth: document.documentElement.scrollWidth, viewportWidth: innerWidth,
      }
    })

    if (viewport.width < 768) {
      expect(geometry.actionTop).toBeGreaterThanOrEqual(geometry.titleBottom)
    } else {
      expect(geometry.actionTop).toBeLessThan(geometry.titleBottom)
      expect(geometry.actionBottom).toBeGreaterThan(geometry.titleTop)
      expect(geometry.actionTop).toBeLessThan(geometry.backBottom)
      expect(geometry.actionBottom).toBeGreaterThan(geometry.backTop)
    }
    expect(geometry.pageWidth).toBeLessThanOrEqual(geometry.viewportWidth)
    if (viewport.width === 820) {
      await hostPage.screenshot({ path: testInfo.outputPath("event-ipad.png") })
      await edit.click()
      await expect(hostPage.locator("#event-name-dialog")).toBeVisible()
      await hostPage.locator("#event-name-dialog").getByRole("button", { name: "Schließen" }).click()
      await expect(hostPage.locator("#event-name-dialog")).toHaveCount(0)
    }
  }

  expect(errors).toEqual([])
})

test("registration summary sits close to the invite card", async ({ hostPage }) => {
  await createEvent(hostPage)

  for (const width of [390, 768, 820, 1180]) {
    await hostPage.setViewportSize({ width, height: 1180 })
    const gap = await hostPage.locator("#event-registration-summary").evaluate(element => {
      const section = element.closest("section")!.getBoundingClientRect()
      const card = document.querySelector("#copy-join-link")!.closest(".card")!.getBoundingClientRect()
      return section.top - card.bottom
    })
    expect(gap).toBeGreaterThan(0)
    expect(gap).toBeLessThanOrEqual(16)
  }
})

test("invite card sits close below the event header", async ({ hostPage }, testInfo) => {
  const errors: string[] = []
  hostPage.on("console", message => { if (message.type() === "error") errors.push(message.text()) })
  hostPage.on("pageerror", error => errors.push(error.message))
  await createEvent(hostPage)

  for (const width of [390, 768, 820, 1180, 1380]) {
    await hostPage.setViewportSize({ width, height: 1180 })
    const gap = await hostPage.locator("#copy-join-link").evaluate(element => {
      const card = element.closest(".card")!.getBoundingClientRect()
      const edit = document.querySelector('[phx-click="open_edit_name"]')!
      const back = edit.closest("header")!.querySelector("a")!
      return card.top - Math.max(edit.getBoundingClientRect().bottom, back.getBoundingClientRect().bottom)
    })
    expect(gap).toBeGreaterThanOrEqual(8)
    expect(gap).toBeLessThanOrEqual(26)
    if (width === 820 || width === 1380) {
      await hostPage.screenshot({ path: testInfo.outputPath(`event-header-gap-${width}.png`) })
    }
  }

  expect(errors).toEqual([])
})

test("invite card has compact inner horizontal padding", async ({ hostPage }) => {
  await createEvent(hostPage)

  for (const width of [390, 768, 820, 1180, 1380]) {
    await hostPage.setViewportSize({ width, height: 1180 })
    const padding = await hostPage.locator("#copy-join-link").evaluate(element => {
      const styles = getComputedStyle(element.closest(".card-body")!)
      return [parseFloat(styles.paddingLeft), parseFloat(styles.paddingRight)]
    })
    for (const value of padding) {
      expect(value).toBeGreaterThanOrEqual(8)
      expect(value).toBeLessThanOrEqual(16)
    }
    await expect(hostPage.locator("#copy-join-link")).toBeVisible()
    await expect(hostPage.getByRole("link", { name: "QR-Karten", exact: true })).toBeVisible()
  }
})

test("invite card has compact vertical padding", async ({ hostPage }) => {
  await createEvent(hostPage)

  for (const width of [390, 768, 820, 1180]) {
    await hostPage.setViewportSize({ width, height: 1180 })
    const padding = await hostPage.locator("#copy-join-link").evaluate(element => {
      const card = element.closest(".card-body")!
      const styles = getComputedStyle(card)
      return [parseFloat(styles.paddingTop), parseFloat(styles.paddingBottom)]
    })
    for (const value of padding) {
      expect(value).toBeGreaterThanOrEqual(6)
      expect(value).toBeLessThanOrEqual(12)
    }
    await expect(hostPage.locator("#copy-join-link")).toBeVisible()
    await expect(hostPage.getByRole("link", { name: "QR-Karten", exact: true })).toBeVisible()
  }
})

test("team names, statuses and actions share a compact non-editable row", async ({ browser, hostPage }, testInfo) => {
  const errors: string[] = []
  hostPage.on("console", message => { if (message.type() === "error") errors.push(message.text()) })
  hostPage.on("pageerror", error => errors.push(error.message))
  await hostPage.setViewportSize({ width: 820, height: 1180 })
  const code = await createEvent(hostPage)
  const cards = hostPage.locator("#event-team-cards")
  await expect(cards.getByRole("textbox")).toHaveCount(0)
  const { contexts } = await joinTeams(browser, code, 1)

  try {
    await expect(cards.getByText("Angemeldet", { exact: true })).toBeVisible()
    for (const width of [320, 390, 768, 820]) {
      await hostPage.setViewportSize({ width, height: 1180 })
      for (const card of await cards.locator(":scope > div").all()) {
        const geometry = await card.evaluate(element => {
          const row = element.getBoundingClientRect()
          const name = element.firstElementChild!.getBoundingClientRect()
          const status = element.querySelector(".badge")!.getBoundingClientRect()
          const remove = element.querySelector('[phx-click="remove_team"]')!.getBoundingClientRect()
          return {
            height: row.height, nameTop: name.top, nameBottom: name.bottom,
            nameRight: name.right, statusLeft: status.left, statusTop: status.top,
            statusBottom: status.bottom, removeTop: remove.top, removeBottom: remove.bottom,
            removeRight: remove.right, rowRight: row.right,
          }
        })
        expect(geometry.height).toBeLessThanOrEqual(82)
        expect(geometry.nameTop).toBeLessThan(geometry.statusBottom)
        expect(geometry.nameBottom).toBeGreaterThan(geometry.statusTop)
        expect(geometry.nameTop).toBeLessThan(geometry.removeBottom)
        expect(geometry.nameBottom).toBeGreaterThan(geometry.removeTop)
        expect(geometry.nameRight).toBeLessThanOrEqual(geometry.statusLeft)
        expect(geometry.removeRight).toBeLessThan(geometry.rowRight)
      }
      expect(await hostPage.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
      if (width === 820) await hostPage.screenshot({ path: testInfo.outputPath("compact-team-rows-ipad.png") })
    }
    expect(errors).toEqual([])
  } finally {
    for (const context of contexts) await context.close()
  }
})
