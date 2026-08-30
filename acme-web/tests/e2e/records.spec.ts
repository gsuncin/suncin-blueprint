import { expect, test } from "@playwright/test";

import { READ_ONLY_PERMISSIONS, apiRoute, json, signIn } from "./support/apiRoute";

const RECORD = {
  id: "rec-1",
  recipient: "Ada",
  locale: "en",
  status: "PENDING",
  message: "",
  provider_reference: "",
  error_code: "",
  error_message: "",
  delivered_at: null,
  is_active: true,
  created_at: "2026-08-29T10:00:00Z",
  updated_at: "2026-08-29T10:00:00Z",
};

const listOf = (...records: object[]) => ({
  count: records.length,
  next: null,
  previous: null,
  results: records,
});

test.describe("records", () => {
  test("lists what the account has", async ({ page }) => {
    await signIn(page);
    await page.route(apiRoute("example/records/"), (route) => json(route, listOf(RECORD)));

    await page.goto("/records");

    await expect(page.getByRole("cell", { name: "Ada" })).toBeVisible();
    await expect(page.getByText("Pending")).toBeVisible();
  });

  test("a provider failure is shown as a failed row, not as a crash", async ({ page }) => {
    // The client-side half of C-1: delivery resolves 200 with status=ERROR, and
    // the UI must render that as an outcome rather than an unhandled rejection.
    await signIn(page);
    await page.route(apiRoute("example/records/$"), (route) => json(route, listOf(RECORD)));
    await page.route(apiRoute("example/records/rec-1/deliver/"), (route) =>
      json(route, {
        ...RECORD,
        status: "ERROR",
        error_code: "SERVICE_UNREACHABLE",
      }),
    );
    await page.route(apiRoute("example/records/\\?"), (route) =>
      json(route, listOf({ ...RECORD, status: "ERROR", error_code: "SERVICE_UNREACHABLE" })),
    );

    await page.goto("/records");
    await page.getByRole("button", { name: "Deliver" }).click();

    await expect(page.getByText("Failed")).toBeVisible();
    await expect(page.getByText("SERVICE_UNREACHABLE")).toBeVisible();
  });

  test("an unentitled plan is told to upgrade, not shown an empty page", async ({ page }) => {
    await signIn(page, { entitlements: { example_jobs: false, bulk_export: false } });
    await page.route(apiRoute("example/records/"), (route) => json(route, listOf()));

    await page.goto("/records");

    await expect(page.getByText(/is not in your plan/i)).toBeVisible();
    await expect(page.getByRole("link", { name: /see plans/i })).toBeVisible();
    // Read access survives losing the entitlement.
    await expect(page.getByRole("heading", { name: "Records" })).toBeVisible();
  });

  test("a viewer cannot reach the users page", async ({ page }) => {
    await signIn(page, { permissions: READ_ONLY_PERMISSIONS });
    await page.route(apiRoute("example/records/"), (route) => json(route, listOf()));

    await page.goto("/settings/users");

    // RequireRole redirects rather than rendering a forbidden page.
    await expect(page.getByRole("heading", { name: "Dashboard" })).toBeVisible();
  });

  test("the nav only offers what the role can reach", async ({ page }) => {
    await signIn(page, { permissions: READ_ONLY_PERMISSIONS });
    await page.route(apiRoute("example/records/"), (route) => json(route, listOf()));

    await page.goto("/records");

    await expect(page.getByRole("link", { name: "Records" })).toBeVisible();
    await expect(page.getByRole("link", { name: "Users" })).toHaveCount(0);
  });
});
