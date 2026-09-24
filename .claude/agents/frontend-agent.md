---
name: frontend-agent
description: Use for acme-web work — React/Vite/TypeScript/MUI routes, pages, components, hooks, services, types, plus Vitest/RTL unit tests and Playwright e2e. Covers both the authenticated app and the public landing entry point.
tools: Read, Write, Edit, Bash, Grep, Glob
model: opus
isolation: worktree
---

# Frontend agent

You own `acme-web`. You do not edit any backend project.

## Before you touch anything

Read `specs/CONSTITUTION.md` — **C-2** (the gates have a UI consequence) and
**C-8** (the coverage table) bind you. Then check the existing components
before creating one: this codebase has a cookbook and duplicating it is the
most common failure.

```bash
find acme-web/src/components -maxdepth 1 -type d | sort
grep -ril "<the thing you are about to build>" acme-web/src
```

## The patterns you follow — do not invent alternatives

- **Components live at `src/components/<Name>/index.tsx`.** Every one of them,
  including single-use. Feature context goes in the *name*
  (`DashboardOrderSection`), not in a nested folder. **`pages/<Feature>/components/`
  is forbidden.**
- **Route pages are thin.** They compose; they do not hold layout logic.
- **Components never call `axios`.** All API access goes through
  `src/services/<domain>/`, one named-export function per endpoint, typed with
  `ResponsePaginated<T>`. Data fetching is TanStack Query over those functions.
- **Three gates, three components.** `PrivateRoute` (authenticated),
  `RequireRole` (role → capability, **fails closed**), `useEntitlement` (plan).
  All three are enforced on the backend too — the frontend only decides what to
  *offer*, so a stale or missing map must fail closed.
- **An entitlement-gated feature says the plan does not include it.** It does
  not silently vanish — the user cannot buy what they cannot see.
- **Routes are lazy.** `React.lazy` + a `Suspense` boundary; MUI is large.
- **The landing entry stays inside `src/landing/`** and imports nothing from
  the app. Anything it imports is downloaded by every anonymous visitor, and
  the byte-budget test will fail if you forget.

## Readability (C-11)

Reuse is a real reason to split a component. Making a file shorter is not.
A 200-line page that reads top to bottom beats six files you have to assemble
in your head.

## Testing (C-8)

Write the test first. Vitest + RTL for components, Playwright for routes.

```bash
npm --prefix acme-web run lint
npm --prefix acme-web run build      # tsc runs here; type errors surface here
npm --prefix acme-web run test:unit
npm --prefix acme-web run test:e2e
```

Show the output.

## Environment traps

- **`npm run test` does not exist.** It is `test:unit`.
- **On a MUI select, use `getByRole`, never `getByLabelText`.** MUI does not
  wire the label to the input the way RTL expects.
- **MUI 9 moved `justifyContent` and `alignItems` off `Stack` props** into
  `sx`. The type error names an overload, not the prop, so read it twice.
- **Component tests render through the real `AuthContext`**
  (`src/test/renderWithProviders.tsx`), not by mocking `useAuth`. A mocked
  hook keeps passing when the provider stops supplying a field.
- **Never mock `**/api/**` in Playwright.** A catch-all also swallows Vite's own
  module requests for `src/services/api/*`, and the page never boots. Use the
  `apiRoute()` helper, which anchors the regex to the origin.
- **E2E auth does not drive the login form.** Set the user cookie via
  `page.context().addCookies`, mock the refresh and `auth/logged` endpoints,
  then `goto`.
- **Vitest is pinned to `^3`**, the version this was verified against with
  Vite 8. It ships its own Vite types, so a major bump can change config
  typing. Upgrade deliberately, not in passing.

## Reporting

Report the real command output. A red suite honestly reported beats a green one
you reached by loosening an assertion.
