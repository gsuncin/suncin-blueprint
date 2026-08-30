const { existsSync } = require("node:fs");

/** Use a system Chrome if there is one, otherwise Playwright's.
 *
 * CI installs Playwright's chromium and has no system Chrome; a developer's
 * machine usually has the reverse. Without this the config only works in one
 * of the two places.
 */
function resolveChrome() {
  if (process.env.CHROME_PATH) return process.env.CHROME_PATH;

  const candidates = [
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/usr/bin/google-chrome",
    "/usr/bin/chromium",
  ];
  const found = candidates.find((path) => existsSync(path));
  if (found) return found;

  try {
    return require("playwright-core").chromium.executablePath();
  } catch {
    return undefined;
  }
}

module.exports = {
  ci: {
    collect: {
      // The landing page only. The authenticated app needs a session, and its
      // performance budget is a different conversation from a page whose whole
      // job is a first impression.
      url: ["http://127.0.0.1:4173/landing.html"],
      // Two flags, both load-bearing, both of which present as the same
      // unhelpful "Chrome prevented page load with an interstitial":
      //
      //   --strictPort   Without it Vite silently moves to the next free port
      //                  when 4173 is taken, while Lighthouse still points at
      //                  4173 and audits whatever else is there.
      //   --host         Vite preview binds [::1] only. Lighthouse navigates to
      //                  127.0.0.1, which is a DIFFERENT address on a
      //                  dual-stack machine, and the connection is refused.
      startServerCommand: "npx vite preview --port 4173 --strictPort --host 127.0.0.1",
      startServerReadyPattern: "Local:",
      numberOfRuns: 3,
      settings: { chromePath: resolveChrome() },
    },
    assert: {
      assertions: {
        "categories:performance": ["error", { minScore: 0.9 }],
        "categories:accessibility": ["error", { minScore: 0.95 }],
        "categories:best-practices": ["error", { minScore: 0.9 }],
        "categories:seo": ["error", { minScore: 0.9 }],
      },
    },
    upload: { target: "filesystem", outputDir: ".lighthouseci" },
  },
};
