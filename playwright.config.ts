import { defineConfig, devices } from "@playwright/test"

/**
 * Playwright config for PubQuizzer E2E tests.
 *
 * The Phoenix dev server (port 4001) is auto-started by `webServer` below
 * using a dedicated E2E database (E2E=1), so it never touches the dev DB
 * and can run alongside a `mix phx.server` on port 4000.
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
  // Sequential: the admin CRUD specs all mutate the same shared E2E database,
  // so running files in parallel races on the topic/question list and produces
  // flaky Ecto.NoResultsError failures. workers: 1 is the stable mode.
  workers: 1,
  reporter: [["html", { open: "never" }], ["list"]],
  timeout: 60_000,
  expect: { timeout: 10_000 },

  use: {
    baseURL: "http://localhost:4001",
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
    // Boot an isolated server on port 4001 (E2E=1 selects a dedicated
    // database that is created/migrated/seeded here) so tests never touch
    // the dev DB and can run while the dev server holds port 4000.
    command:
      "mix ecto.create && mix ecto.migrate && mix run priv/repo/seeds.exs && mix phx.server",
    url: "http://localhost:4001",
    reuseExistingServer: false,
    timeout: 180_000,
    stdout: "pipe",
    stderr: "pipe",
    // Disable Phoenix live reload for E2E: its page reloads race with form
    // submissions and cause flaky tests.
    env: { ...process.env, E2E: "1", PORT: "4001" },
  },

  globalTeardown: "e2e/teardown.ts",
})
