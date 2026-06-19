# Issue Tracker: Obsidian Kanban

Issues, implementation tickets, and project task state for this repo live in an Obsidian Kanban board.

## Board

- Vault: `~/obsidian_notes/pocock-skills-vault`
- Board: `~/obsidian_notes/pocock-skills-vault/projects/utilities/homebrew-age-gate/Homebrew Age Gate Kanban.md`
- Template: `~/obsidian_notes/pocock-skills-vault/Z - Templates/Kanban Template.md`
- Project path: `~/projects/utilities/homebrew-age-gate`

The board path mirrors the project path relative to the home directory: `projects/utilities/homebrew-age-gate`.

## Lanes

- `Backlog` means not started.
- `In Progress` means actively being worked.
- `Completed` means done.

Move a ticket by moving its full markdown card between these lane headings.

## Ticket Format

When a skill says "publish to the issue tracker", create a new Kanban card in `Backlog` using the format from the vault's `Kanban Template.md`.

Each ticket should include:

- title line using the Kanban checkbox/card format
- `## Description`
- relevant tags such as `#homebrew-age-gate`, `#cli`, `#sync`, `#tests`, or `#2026`
- `## Implementation Data`
- a triage tag line using one of the tags from `docs/agents/triage-labels.md`
- `## TODO Checklist`
- `## Definition of Done`

For implementation work, record concrete evidence in `Implementation Data`: commit SHAs, changed files, commands run, relevant paths, decisions made, and verification results.

Use triage labels as Obsidian tags, for example:

```markdown
- Triage: #ready-for-agent
```

The Kanban plugin's vault-level `tag-colors` settings define the visual colors for these tags across all Kanban boards in the vault.

## Fetching Tickets

When a skill says "fetch the relevant ticket", read the referenced card in the Obsidian Kanban board. The user may name the card title, paste a section, or provide the board path.

## Pull Requests

External PRs are not currently treated as a request surface for this project. Track requested work in the Obsidian Kanban board unless the user explicitly says otherwise.
