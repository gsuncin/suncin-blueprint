# acme-web

React 19 / Vite / TypeScript / MUI. Two entries from one build: the
authenticated SPA and the public landing page.

## The two entries

`vite.config.ts` declares both `index.html` and `landing.html` as Rollup
inputs. `nginx.conf` picks between the built outputs by `Host`, so one image
and one deploy serve both — and nothing the app imports can reach the landing
bundle or vice versa.

The non-obvious bit is in `nginx.conf`:

```nginx
location = / { try_files $spa_fallback =404; }   # exact match, required
location /   { try_files $uri $uri/ $spa_fallback; }
```

Without the exact-match block, the `index` directive resolves `index.html` —
which exists — so `try_files` is satisfied before it ever consults the
host-based fallback, and the apex serves the app instead of the landing page.

## The landing entry is isolated on purpose

`src/landing/` has its own theme, its own copy in `content.ts`, no router, no
query client and no auth context. Everything it imports is downloaded by every
anonymous visitor.

`src/landing/pageBudget.test.ts` runs a **real Vite build** and fails if the
bundle grows past its budget, and separately asserts that the router and query
client have not been dragged in by a shared import.

`landing.html` also carries an inline `prefers-reduced-motion` block — inline,
so it applies from the first paint rather than arriving with the JS — and a
`<noscript>` fallback injected at build time.

## Three gates

Mirroring the backend (C-2):

| Gate | Where | Question |
|---|---|---|
| `PrivateRoute` | route element | Is anyone signed in? |
| `RequireRole` | route element | Does this user's **role** allow it? |
| `useEntitlement` / `EntitlementGate` | inside the page | Did the account's **plan** buy it? |

All three fail closed. All three are enforced on the backend independently —
these only decide what the UI **offers**.

An unentitled feature renders an upgrade prompt rather than disappearing: a
feature the user cannot see is one they cannot buy, and "you have no
permission" is the wrong message for a plan limit.

## The API client

`src/services/api/api.ts`:

- The access token lives in a **module variable**, never `localStorage`. It dies
  with the tab; an XSS cannot exfiltrate something that outlives the session.
- The refresh token is an **HttpOnly cookie** JavaScript cannot read at all.
- **Single-flight refresh.** Six requests firing on mount produce six 401s;
  without this each starts its own refresh, the token rotates six times, and
  five replays fail with a token that was just invalidated.
- `refreshClient` is a second axios instance with no interceptors, so a 401 on
  refresh cannot trigger a refresh of the refresh.
- `normalizeApiError` digs the message out of `detail`, a field name, or
  `non_field_errors` — DRF puts it in a different place depending on what
  rejected the request.

## Testing

```bash
npm run lint
npm run build          # tsc runs here; type errors surface here
npm run test:unit      # NOT "npm run test" — there is no such script
npm run test:e2e
npm run test:lighthouse
```

Three traps, each of which has cost someone an afternoon:

- **Never mock `**/api/**` in Playwright.** A catch-all also swallows Vite's own
  module requests for `src/services/api/*` and the page never boots — which
  looks like an application bug. Use `apiRoute()`, which anchors to the origin.
- **`getByRole`, not `getByLabelText`, on a MUI select.**
- **`vite preview` binds `[::1]` only.** Lighthouse navigates to `127.0.0.1`,
  which is a different address; `lighthouserc.cjs` passes `--host 127.0.0.1`
  and `--strictPort` for exactly this reason.

Component tests render through the real `AuthContext` rather than mocking
`useAuth`, so they still fail if the provider stops supplying a field the
component reads.

## Adding a component

`src/components/<Name>/index.tsx`. Every one, including single-use. Feature
context goes in the **name** (`DashboardOrderSection`), not in a nested folder —
`pages/<Feature>/components/` is forbidden, because the second page that needs
it cannot reach it without a refactor.

Components never call `axios`: they call a function in `src/services/<domain>/`,
usually through TanStack Query.
