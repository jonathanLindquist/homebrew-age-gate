# HAG-0003 Latest Safe Upgrade Handoff

- Ticket: HAG-0003
- Board: ~/obsidian_notes/pocock-skills-vault/projects/utilities/homebrew-age-gate/Homebrew Age Gate Kanban.md
- Card: HAG-0003 Latest Safe Upgrade
- Migrated: 2026-06-19

## Goal

Add wrapper-only support for:

```sh
brew upgrade --latest-safe [packages...]
```

The flag must not be passed to real Homebrew. It should mean: when the current Homebrew definition is too young under `min_age_days`, upgrade to the newest historical definition that is old enough, if one can be proven.

## Current State

`brew outdated` can now display a historical safe target for too-young entries:

```text
apidog version: 2.8.34 age: 5d -> version: 2.8.20 age: 20d
```

That display is powered by `HomebrewAgeGate::SafeVersionResolver`, which:

- runs only when the current definition age is known and too young;
- asks git for the newest same-file commit at or before the age cutoff with `rev-list -1 --before`;
- infers the version from Homebrew-native definition fields in safe order: explicit `version`, URL, `tag`, then semantic `revision`;
- returns `nil` if the safe historical version cannot be proven.

This is only a report decoration. Normal `brew upgrade apidog` still asks Homebrew to install the current definition.

## Required Semantics

- `--latest-safe` is a wrapper-only `brew upgrade` flag.
- The wrapper must strip `--latest-safe` before invoking any real Homebrew command.
- Without `--latest-safe`, current behavior remains unchanged: too-young current definitions are blocked.
- With `--latest-safe`, too-young current definitions may be routed to a historical safe definition only if that definition is proven by git history.
- Unknown age remains fail-closed unless already explicitly named in `unsafe_allow_unknown_age`.
- Never call bare real `brew upgrade`.
- Never run real `brew update`.

## Acceptance Criteria

- [ ] `--latest-safe` is accepted by the wrapper for `brew upgrade` and is never passed to real Homebrew.
- [ ] Without `--latest-safe`, existing too-new package blocking behavior is unchanged.
- [ ] With `--latest-safe`, a too-new package is routed to a historical safe definition only when that definition can be proven from git history.
- [ ] If no safe historical definition can be proven, the package remains blocked.
- [ ] Unknown package age remains fail-closed unless explicitly allowed by unsafe config.
- [ ] Dry-run expansion is still validated before any final upgrade command.
- [ ] Final upgrade commands remain explicit allowlists and never call bare `brew upgrade`.
- [ ] Verification uses fake-brew integration tests and does not run real `brew update` or real `brew upgrade`.

## Suggested Implementation Shape

1. Extend `ArgParser` to recognize `--latest-safe` as a wrapper-only upgrade flag.
   - Add a boolean to `ParsedUpgradeArgs`.
   - Exclude it from `flags`, `outdated_flags`, `flags_without_dry_run`, and all real Homebrew invocations.

2. Extend planning decisions.
   - Current `Decision` can represent current-definition allowed/skipped.
   - Add either `safe_version` to `Decision` or introduce a parallel plan collection for safe historical targets.
   - For too-young decisions under `--latest-safe`, call `SafeVersionResolver`.
   - If no safe version is found, keep the package skipped.

3. Decide installation strategy for historical definitions.
   - Do not pass `package@version` to Homebrew unless Homebrew already has that formula.
   - Preferred safe approach: create a temporary tap directory containing the historical definition file at the safe commit, then invoke Homebrew against that explicit tap package.
   - Ensure final commands target explicit package names only.
   - Clean up temporary taps/files after the command.

4. Preflight still matters.
   - Run a dry-run against the exact historical target strategy.
   - Parse planned names.
   - Fail closed if Homebrew expands to any unplanned package whose age cannot be proven or routed to a safe historical definition.

## Test Plan

- Unit: `ArgParser` accepts `--latest-safe` and does not forward it.
- Unit: too-young package with historical safe version is selected only when `--latest-safe` is set.
- Unit: too-young package without a historical safe version remains blocked.
- Integration: fake brew proves no bare `upgrade` is invoked.
- Integration: fake brew proves `--latest-safe` is never passed through.
- Integration: dry-run expansion containing a too-young dependency still fails closed unless that dependency also has a safe historical target.
- Regression: normal `brew upgrade` behavior is unchanged.

## Open Design Questions

- Whether safe historical upgrade should support casks first, then formulae.
- How to represent a historical cask install command in a way Homebrew accepts consistently.
- Whether to persist any temporary tap cache or always generate it per invocation.
