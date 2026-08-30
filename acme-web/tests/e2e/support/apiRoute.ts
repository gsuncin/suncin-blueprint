import type { Page, Route } from "@playwright/test";

export const BASE_URL = "http://127.0.0.1:3000";

/**
 * Build a route matcher anchored to the API origin.
 *
 * NEVER use a catch-all like `**\/api/**`. It also matches Vite's own module
 * requests for files under `src/services/api/`, so the dev server's modules get
 * intercepted, the page never boots, and the failure looks like an application
 * bug rather than a mock that was too greedy. This has cost a debugging session
 * more than once.
 */
export const apiRoute = (path: string): RegExp =>
  new RegExp(`^${BASE_URL.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}/api/${path}`);

export const json = (route: Route, body: unknown, status = 200) =>
  route.fulfill({ status, contentType: "application/json", body: JSON.stringify(body) });

/** A token that will not expire during the run. */
const FAR_FUTURE_ACCESS_TOKEN = [
  "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9",
  "eyJ1c2VyX2lkIjoidXNlci0xIiwiZXhwIjo0MTAyNDQ0ODAwfQ",
  "signature-not-verified-client-side",
].join(".");

export const FULL_PERMISSIONS = {
  account: { view: true, manage: true },
  users: { view: true, manage: true },
  example: { view: true, manage: true },
  audit: { view: true, manage: true },
};

export const READ_ONLY_PERMISSIONS = {
  account: { view: false, manage: false },
  users: { view: false, manage: false },
  example: { view: true, manage: false },
  audit: { view: false, manage: false },
};

interface SignInOptions {
  permissions?: typeof FULL_PERMISSIONS;
  entitlements?: Record<string, boolean>;
}

/**
 * Put the page in a signed-in state without driving the login form.
 *
 * Driving the form would make every test depend on that one page, so a change
 * to the login markup fails the whole suite and tells you nothing about the
 * feature under test.
 */
export async function signIn(page: Page, options: SignInOptions = {}): Promise<void> {
  const {
    permissions = FULL_PERMISSIONS,
    entitlements = { example_jobs: true, bulk_export: true },
  } = options;

  await page.route(apiRoute("auth/token/refresh/"), (route) =>
    json(route, { access: FAR_FUTURE_ACCESS_TOKEN }),
  );

  await page.route(apiRoute("auth/logged/"), (route) =>
    json(route, {
      id: "user-1",
      email: "ada@acme.test",
      first_name: "Ada",
      last_name: "Lovelace",
      role: "OWNER",
      account: "acct-1",
      is_active: true,
      // An incomplete map silently redirects the test to "/", because
      // RequireRole fails closed. That looks like a routing bug and is not.
      permissions,
      entitlements,
    }),
  );
}
