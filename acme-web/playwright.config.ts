import { defineConfig, devices } from "@playwright/test";

// Fixed by default, and overridable because reuseExistingServer tests whatever
// answers on the port: a parallel worktree, or another project's container.
const port = process.env.E2E_PORT ?? "3000";
const origin = `http://127.0.0.1:${port}`;

// On CI the suite runs against a production build served by `vite preview`
// (specs 488a9ee4, D-2). The dev server compiles every module on its first
// request, and with one worker that made test:e2e 17 of the web job's ~28
// minutes. The build goes to dist/e2e so the dist/ that `lhci autorun` audits
// next keeps the bundle `npm run build` made. E2E_PREVIEW=1 runs the CI mode on
// a laptop; without it a laptop keeps the dev server and its hot reload.
const preview = !!process.env.CI || process.env.E2E_PREVIEW === "1";
const previewDir = "dist/e2e";

export default defineConfig({
  testDir: "./tests/e2e",
  timeout: 30_000,
  expect: { timeout: 5_000 },
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  // Playwright's CI default is half the cores, one worker on a hosted runner.
  // Every spec mocks its API, so the only server is a static one; two is the
  // runner's core count. Locally the default stands.
  workers: process.env.CI ? 2 : undefined,
  reporter: [["list"], ["html", { open: "never" }]],

  use: {
    baseURL: origin,
    trace: "on-first-retry",
  },

  // No backend. Every spec mocks its own API surface with page.route, which is
  // what lets this suite run in CI with nothing but Node.
  webServer: {
    command: preview
      ? `npx vite build --outDir ${previewDir} --emptyOutDir && npx vite preview --outDir ${previewDir} --host 127.0.0.1 --port ${port} --strictPort`
      : `npm run dev -- --host 127.0.0.1 --port ${port}`,
    url: origin,
    reuseExistingServer: !process.env.CI,
    // The build runs inside this timeout in preview mode.
    timeout: preview ? 180_000 : 60_000,
    // Read by `vite build` as well as by the dev server, so the preview bundle
    // calls the origin every spec's page.route mocks.
    env: { VITE_API_URL: `${origin}/api` },
  },

  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
});
