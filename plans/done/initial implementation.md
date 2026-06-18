# homebrew-age-gate Implementation Plan

## Summary

Build a PATH-level `brew` shim plus a separate `homebrew-age-gate` diagnostic command. The shim delegates every non-`upgrade` command to real Homebrew unchanged. For `brew upgrade`, it computes and validates a frozen age-gated upgrade plan before delegating to `/opt/homebrew/bin/brew upgrade <allowed names...>`.

Core invariant: by default, no package definition younger than `min_age_days` upgrades. Unsafe config can weaken this only where explicitly named.

## Must-Have Safety Constraint

During development and testing, do not run real `brew update`, real `brew upgrade`, or any command path that can update or upgrade the developer machine's Homebrew formulae/casks.

Tests must use a fake `brew` executable and temporary git tap repositories. Verification may inspect wrapper behavior, generated command arguments, environment variables, and reports, but must not perform actual Homebrew updates or upgrades.

## Key Behavior

- `brew update` and `brew outdated` remain pass-through. Add `homebrew-age-gate plan` for the truthful age-gated view.
- `brew upgrade` and `brew upgrade <names...>` both age-gate explicit targets; explicit names are not a bypass.
- Config lives at `$XDG_CONFIG_HOME/homebrew-age-gate/config.json`, falling back to `~/.config/homebrew-age-gate/config.json`.
- Default config:
  - `min_age_days: 7`
  - conservative casks enabled
  - cleanup disabled
  - installed-dependent check disabled by default
- Config package identities use canonical names such as `homebrew/core/jq` and `homebrew/cask/slack`; reports and docs explain normalization.

## Upgrade Flow

- Parse `brew upgrade` args with a strict known-flag parser. Unknown or ambiguous flags fail closed.
- Load config first. Invalid config aborts before running Homebrew.
- Run real `brew outdated --json=v2` with relevant discovery flags and normal Homebrew auto-update behavior.
- Freeze later commands with `HOMEBREW_NO_AUTO_UPDATE=1`.
- Fetch metadata via `brew info --json=v2`, using `tap`, `tap_git_head`, `ruby_source_path`, `version`, and `auto_updates`.
- Determine age from git committer timestamp:
  - `git -C <tap_repo> log -1 --format=%ct <tap_git_head> -- <ruby_source_path>`
  - eligible when `now - commit_time >= min_age_days * 86400`
  - missing tap/path/commit/history is unknown age.
- Casks:
  - skip `version: latest` unless named in `allow_latest_casks`
  - skip `auto_updates: true` unless named in `allow_auto_updates_casks`
  - skip unknown age unless named in `unsafe_allow_unknown_age`
- If no packages remain, print a skip report and exit `0`.

## Safety Preflight

- Before actual upgrade, run a frozen `brew upgrade --dry-run <allowed names...>` with the same final safety env.
- Parse the full dry-run plan and age-gate every planned package, including dependencies.
- If the dry-run plan contains any young, unknown, unparseable, or disallowed package, abort the whole upgrade with a report.
- If the original user command was `--dry-run`, print the validated dry-run output and stop.
- Final upgrade env:
  - always `HOMEBREW_NO_AUTO_UPDATE=1`
  - always `HOMEBREW_NO_INSTALL_CLEANUP=1`
  - set `HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1` by default, but allow an explicitly unsafe config override.

## Commands

- `bin/brew`: Ruby shim, subprocess-only integration with real Homebrew and `git`.
- `bin/homebrew-age-gate doctor`: verify PATH ordering, real brew path, config validity, and git availability without running real `brew update` or `brew upgrade`.
- `bin/homebrew-age-gate plan [upgrade args...]`: show allowed/skipped/unsafe candidates without upgrading.
- Non-upgrade `brew` commands, including `brew update`, `brew outdated`, and `brew info`, always exec real Homebrew unchanged.

## Tests

- Unit tests for arg parsing, config validation, canonical name normalization, cask policy, and age cutoff math.
- Fixture tests with temporary git tap repos to verify committer-date age lookup and fail-closed unknown-age behavior.
- Fake-brew integration tests for:
  - bare `brew upgrade`
  - explicit `brew upgrade foo`
  - empty allowlist exits `0`
  - unknown flags abort
  - cask `auto_updates` and `latest` opt-ins
  - unsafe unknown-age per-package allowlist
  - dry-run full-plan dependency rejection
  - cleanup and auto-update env passed to final upgrade
  - non-upgrade commands pass through unchanged

