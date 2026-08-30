# WS-000 — <one-line title>

**Branch:** `spec/000-<slug>`
**Primary agent:** `<agent-name>` · **Support:** `<agent-name>` (<what for>)

## Problem

Why this now. What breaks, or stays broken, without it. Two paragraphs at most.

No solutions in this section — if you find yourself writing "we should use X",
that belongs in Decisions or Design.

## Decisions

Choices already made, each with the reasoning that produced it. A task cites
these by id rather than restating them.

**D-1 — <the choice, as a one-line claim>.** The reasoning. What was rejected
and why. What would make us revisit.

**D-2 — <…>.**

## Open questions

Every unknown, with an id and an owner. An owner of a human name is a **hard
gate**: the agent stops and asks, it does not pick a default.

**Q-0.1** — <question>. **Owner: <agent-name | human>.**

**Q-0.2** — <question>. **Owner: <…>.** *(Blocks T-3.)*

Resolved ones are struck through in place, with the answer and the date:

~~**Q-0.3**~~ — ~~<question>~~ — **Answered <date>: <the answer>.**

## Design

Architecture, contracts, file-level changes. A fenced tree of exactly what will
be created or changed, with `NEW` / `~` markers, is worth more than prose.

```
acme-bff/
  example/
    services.py       ~  add create_example_job
    tests_services.py NEW
```

Where the feature touches a boundary, state the contract in both directions and
in the same words both sides will read.

## Tasks

Ordered, atomic, agent-assignable. Definition of Done is a **command whose
output proves it**, not an adjective.

| ID | Task | Agent | Definition of done |
|----|------|-------|--------------------|
| T-1 | <task> | `<agent>` | `<command>` green, output shown |
| T-2 | <task> | `<agent>` | <observable, checkable outcome> |
