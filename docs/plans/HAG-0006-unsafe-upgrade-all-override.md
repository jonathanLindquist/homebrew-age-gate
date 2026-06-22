# HAG-0006 Unsafe Upgrade-All Override

- Ticket: HAG-0006
- Board: derived from `$PROJECT_WORKFLOW_OBSIDIAN_VAULT` and `docs/agents/project-workflow.json`
- Card: HAG-0006 Unsafe Upgrade-All Override
- Created: 2026-06-21

## Summary

Add the no-argument unsafe mode for the wrapper-only flag. Running brew upgrade with the unsafe flag and no package names intentionally bypasses the age gate for every outdated package in the frozen upgrade plan while preserving explicit final allowlists and fake-brew-only safety guarantees. This complements HAG-0005, which covers explicitly named unsafe upgrade targets.

## Context

HAG-0005 already covers `brew upgrade --unsafe <name...>` for explicitly named too-new packages and their too-new dry-run dependencies. This ticket covers the accepted companion behavior for `brew upgrade --unsafe` with no package names: treat every package discovered by the normal upgrade planning flow as intentionally unsafe-approved for age-gate purposes.

Coordinate with HAG-0005 for shared argument parsing, flag stripping, and plan/report output. If this is implemented before HAG-0005, keep the implementation shaped so the named-target path can reuse the same unsafe approval model.

Safety constraints:

- Never call bare `brew upgrade`; final upgrade calls must still use explicit allowlists.
- Never pass `--unsafe` to real Homebrew.
- Before submitting the final real upgrade for any unsafe-approved package, prompt once for explicit user confirmation and abort if the user does not confirm.
- Continue to fail closed for unknown age, unparseable dry-run output, and safety blockers that are not specifically age-based too-new decisions.
- Use fake Homebrew and temporary tap repositories for implementation and verification.

## Plan

- [ ] Read HAG-0005 and this linked plan before implementation to preserve the shared unsafe parser and reporting contract.
- [ ] Treat brew upgrade with the unsafe flag and no package names as an intentional upgrade-all age-gate bypass for packages discovered by the normal outdated and dry-run planning flow.
- [ ] Add a single confirmation prompt before submitting the final upgrade when one or more unsafe-approved packages would be upgraded.
- [ ] Keep final real Homebrew calls as explicit package allowlists; never call bare brew upgrade and never pass the unsafe flag through.
- [ ] Add fake-brew integration coverage for the no-argument unsafe path, including dependencies and mixed formula/cask behavior where supported by existing fixtures.

## Acceptance Criteria

- [ ] Brew upgrade with the unsafe flag and no package names can proceed for too-new packages discovered by the normal plan after dry-run validation.
- [ ] Before submitting the real upgrade, the wrapper prompts once for confirmation when any unsafe-approved package is present.
- [ ] Multi-package unsafe upgrade-all runs still produce exactly one confirmation prompt, not one prompt per package.
- [ ] If the user declines or does not provide the expected confirmation, no final upgrade command is submitted.
- [ ] The no-argument unsafe path bypasses only age-based too-new blockers; unknown-age, unparseable, and unrelated fail-closed safety errors remain blocked unless another explicit unsafe config already allows them.
- [ ] The final upgrade command uses an explicit allowlist of resolved package names and never calls bare brew upgrade.
- [ ] The unsafe flag is stripped from every real Homebrew discovery, dry-run, and final upgrade invocation.
- [ ] User-visible plan output clearly identifies upgrade-all unsafe approvals as intentional age-gate bypasses.

## Verification

- [ ] rbenv exec bundle exec ruby -Ilib -Itest test/arg_parser_test.rb
- [ ] rbenv exec bundle exec ruby -Ilib -Itest test/planner_test.rb
- [ ] rbenv exec bundle exec ruby -Ilib -Itest test/wrapper_integration_test.rb
- [ ] rbenv exec bundle exec rake test

## Outcome

Fill in when completed with implementation summary, commits, verification commands, and results. Move the Kanban card to Completed only after this is filled in and the applicable card checkboxes are checked.
