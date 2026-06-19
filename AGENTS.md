# AGENTS.md

## Project

`homebrew-age-gate` is a PATH-level `brew` wrapper. Its critical guarantee is that `brew upgrade` must only upgrade Homebrew formulae/casks whose Homebrew package definition is old enough under the configured policy.

Default policy: package definitions must be at least 7 days old. Age means the last git committer timestamp for the Homebrew formula/cask definition file, not upstream release age.

## Core Safety Rules

- Never run real `brew update`, real `brew upgrade`, or any command path that can update or upgrade the developer machine's Homebrew formulae/casks while building or testing this project.
- Tests must use fake `brew` executables and temporary git tap repositories.
- Never call bare `brew upgrade` from the wrapper. Always compute an explicit allowlist first.
- Preserve the age-gate guarantee by failing closed when package age cannot be determined, except for explicitly named unsafe config opt-ins.
- Delegate non-upgrade commands to the configured real Homebrew executable unchanged.

## Implementation Notes

- Runtime is Ruby, using stdlib where possible.
- Project Ruby is pinned with `.ruby-version`.
- Bundler is configured through `.bundle/config` to install gems into `vendor/bundle` and avoid shared gems.
- The main shim is `bin/brew`.
- The diagnostic CLI is `bin/homebrew-age-gate`.
- Core code lives under `lib/homebrew_age_gate/`.
- Tests live under `test/` and use Minitest.

## Setup

Use rbenv with the project Ruby version:

```sh
ruby -v
```

Install project gems locally:

```sh
bundle install
```

Run tests through Bundler:

```sh
bundle exec rake test
```

If shell rbenv shims are not active, use:

```sh
rbenv exec bundle install
rbenv exec bundle exec rake test
```

## Testing Expectations

- Prefer `bundle exec rake test` for the full suite.
- New behavior needs tests, especially for fail-closed paths and Homebrew delegation safety.
- Integration tests must route Homebrew calls through the fake-brew harness.
- Any test that inspects upgrade behavior should assert that no real update/upgrade path was invoked.

## GitHub Hygiene

- Do not commit `vendor/bundle/`, IDE metadata, `.DS_Store`, or local personal config.
- Do commit `.bundle/config`, `.ruby-version`, `Gemfile`, and `Gemfile.lock`.
- Keep instructions concise and project-specific; avoid putting personal preferences here.

## Agent skills

### Issue tracker

Issues and implementation tickets live in the Obsidian Kanban board at `~/obsidian_notes/pocock-skills-vault/projects/utilities/homebrew-age-gate/Homebrew Age Gate Kanban.md`; external PRs are not a triage surface. See `docs/agents/issue-tracker.md`.

### Ticket workflow

Create tickets with `new_project_ticket.mjs`; it allocates stable IDs, appends a Kanban card, creates a linked plan in `docs/plans/`, and advances `docs/agents/ticket-sequence.json`. See `docs/agents/ticket-workflow.md`.

When working from a ticket, read the Kanban card and linked plan before implementation. Before calling the ticket complete, verify the Definition of Done or acceptance criteria, add completion notes to the linked plan, move the Kanban card to `Completed`, check applicable TODO/DoD boxes, and re-read the board to confirm the lane.

### Execution plans

Execution plan Markdown files live under stable paths in `docs/plans/`, for example `docs/plans/HAG-0001-initialize-project-workflow.md`. Do not use lane-named status folders for new plans; old `docs/plans/Backlog/`, `docs/plans/In Progress/`, and `docs/plans/Completed/` folders are legacy.

### Triage labels

Use the default five-role triage vocabulary as Obsidian tags configured with Kanban plugin colors: `#needs-triage`, `#needs-info`, `#ready-for-agent`, `#ready-for-human`, and `#wontfix`. Add, remove, or replace those tags in the card's `Description` section. See `docs/agents/triage-labels.md`.

### Domain docs

This is a single-context repo: read root `CONTEXT.md` and `docs/adr/` if they exist. See `docs/agents/domain.md`.
