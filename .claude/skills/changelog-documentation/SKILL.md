---
name: changelog-documentation
description: Use when reviewing implementation changes since the previous commit, updating .changelog.md with structured implementation highlights, or deciding whether a change needs documentation.
---

# Changelog and documentation

## Change discovery

```bash
git status --short
git diff --stat HEAD
git diff --cached --stat
git log --oneline -10
```

## The pre-commit routine

`.githooks/pre-commit` runs `scripts/precommit-changelog-docs.sh`, which stamps
a mechanical entry into `.changelog.md` listing which paths changed and marks
it `Review required`.

**Replace that placeholder before committing.** The hook records *which paths
changed*; it cannot know *what the change means*. That is your job.

Enable the hook once per clone:

```bash
git config core.hooksPath .githooks
```

## Entry format

Reverse-chronological. `# Changelog` H1, then `## YYYY-MM-DD`, then one
`### Topic` block per change, with these five keys:

```markdown
### WS-002 T-4 — service client timeout and audit
- Highlight: Every outbound service call now goes through one chokepoint that
  times out at 30s and records the attempt, including failures.
- Impact: An unreachable provider now produces an audited ERROR row instead of
  a 500; operators can see the attempt in the audit log.
- Scope: acme-bff/core/service_client.py, acme-bff/audit/recorder.py
- Verification: `python manage.py test` — 118 tests, OK. New: 6.
- Docs: Not needed — the pattern is already described in the constitution (C-1).
```

**Explain the implementation consequence, not just the file changed.** "Updated
services.py" is worthless; "an unreachable provider no longer 500s" is not.

## Does it need documentation?

| Change | Docs |
|---|---|
| New env var, new secret, new port | **Yes** — `.env.example` and the infra docs |
| New deploy step or operational procedure | **Yes** — `acme-tf/docs/` |
| A rule future agents must follow | **Yes** — a spec, or propose a Constitution amendment |
| New endpoint | Yes, if a client outside this repo calls it |
| Refactor with no behaviour change | No — the changelog entry is enough |
| Bug fix | Only if the workaround was documented |

A release note may **propose** a Constitution amendment. It may not make one.
