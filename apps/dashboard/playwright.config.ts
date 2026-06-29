import { defineConfig, devices } from "@playwright/test";

/**
 * Visual-regression + accessibility guardrail for the PRE-UI dashboard.
 *
 * Stood up early (NIC-51 Increment 3) so every later increment is held to the
 * design-token grammar. The comprehensive cross-browser fixture matrix is NIC-65;
 * this config is the skeleton it grows into. Baselines are platform-specific
 * (currently win32) — see UI-CONSTITUTION §2.
 */
export default defineConfig({
  testDir: "./tests/visual",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: 0,
  reporter: "line",
  expect: {
    // Tolerate sub-pixel anti-aliasing noise without masking real regressions.
    toHaveScreenshot: { maxDiffPixelRatio: 0.02 }
  },
  use: {
    baseURL: "http://localhost:4173"
  },
  projects: [
    { name: "chromium", use: { ...devices["Desktop Chrome"] } },
    { name: "webkit", use: { ...devices["Desktop Safari"] } }
  ],
  webServer: {
    // Invoke the local Vite binary directly so the server starts regardless of
    // whether pnpm/corepack is on PATH inside Playwright's spawned shell.
    command: "node node_modules/vite/bin/vite.js preview --port 4173 --strictPort",
    url: "http://localhost:4173",
    reuseExistingServer: !process.env.CI,
    timeout: 120_000
  }
});
