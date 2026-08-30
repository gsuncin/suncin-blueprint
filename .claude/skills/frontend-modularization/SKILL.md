---
name: frontend-modularization
description: Use when creating, refactoring, or reorganizing React/Vite frontend code in acme-web — route pages, large TSX files, component extraction, reusable UI, hooks, services, types, or checks against the existing cookbook before adding new code.
---

# Frontend modularization

## Cookbook check — before you create anything

The most common failure in this codebase is building something that already
exists under a different name.

```bash
find acme-web/src/components -maxdepth 1 -type d | sort
find acme-web/src/hooks acme-web/src/utils -type f | sort
grep -ril "<the concept you are about to build>" acme-web/src
```

If something close exists, extend it. If you extend it, say so in your report.

## Page structure

A route page composes; it does not implement. When a page grows past roughly
250 lines, the sections inside it are usually the components trying to get out.

## Component placement

- **Every extracted component is `src/components/<Name>/index.tsx`.** Every one,
  including single-use.
- **Feature context lives in the name**, not the path:
  `DashboardOrderSection`, not `pages/Dashboard/components/OrderSection`.
- **`pages/<Feature>/components/` is forbidden.** It looks tidy and then the
  second page that needs the component cannot reach it without a refactor.
- Colocate the test: `index.test.tsx` next to `index.tsx`.

## Supporting code

| Kind | Goes in | Rule |
|---|---|---|
| Reused stateful behaviour | `src/hooks/<domain>/` | Returns a documented shape |
| Pure logic | `src/utils/` | No React, no network |
| Every API call | `src/services/<domain>/` | One named export per endpoint |
| Shared shapes | `src/types/` | Mirrors the backend contract |

**A component never calls `axios`.** It calls a service function, usually
through TanStack Query.

## Refactor workflow

1. Run the cookbook check.
2. Write or update the test **first** — it is what lets you move code safely.
3. Extract, keeping the public behaviour identical.
4. `npm --prefix acme-web run build` — `tsc` runs here.
5. `test:unit`, then `test:e2e` if a route changed.

## Guardrails

- Do not create a second frontend app.
- Do not introduce Storybook, a component library, or a CSS framework.
- Do not "helpfully" upgrade Vitest past `^3`.
- Respect unrelated dirty work in the tree — commit only your own paths.

## Reconciling this with C-11

C-11 says fewer, larger functions. This skill says extract components. They
agree: **reuse is a real reason to split; making a file shorter is not.** A
200-line page that reads top to bottom beats six files you have to assemble in
your head.
