# Issue Tracker: Obsidian Kanban

Issues, implementation tickets, and project task state for this repo live in an Obsidian Kanban board.

## Board

- Vault: `~/obsidian_notes/pocock-skills-vault`
- Board: `~/obsidian_notes/pocock-skills-vault/projects/utilities/homebrew-age-gate/Homebrew Age Gate Kanban.md`
- Template: `~/obsidian_notes/pocock-skills-vault/Z - Templates/Kanban Template.md`
- Project path: `~/projects/utilities/homebrew-age-gate`
- Tool config: `docs/agents/project-workflow.json`
- Ticket sequence: `docs/agents/ticket-sequence.json`
- Execution plans: `docs/plans/*.md`

The board path mirrors the project path relative to the home directory: `projects/utilities/homebrew-age-gate`.

## Lanes

- `Backlog` means not started.
- `In Progress` means actively being worked.
- `Completed` means done.

The current ticket status is the card's lane on the Obsidian board. Do not encode current status in the plan file path.

## Ticket Format

When a skill says "publish to the issue tracker", use the ticket utility documented in `docs/agents/ticket-workflow.md`. It creates the Kanban card and linked plan file together.

Each ticket card should stay short and include:

- title line using the Kanban checkbox/card format, with the stable ticket ID first
- `## Description` with all tags and a 1-3 sentence summary
- `## Implementation Details` with `Ticket` and `Plan` bullets
- `## TODO Checklist`
- `## Definition of Done`

Use this shape:

```markdown
- [ ] # <span style="color: #77ccd5">HAG-0002 Ticket title</span>

    ## Description

    #needs-triage #optional-topic

    1-3 sentence summary.

    ## Implementation Details

    - Ticket: HAG-0002
    - Plan: docs/plans/HAG-0002-ticket-title.md
```

For implementation work, record longform context, plans, and verification notes in the linked `docs/plans/*.md` file. Keep the card scannable.

## Fetching Tickets

When a skill says "fetch the relevant ticket", read the referenced card in the Obsidian Kanban board and then read its linked plan file under `docs/plans/`.

## Pull Requests

External PRs are not currently treated as a request surface for this project. Track requested work in the Obsidian Kanban board unless the user explicitly says otherwise.
