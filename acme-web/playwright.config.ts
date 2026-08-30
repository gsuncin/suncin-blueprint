import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "./tests/e2e",
  timeout: 30_000,
  expect: { timeout: 5_000 },
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  reporter: [["list"], ["html", { open: "never" }]],

  use: {
    baseURL: "http://127.0.0.1:3000",
    trace: "on-first-retry",
  },

  // No backend. Every spec mocks its own API surface with page.route, which is
  // what lets this suite run in CI with nothing but Node.
  webServer: {
    command: "npm run dev -- --host 127.0.0.1 --port 3000",
    url: "http://127.0.0.1:3000",
    reuseExistingServer: !process.env.CI,
    timeout: 60_000,
    env: { VITE_API_URL: "http://127.0.0.1:3000/api" },
  },

  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
});
