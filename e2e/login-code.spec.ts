import { test, expect } from "@playwright/test"

test.use({ video: "off" })

test("a completed code cannot submit twice before navigation", async ({ page }) => {
  await page.goto("/admin/login")
  await page.locator("#admin-login-form input[name='email']").fill("e2e@localhost.test")
  await page.locator("#admin-login-form button[type='submit']").click()
  await expect(page.locator("#admin-code-form")).toBeVisible()

  const submissions = await page.locator("#admin-code-form").evaluate(form => {
    const el = form as HTMLFormElement
    let submitted = 0
    el.addEventListener("submit", event => {
      event.preventDefault()
      submitted++
    })
    const segments = el.querySelectorAll<HTMLInputElement>("input[data-code-seg]")
    "ABC234".split("").forEach((char, i) => {
      if (segments[i]) segments[i].value = char
    })
    el.querySelector<HTMLInputElement>("input[data-code-seg]")?.dispatchEvent(
      new Event("input", { bubbles: true })
    )
    return submitted
  })

  expect(submissions).toBe(1)
})

test("a pasted code with separators signs in without another submit", async ({ page, context }) => {
  const errors: string[] = []
  page.on("pageerror", error => errors.push(error.message))
  page.on("console", message => {
    if (message.type() === "error") errors.push(message.text())
  })
  await page.goto("/admin/login")
  await page.locator("#admin-login-form input[name='email']").fill("e2e@localhost.test")
  await page.locator("#admin-login-form button[type='submit']").click()
  await expect(page.locator("#admin-code-form")).toBeVisible()

  const mailbox = await context.newPage()
  await mailbox.goto("/dev/mailbox")
  const code = (await mailbox.locator("body").innerText()).match(/([A-HJ-NP-Z2-9]{6}) – dein Quiz for a better life Login-Code/)?.[1]
  expect(code).toBeTruthy()

  const characters = code!.split("")
  for (let i = 0; i < characters.length; i++) {
    await page.locator(`#admin-code-seg-${i}`).fill(characters[i])
  }
  await expect(page).toHaveURL(/\/admin\/topics$/, { timeout: 10_000 })
  await expect(page.locator("#code-error")).toHaveCount(0)
  expect(errors).toEqual([])
  await mailbox.close()
})
