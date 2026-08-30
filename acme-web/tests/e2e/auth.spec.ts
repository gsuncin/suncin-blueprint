import { expect, test } from "@playwright/test";

import { apiRoute, json, signIn } from "./support/apiRoute";

test.describe("authentication", () => {
  test("an anonymous visitor is sent to the login page", async ({ page }) => {
    await page.route(apiRoute("auth/token/refresh/"), (route) =>
      json(route, { detail: "No refresh token." }, 401),
    );

    await page.goto("/records");

    await expect(page).toHaveURL(/\/login/);
    await expect(page.getByRole("heading", { name: "Sign in" })).toBeVisible();
  });

  test("a session survives a hard reload", async ({ page }) => {
    // The access token lives in memory only, so a reload always starts with
    // none. This asserts the HttpOnly cookie carries the session across it —
    // the failure mode being every reload bouncing the user to /login.
    await signIn(page);
    await page.route(apiRoute("example/records/"), (route) =>
      json(route, { count: 0, next: null, previous: null, results: [] }),
    );

    await page.goto("/records");
    await expect(page.getByRole("heading", { name: "Records" })).toBeVisible();

    await page.reload();
    await expect(page.getByRole("heading", { name: "Records" })).toBeVisible();
  });

  test("the login page reports a rejected credential", async ({ page }) => {
    await page.route(apiRoute("auth/token/refresh/"), (route) => json(route, {}, 401));
    await page.route(apiRoute("auth/token/"), (route) =>
      json(route, { detail: "No active account found with the given credentials" }, 401),
    );

    await page.goto("/login");
    await page.getByLabel("Email").fill("ada@acme.test");
    await page.getByLabel("Password").fill("wrong");
    await page.getByRole("button", { name: "Sign in" }).click();

    await expect(page.getByRole("alert")).toContainText(/no active account/i);
  });
});
