# Brew Upgrade Preflight Blockers Handoff

Created: 2026-06-18

## Goal For Next Session

Fix the current `brew upgrade` failure mode where a formula-only upgrade plan has many old-enough root formulae, but Homebrew's frozen dry-run expands that plan to include too-young dependency formulae. The wrapper currently fails closed for the whole batch. We need keep the age-gate guarantee, but salvage the subset of green root formulae that can be upgraded without pulling any blocked package.

Do not weaken the safety invariant:

- never call bare real `brew upgrade`;
- never run real `brew update`;
- never upgrade a package whose definition age is too young or unknown unless explicitly allowed by unsafe config;
- tests must continue to use fake `brew` executables and temp git tap repos.

## Current Branch State

The branch is intentionally dirty from the current feature sequence. Current visible state before this handoff:

```text
 M README.md
 M bin/brew
 M lib/homebrew_age_gate.rb
 M lib/homebrew_age_gate/age_resolver.rb
 M lib/homebrew_age_gate/cli.rb
 M lib/homebrew_age_gate/config.rb
 M lib/homebrew_age_gate/package.rb
 M lib/homebrew_age_gate/planner.rb
 M lib/homebrew_age_gate/report.rb
 M test/age_resolver_test.rb
 M test/config_test.rb
 M test/package_test.rb
 M test/planner_test.rb
 M test/test_helper.rb
 M test/wrapper_integration_test.rb
?? config.json
?? lib/homebrew_age_gate/outdated_reporter.rb
?? lib/homebrew_age_gate/safe_version_resolver.rb
?? pnpm/
?? test/outdated_reporter_test.rb
?? test/report_test.rb
?? test/safe_version_resolver_test.rb
```

The `plans/` directory is ignored by `.gitignore`, so this file will not appear in normal `git status`.

Last full verification before this handoff, after the formula-only default change:

```sh
rbenv exec bundle exec rake test
```

Expected result at that point:

```text
54 runs, 336 assertions, 0 failures, 0 errors, 0 skips
```

## What We Have Done

### Upgrade Guard

- `bin/brew` intercepts `brew upgrade` and delegates non-upgrade commands unchanged.
- The wrapper never calls bare real `brew upgrade`; it computes an explicit allowlist first.
- `Planner` discovers outdated packages, fetches `brew info --json=v2`, computes package definition age, and returns allowed/skipped decisions.
- `CLI.run_brew_wrapper` prints the plan, preflights the explicit allowlist with `brew upgrade --dry-run`, validates the full dry-run expansion, then runs the final explicit upgrade only if the preflight is clean.
- Final upgrade env freezes Homebrew mutation side effects:
  - `HOMEBREW_NO_AUTO_UPDATE=1`
  - `HOMEBREW_NO_INSTALL_CLEANUP=1`
  - `HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1` unless explicitly preserved by unsafe config.

### Formula-Only Bare Upgrade

- A blank `brew upgrade` now defaults discovery to formulae only:
  - current behavior calls `brew outdated --json=v2 --formula` for no-name, no-type upgrade.
- Casks are ignored by blank `brew upgrade`.
- Explicit cask upgrade paths still work through the wrapper, for example `brew upgrade --cask visual-studio-code`.
- The user intends to handle casks manually with `brew cu`, which remains a non-upgrade pass-through command.

### Outdated Report

- `brew outdated` human output is annotated as:

```text
name version: <version> age: <age>d
```

- Date is omitted from the annotated line.
- Age is rounded down to an integer day count.
- Labels and package names are colored by age status; values are not colored.
- For too-young entries, `SafeVersionResolver` may show a historical safe display target:

```text
apidog version: 2.8.34 age: 5d -> version: 2.8.33 age: 12d
```

### SafeVersionResolver

- The expensive history walk was replaced.
- It now asks git for one commit:

```sh
git rev-list -1 --before=<cutoff> <revision> -- <path>
```

- Version inference fails closed unless it can safely infer from:
  1. explicit Homebrew `version`
  2. semantic version in `url`
  3. semantic `tag`
  4. semantic `revision`
- `version_scheme` is intentionally not treated as a package version.

### Config Changes

- `allow_latest_casks` was removed as an active policy knob.
- Legacy `allow_latest_casks` is accepted and ignored for compatibility.
- Casks with `version: latest` are age-gated like any other package.
- `allow_auto_updates_casks` remains the opt-in for casks with `auto_updates true`.

## Latest Failure From Attached Output

The attached `brew upgrade` output showed:

- The root formula plan had many old-enough allowed packages.
- The skipped list correctly included too-young packages.
- The wrapper then failed during frozen dry-run validation:

```text
homebrew-age-gate: refusing to upgrade because the frozen dry-run plan includes blocked packages.
  homebrew/core/libomp age=0.62d definition_commit_date=2026-06-17 reason=too young
  homebrew/core/openexr age=0.45d definition_commit_date=2026-06-17 reason=too young
  homebrew/core/openjdk age=2.20d definition_commit_date=2026-06-15 reason=too young
  homebrew/core/python@3.14 age=4.24d definition_commit_date=2026-06-13 reason=too young
```

This means the initial root allowlist was clean, but Homebrew expanded the explicit formula upgrade dry-run to include additional formulae that were not safe under the age policy. The wrapper did the right fail-closed thing, but the user experience is too coarse: one blocked dependency causes the whole allowed batch to abort.

Current flow that produced the failure:

1. `brew upgrade`
2. `Planner.initial_plan`
3. `brew outdated --json=v2 --formula`
4. `brew info --json=v2 --formula <outdated formulae>`
5. age-gate root formulae
6. build one formula batch from all allowed root formulae
7. run `brew upgrade --formula --dry-run <all allowed formulae>`
8. parse dry-run package names
9. `Planner.validate_planned_names(..., type: :formula)`
10. fail closed because dry-run expansion includes too-young packages

## Desired Behavior

For blank `brew upgrade`:

- Upgrade every old-enough root formula that can be upgraded without pulling any blocked package.
- Do not upgrade too-young root formulae.
- Do not upgrade too-young transitive/dependency formulae.
- If a green root formula requires a blocked dependency, skip that root formula and explain why.
- Continue to fail closed for unparseable dry-run output, unknown package age, missing metadata, unsupported flags, and real Homebrew dry-run failures.

Important distinction: "green root formula" does not mean "always safe to upgrade". If Homebrew requires a too-young dependency for that root formula, that root formula must be deferred too.

## Proposed Fix

Introduce a preflight filtering step that can isolate blocked roots instead of treating the whole batch as all-or-nothing.

Recommended shape:

1. Keep the current whole-batch preflight fast path.
   - If `brew upgrade --formula --dry-run <all allowed roots>` validates cleanly, run the same final batch as today.

2. If the whole-batch preflight contains blocked packages, do not run the final upgrade.
   - Instead, isolate which root formulae cause blocked dry-run expansions.

3. Add a small object to own this behavior, for example `UpgradePreflight` or `PreflightPlanner`.
   - Inputs: `planner`, `runner`, `parsed`, one `UpgradeBatch`.
   - Output: approved batches plus deferred root decisions.

4. Initial implementation can be per-root for clarity.
   - For each allowed root formula, run:

     ```sh
     brew upgrade --formula --dry-run <root>
     ```

   - Parse planned names.
   - Validate those planned names with `Planner.validate_planned_names(parsed, planned_names, type: :formula)`.
   - If validation passes, keep that root in the approved set.
   - If validation finds blocked packages, defer that root and record the blockers.

5. Re-preflight the combined approved roots before final upgrade.
   - This catches interaction effects where two individually safe roots become unsafe together.
   - If the combined approved batch is now clean, run final upgrade for that batch.
   - If it is still blocked, recursively split or fall back to one-root final upgrades.

6. Reporting should distinguish:
   - root packages skipped by initial age gate;
   - root packages deferred because their dry-run expansion includes blocked packages;
   - package names that appeared only as blocked transitive dry-run expansion.

Do not use `--ignore-dependencies`; that would make Homebrew install behavior less truthful and could break formulae.

Do not simply add the dry-run blockers to the final allowlist; that violates the age-gate guarantee.

## Implementation Notes

Current relevant files:

- `lib/homebrew_age_gate/cli.rb`
  - `run_brew_wrapper` owns preflight and final command execution.
  - `UpgradeBatch` owns `preflight_args` and `final_args`.
  - This is currently where the all-or-nothing preflight lives.

- `lib/homebrew_age_gate/planner.rb`
  - `initial_plan` handles root package planning.
  - `validate_planned_names(parsed_args, names, type:)` validates packages from dry-run output.
  - Blank upgrade discovery defaults to `--formula` through `outdated_discovery_flags`.

- `lib/homebrew_age_gate/dry_run_parser.rb`
  - Extracts package names from dry-run output.
  - Keep this as the parser unless the actual Homebrew output exposes a missed format.

- `lib/homebrew_age_gate/report.rb`
  - Add a method for preflight-deferred roots if needed.

- `test/test_helper.rb`
  - Fake brew now supports `dry_run_outputs` keyed by exact command string.
  - Extend this for per-root dry-run scenarios.

## Suggested Tests

Add integration tests before implementing the fix:

1. Whole batch clean remains a single final upgrade.
   - Existing behavior should stay fast and unchanged.

2. Whole batch blocked, one root is safe, one root pulls a young dependency.
   - Initial dry-run for both roots returns both roots plus `youngdep`.
   - Per-root dry-run for `safe-root` returns only safe packages.
   - Per-root dry-run for `blocked-root` returns `blocked-root` plus `youngdep`.
   - Final upgrade runs only `safe-root`.
   - `blocked-root` is reported as deferred.
   - `youngdep` is never in a final upgrade command.

3. All roots blocked.
   - Wrapper exits cleanly without running final upgrade, or exits with a clear refusal depending on the chosen UX.
   - Prefer exit `0` if there were simply no safely upgradeable roots after filtering; prefer exit `1` only for parser/metadata/preflight errors.

4. Combined approved roots re-preflight catches interaction.
   - Two roots are individually clean but combined dry-run pulls a blocked package.
   - The wrapper recursively splits or falls back to one-root final upgrades.

5. Real dry-run failure is still propagated.
   - If fake brew dry-run exits nonzero, do not split around that unless we explicitly decide it is safe.

6. User `--dry-run` mode.
   - Should print only validated approved dry-run output.
   - Should also report deferred roots and blockers.
   - Must not run final upgrade.

## Open Decisions For Next Session

- Exit code when some roots upgrade and some are deferred:
  - recommended: return the final Homebrew status if any final upgrade runs, even if some roots were deferred, and make deferrals visible in stdout/stderr.

- Exit code when all roots are deferred by blocked dependencies:
  - recommended: exit `0` with "no safely upgradeable packages after dependency preflight" if all behavior was successfully analyzed, because this is analogous to an empty allowlist.

- Reporting detail:
  - minimum useful report: `blocked-root deferred because dry-run includes: youngdep, otherdep`.
  - avoid dumping full dependency trees unless needed.

- Performance:
  - use all-at-once preflight first;
  - only fall back to per-root or bisection after the all-at-once preflight fails.

## Next Session Starting Checklist

1. Read `AGENTS.md`.
2. Read this handoff.
3. Run:

   ```sh
   rbenv exec bundle exec rake test
   ```

4. Add failing tests for preflight dependency isolation in `test/wrapper_integration_test.rb`.
5. Extract current preflight logic out of `CLI.run_brew_wrapper` into a focused helper/service.
6. Implement safe subset selection.
7. Re-run focused integration tests, then full suite.
8. Do not run real `brew update` or real `brew upgrade` during the fix.
