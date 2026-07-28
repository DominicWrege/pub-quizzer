import { request } from "@playwright/test"

/**
 * Global teardown: delete all events created by E2E tests.
 * Keeps the dev DB clean across repeated test runs.
 */
async function globalTeardown() {
  const ctx = await request.newContext({ baseURL: "http://localhost:4000" })
  await ctx.delete("/dev/cleanup-events")
  await ctx.dispose()
}

export default globalTeardown
