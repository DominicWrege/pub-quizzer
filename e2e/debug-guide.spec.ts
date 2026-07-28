import { test, loginAsHost } from "./fixtures"

test("debug guide screenshot", async ({ browser }) => {
  const ctx = await browser.newContext()
  const page = await ctx.newPage()
  await loginAsHost(page)

  await page.waitForSelector(".driver-popover-title", { timeout: 10_000 })

  // Dump computed styles
  const info = await page.evaluate(() => {
    const pop = document.querySelector(".driver-popover") as HTMLElement
    const footer = document.querySelector(".driver-popover-footer") as HTMLElement
    const navBtns = document.querySelector(".driver-popover-navigation-btns") as HTMLElement
    const cs = getComputedStyle
    return {
      popover: {
        width: pop?.offsetWidth,
        minWidth: cs(pop).minWidth,
        maxWidth: cs(pop).maxWidth,
      },
      footer: {
        gap: cs(footer).gap,
        display: cs(footer).display,
        children: Array.from(footer?.children ?? []).map(c => c.tagName + "." + c.className + " w=" + (c as HTMLElement).offsetWidth),
      },
      navBtns: {
        gap: cs(navBtns).gap,
        display: cs(navBtns).display,
      },
    }
  })
  console.log("DEBUG", JSON.stringify(info, null, 2))

  await page.screenshot({ path: "test-results/guide-debug.png" })
  await ctx.close()
})
