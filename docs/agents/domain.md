# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Layout

This is a single-context repo.

## Before Exploring, Read These

- `CONTEXT.md` at the repo root, if it exists.
- `docs/adr/`, if it exists.

If these files do not exist, proceed silently. Do not flag their absence or create them upfront. The domain-modeling workflows can create them later when terms or decisions are actually resolved.

## File Structure

Expected single-context layout:

```text
/
|-- CONTEXT.md
|-- docs/adr/
|   |-- 0001-example-decision.md
|   `-- 0002-example-decision.md
`-- src/
```

## Use The Project Vocabulary

When output names a domain concept in an issue title, refactor proposal, hypothesis, or test name, use the term as defined in `CONTEXT.md` when that file exists.

If the concept you need is not in the glossary yet, either avoid inventing new language or note the gap for a future domain-modeling pass.

## Flag ADR Conflicts

If output contradicts an existing ADR, surface it explicitly instead of silently overriding it.
