# HAG-0005 Unsafe Upgrade Override for Too-New Packages

- Ticket: HAG-0005
- Board: derived from `PROJECT_WORKFLOW_OBSIDIAN_VAULT` and this repo path relative to `$HOME`
- Card: HAG-0005 Unsafe Upgrade Override for Too-New Packages
- Created: 2026-06-19

## Summary

Add a wrapper-only `brew upgrade --unsafe <name...>` override for cases where the user intentionally wants to upgrade a package whose Homebrew definition is too new under the age policy. The override should also apply to too-new dependent formulae that Homebrew includes in the frozen dry-run plan for the explicitly unsafe roots.

## Context

The current age gate fails closed when a root package or dependency is too new. That is the safe default and must remain the default behavior.

The requested future behavior is an explicit escape hatch for one-off upgrades. The flag should be handled by `homebrew-age-gate`, stripped before calling real Homebrew, and represented clearly in the plan output so the user can see which packages are bypassing the age policy.

This ticket is scoped to explicitly named upgrade targets, such as `brew upgrade --unsafe sqlite`. The no-argument upgrade-all unsafe mode is tracked separately in HAG-0006 and should use the same parser/reporting contract without expanding this ticket's acceptance criteria.

Important safety constraints:

- Never call bare `brew upgrade`; final upgrade calls must still use explicit allowlists.
- Do not pass `--unsafe` through to real Homebrew.
- Before submitting the final real upgrade for any unsafe-approved package, prompt once for explicit user confirmation and abort if the user does not confirm.
- Keep unknown-age packages fail-closed unless a separate existing unsafe unknown-age config allows them.
- Keep no-argument upgrade-all unsafe behavior out of this ticket except for shared parser/reporting contracts; implement that accepted behavior under HAG-0006.
- All implementation and verification must use fake Homebrew and temporary tap repositories, not real `brew upgrade`.

## Plan

- [x] Extend argument parsing to recognize wrapper-only `--unsafe`.
- [x] Keep this ticket's implementation path scoped to explicitly named unsafe roots while coordinating shared `--unsafe` parsing with HAG-0006.
- [x] Mark explicitly named packages as unsafe-approved when their only blocker is `reason == "too new"`.
- [x] During dependency preflight, allow too-new dependent formulae that are pulled in by an unsafe-approved root.
- [x] Add a single confirmation prompt before submitting the final upgrade when one or more unsafe-approved packages would be upgraded.
- [x] Keep unknown ages, unparseable packages, auto-updating cask blockers, and unrelated blocked roots fail-closed unless covered by existing explicit unsafe config.
- [x] Strip `--unsafe` from all real Homebrew discovery, dry-run, and final upgrade command arguments.
- [x] Update plan/report output so unsafe-approved packages are visibly distinct from normal old-enough packages.

## Acceptance Criteria

- [x] `brew upgrade --unsafe sqlite` can proceed when `sqlite` is too new, after normal dry-run validation.
- [x] If the unsafe root pulls a too-new dependent formula in the frozen dry-run output, that dependency is allowed for that unsafe root's final upgrade path.
- [x] Before submitting the real upgrade, the wrapper prompts once for confirmation when any unsafe-approved package is present.
- [x] Multi-package unsafe upgrades still produce exactly one confirmation prompt, not one prompt per package.
- [x] If the user declines or does not provide the expected confirmation, no final upgrade command is submitted.
- [x] When explicit package names are provided, a too-new package that was not explicitly named and is not a dependency of an unsafe root remains blocked.
- [x] Unknown-age packages still fail closed unless covered by existing unsafe unknown-age config.
- [x] `--unsafe` is never passed to the real Homebrew executable.
- [x] Final upgrade commands remain explicit package allowlists and never call bare `brew upgrade`.
- [x] User-visible plan output identifies unsafe-approved packages and explains that the age gate was bypassed intentionally.

## Verification

Run focused tests while implementing:

```sh
rbenv exec bundle exec ruby -Ilib -Itest test/arg_parser_test.rb
rbenv exec bundle exec ruby -Ilib -Itest test/planner_test.rb
rbenv exec bundle exec ruby -Ilib -Itest test/wrapper_integration_test.rb
```

Run the full suite before completion:

```sh
rbenv exec bundle exec rake test
```

## Outcome

CLI contract: `brew upgrade --unsafe <name...>` (also `homebrew-age-gate plan --unsafe <name...>`). `--unsafe` with no names is an argument error until HAG-0006 defines upgrade-all behavior.

Implementation:

- `ArgParser` recognizes wrapper-only `--unsafe`, keeps it out of `flags`, and exposes `ParsedUpgradeArgs#unsafe?` and `#unsafe_root?`.
- `Planner#decide` allows a known-age too-new package with reason `too new; age gate bypassed by --unsafe` and `Decision#unsafe?` only when it is a named unsafe root, or when it appears in the frozen dry-run of a batch made only of unsafe roots. Mixed batches stay gated and fall back to per-root isolation.
- `UpgradePreflight` collects unsafe-approved decisions from approved batches. `CLI.run_brew_wrapper` prints them under `Age gate bypassed with --unsafe:` and asks once (`[y/N]`) before any final upgrade. Only `y`/`yes` continues; anything else, including EOF, exits 1 with no final upgrade. `--dry-run` prints the list without prompting.
- Unknown age, unparseable dry-run output, and auto-updating casks remain fail-closed.

Commits:

- `4bcf712` Add wrapper-only --unsafe override for named too-new packages
- `e99f4ea` Make outdated color test independent of the current date (pre-existing failure found during verification)

Verification (2026-11-15):

- `rbenv exec bundle exec ruby -Ilib -Itest test/arg_parser_test.rb`: 8 runs, 0 failures
- `rbenv exec bundle exec ruby -Ilib -Itest test/planner_test.rb`: 8 runs, 0 failures
- `rbenv exec bundle exec ruby -Ilib -Itest test/wrapper_integration_test.rb`: 33 runs, 0 failures
- `rbenv exec bundle exec rake test`: 91 runs, 835 assertions, 0 failures, 0 errors, 0 skips
- All upgrade tests use the fake-brew harness and assert no bare `brew upgrade` or `brew update` call.

## Progress Notes

- 2026-11-16: Started implementation of wrapper-only brew upgrade --unsafe <names...>.

## Completion Notes

- 2026-11-16: Completed wrapper-only brew upgrade --unsafe <names...> with one confirmation prompt; full suite green.
