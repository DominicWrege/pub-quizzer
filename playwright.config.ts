import { defineConfig, devices } from "@playwright/test"

/**
 * Playwright config for PubQuizzer E2E tests.
 *
 * The Phoenix dev server (port 4000) is auto-started by `webServer` below.
 * `reuseExistingServer: true` means if you already have `mix phx.server`
 * running, Playwright will use it instead of booting a second instance.
 *
 * Browsers come from the Nix-managed playwright-driver (see flake.nix).
 * `PLAYWRIGHT_BROWSERS_PATH` + `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD` are set
 * by direnv; if you are not using the nix shell, run
 * `npx playwright install chromium` once.
 */
export default defineConfig({
  testDir: "./e2e",
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: 4,
  reporter: [["html", { open: "never" }], ["list"]],
  timeout: 60_000,
  expect: { timeout: 10_000 },

  use: {
    baseURL: "http://localhost:4000",
    trace: "on-first-retry",
    screenshot: "only-on-failure",
    video: "retain-on-failure",
    actionTimeout: 15_000,
  },

  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
  ],

  webServer: {
    command: "mix phx.server",
    url: "http://localhost:4000",
    reuseExistingServer: true,
    timeout: 120_000,
    stdout: "pipe",
    stderr: "pipe",
    // Disable Phoenix live reload for E2E: its page reloads race with form
    // submissions and cause flaky tests.
    env: { ...process.env, E2E: "1" },
  },

  globalTeardown: "e2e/teardown.ts",
})
