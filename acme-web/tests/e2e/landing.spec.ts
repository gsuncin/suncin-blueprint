import { expect, test } from "@playwright/test";

const LANDING = "/landing.html";

test.describe("landing page", () => {
  test("renders its message", async ({ page }) => {
    await page.goto(LANDING);

    await expect(
      page.getByRole("heading", { name: /ship the boring parts once/i }),
    ).toBeVisible();
  });

  test("makes no API calls at all", async ({ page }) => {
    // An anonymous marketing page that talks to the API is either leaking
    // something or waking up a backend for no reason.
    const apiCalls: string[] = [];
    page.on("request", (request) => {
      if (request.url().includes("/api/")) apiCalls.push(request.url());
    });

    await page.goto(LANDING);
    await page.waitForLoadState("networkidle");

    expect(apiCalls).toEqual([]);
  });

  test("respects prefers-reduced-motion", async ({ page }) => {
    await page.emulateMedia({ reducedMotion: "reduce" });
    await page.goto(LANDING);

    await expect(page.getByRole("heading", { name: /questions/i })).toBeVisible();
  });

  test("still says something with JavaScript disabled", async ({ browser }) => {
    const context = await browser.newContext({ javaScriptEnabled: false });
    const page = await context.newPage();

    await page.goto(LANDING);

    await expect(page.getByText(/ship the boring parts once/i)).toBeVisible();
    await expect(page.getByRole("link", { name: /sign in/i })).toBeVisible();

    await context.close();
  });
});
