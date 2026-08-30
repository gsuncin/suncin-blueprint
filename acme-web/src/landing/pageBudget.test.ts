import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import path from "node:path";

import { describe, expect, it } from "vitest";

import { LANDING_JS_BUDGET_BYTES } from "@/landing/pageBudget";

const ROOT = path.resolve(import.meta.dirname, "../..");
const DIST = path.join(ROOT, "dist");

/** Follow landing.html's module graph and total the JavaScript it pulls in.
 *
 * Reads the real build output rather than estimating: the number that matters
 * is what a browser downloads, and only the bundler knows what got shared with
 * the app entry and what did not.
 */
function landingBundleBytes(): number {
  if (!existsSync(path.join(DIST, "landing.html"))) {
    execFileSync("npx", ["vite", "build"], { cwd: ROOT, stdio: "pipe" });
  }

  const html = readFileSync(path.join(DIST, "landing.html"), "utf8");
  const entry = html.match(/src="\/(assets\/[^"]+\.js)"/)?.[1];
  if (!entry) throw new Error("No module script found in dist/landing.html");

  const assetsDir = path.join(DIST, "assets");
  const seen = new Set<string>();
  const queue = [path.basename(entry)];
  let total = 0;

  const available = readdirSync(assetsDir);

  while (queue.length) {
    const file = queue.pop()!;
    if (seen.has(file)) continue;
    seen.add(file);

    const full = path.join(assetsDir, file);
    if (!existsSync(full)) continue;

    total += statSync(full).size;

    // Static imports appear as relative specifiers in the emitted chunk.
    const source = readFileSync(full, "utf8");
    for (const match of source.matchAll(/["'`]\.\/([\w.-]+\.js)["'`]/g)) {
      if (available.includes(match[1])) queue.push(match[1]);
    }
  }

  return total;
}

describe("landing page budget", () => {
  it("stays inside its byte budget", () => {
    const bytes = landingBundleBytes();

    // Reported either way: a build that comes in far under budget is worth
    // knowing about too, because it means the budget can be tightened.
    console.log(
      `landing bundle: ${(bytes / 1024).toFixed(1)} KB of ` +
        `${(LANDING_JS_BUDGET_BYTES / 1024).toFixed(0)} KB budget`,
    );

    expect(bytes).toBeLessThanOrEqual(LANDING_JS_BUDGET_BYTES);
  });

  it("does not pull the application's router or query client into the landing entry", () => {
    // The failure this catches: someone imports a shared component that
    // transitively drags react-router and TanStack Query onto a page that
    // needs neither. The size check would eventually catch it; this says why.
    const html = readFileSync(path.join(DIST, "landing.html"), "utf8");
    const entry = html.match(/src="\/(assets\/[^"]+\.js)"/)?.[1];
    const source = readFileSync(path.join(DIST, entry!), "utf8");

    expect(source).not.toContain("createBrowserRouter");
    expect(source).not.toContain("QueryClientProvider");
  });
});
