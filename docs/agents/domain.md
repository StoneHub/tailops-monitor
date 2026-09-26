# Domain docs

How engineering skills consume this repo's domain documentation.

## Before exploring

- Read root `CONTEXT.md` when it exists.
- Read ADRs under `docs/adr/` that touch the work area.
- If either location is absent, proceed silently. `/domain-modeling` creates files only when a term or decision is resolved.

## File structure

This is a single-context repo:

```text
/
├── CONTEXT.md
├── docs/
│   └── adr/
└── src/
```

## Use the glossary

Use the terms defined in `CONTEXT.md` in issue titles, architecture proposals, hypotheses, and tests. If a needed concept is absent, reconsider the term or record the gap for `/domain-modeling`.

## Flag ADR conflicts

If work contradicts an ADR, name the ADR and explain why the decision should be reopened.
