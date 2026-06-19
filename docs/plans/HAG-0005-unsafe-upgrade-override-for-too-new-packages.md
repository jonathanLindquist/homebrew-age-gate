# HAG-0005 Unsafe Upgrade Override for Too-New Packages

- Ticket: HAG-0005
- Board: ~/obsidian_notes/pocock-skills-vault/projects/utilities/homebrew-age-gate/Homebrew Age Gate Kanban.md
- Card: HAG-0005 Unsafe Upgrade Override for Too-New Packages
- Created: 2026-06-19

## Summary

Add a wrapper-only `brew upgrade --unsafe <name...>` override for cases where the user intentionally wants to upgrade a package whose Homebrew definition is too new under the age policy. The override should also apply to too-new dependent formulae that Homebrew includes in the frozen dry-run plan for the explicitly unsafe roots.

## Context

The current age gate fails closed when a root package or dependency is too new. That is the safe default and must remain the default behavior.

The requested future behavior is an explicit escape hatch for one-off upgrades. The flag should be handled by `homebrew-age-gate`, stripped before calling real Homebrew, and represented clearly in the plan output so the user can see which packages are bypassing the age policy.

Important safety constraints:

- Never call bare `brew upgrade`; final upgrade calls must still use explicit allowlists.
- Do not pass `--unsafe` through to real Homebrew.
- Keep unknown-age packages fail-closed unless a separate existing unsafe unknown-age config allows them.
- Do not let `--unsafe` without explicit package names become a global upgrade-all-new override unless that behavior is deliberately designed and accepted.
- All implementation and verification must use fake Homebrew and temporary tap repositories, not real `brew upgrade`.

## Plan

- [ ] Extend argument parsing to recognize wrapper-only `--unsafe`.
- [ ] Define whether `--unsafe` requires at least one explicit package name; recommended default is to require explicit names.
- [ ] Mark explicitly named packages as unsafe-approved when their only blocker is `reason == "too new"`.
- [ ] During dependency preflight, allow too-new dependent formulae that are pulled in by an unsafe-approved root.
- [ ] Keep unknown ages, unparseable packages, auto-updating cask blockers, and unrelated blocked roots fail-closed unless covered by existing explicit unsafe config.
- [ ] Strip `--unsafe` from all real Homebrew discovery, dry-run, and final upgrade command arguments.
- [ ] Update plan/report output so unsafe-approved packages are visibly distinct from normal old-enough packages.

## Acceptance Criteria

- [ ] `brew upgrade --unsafe sqlite` can proceed when `sqlite` is too new, after normal dry-run validation.
- [ ] If the unsafe root pulls a too-new dependent formula in the frozen dry-run output, that dependency is allowed for that unsafe root's final upgrade path.
- [ ] A too-new package that was not explicitly named and is not a dependency of an unsafe root remains blocked.
- [ ] Unknown-age packages still fail closed unless covered by existing unsafe unknown-age config.
- [ ] `--unsafe` is never passed to the real Homebrew executable.
- [ ] Final upgrade commands remain explicit package allowlists and never call bare `brew upgrade`.
- [ ] User-visible plan output identifies unsafe-approved packages and explains that the age gate was bypassed intentionally.

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

Fill in when completed with implementation summary, commits, verification commands, and results. Move the Kanban card to Completed only after this is filled in and the Definition of Done is checked.
