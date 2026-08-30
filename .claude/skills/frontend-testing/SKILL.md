---
name: frontend-testing
description: Use when validating or adding tests for the acme-web frontend — Playwright browser tests, route smoke tests, Vitest/RTL component tests, and API-mocked UI workflows.
---

# Frontend testing

```bash
npm --prefix acme-web run test:unit      # Vitest + RTL.  NOT "run test".
npm --prefix acme-web run test:e2e       # Playwright
npm --prefix acme-web run build          # tsc; type errors surface here
npm --prefix acme-web run test:lighthouse
```

## Tooling notes

- **Vitest is pinned to `^3`** — that is the version this boilerplate was
  built and verified against, with Vite 8. Vitest ships its own Vite types,
  so a major upgrade can change config typing (`resolve.tsconfigPaths` is
  not in Vitest 3's types, which is why `vitest.config.ts` declares the
  alias explicitly while `vite.config.ts` reads it from tsconfig). Upgrade
  deliberately and re-run the suite; do not bump it in passing.
- `vitest.config.ts` injects `VITE_*` into the test environment. A component
  that reads one will throw without it.
- `src/test/setup.ts` registers `afterEach(cleanup)` explicitly — there is no
  `globals: true` — and polyfills `matchMedia` guarded by `typeof window`,
  because the byte-budget test runs in the `node` environment with no DOM.

## API mocking rules

**Never use a catch-all `**/api/**` route.** It also swallows Vite's own module
requests for `src/services/api/*`, and the page never boots. The symptom is a
blank page and a timeout, which looks like an app bug and is not.

Anchor to the origin. `tests/e2e/support/apiRoute.ts` exports the helper:

```ts
const apiRoute = (path: string) =>
  new RegExp(`^http://127\\.0\\.0\\.1:3000/api/${path}`);

await page.route(apiRoute("example/"), (route) =>
  route.fulfill({ json: { count: 0, results: [] } }));
```

Mock the **smallest** surface the test needs. A test that mocks everything
proves the mocks work.

Use **business-realistic data**: real-looking dates, the same status enums the
backend emits, plausible names. A mock that returns `"foo"` hides formatting
bugs.

## Auth in e2e tests

Do not drive the login form — it makes every test depend on one page. Set the
cookie and mock the two identity endpoints:

```ts
await page.context().addCookies([{ name: "user", value: ..., url: BASE }]);
await page.route(apiRoute("auth/token/refresh/"), (r) =>
  r.fulfill({ json: { access: FAR_FUTURE_JWT } }));
await page.route(apiRoute("auth/logged/"), (r) =>
  r.fulfill({ json: { ...user, permissions: FULL_PERMISSIONS } }));
```

The permissions map matters: `RequireRole` fails closed, so an incomplete map
silently redirects the test to `/`.

## Component tests

- **`getByRole`, never `getByLabelText`, on a MUI select.** MUI does not wire
  the label to the input the way RTL expects.
- Mock the service module (`vi.mock("@/services/<domain>")`), not `axios`.
- `userEvent.setup()` before interacting.

## Lighthouse

`npm run test:lighthouse` builds, serves with `vite preview`, and asserts
performance >= 0.90 and accessibility >= 0.95 on the landing page.

Two flags in `lighthouserc.cjs` are load-bearing, and both present as the same
unhelpful "Chrome prevented page load with an interstitial":

- `--strictPort` — otherwise Vite silently moves to the next free port while
  Lighthouse still points at 4173 and audits whatever else is there.
- `--host 127.0.0.1` — `vite preview` binds `[::1]` only, and `127.0.0.1` is a
  different address on a dual-stack machine.

## When a Playwright test is required

- A new route.
- A change to a route gate (`PrivateRoute`, `RequireRole`, `useEntitlement`).
- A change to the API client's auth or refresh behaviour.
- Anything on the landing entry, which also has a byte budget and a Lighthouse
  floor.
