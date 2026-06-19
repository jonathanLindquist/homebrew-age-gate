# Ticket Workflow

How agents create and maintain project tickets.

## Source Of Truth

- Visible ticket state lives in the Obsidian Kanban board.
- Current status is the card's lane on the board.
- Longform execution context lives in stable Markdown files under `docs/plans/`.
- Ticket numbering state lives in committed repo file `docs/agents/ticket-sequence.json`.
- Tool-readable workflow config lives in `docs/agents/project-workflow.json`.

Lane-named plan folders such as `docs/plans/Backlog/`, `docs/plans/In Progress/`, and `docs/plans/Completed/` are legacy. Do not create new plan files there.

## Creating Tickets

Use the bundled utility from the repo root:

```bash
node "$HOME/.agents/skills/setup-project-workflow/scripts/new_project_ticket.mjs" \
  --title "Ticket title" \
  --description "Short 1-3 sentence summary." \
  --tag optional-topic
```

Only `--title` is required. Defaults:

- `--project-root`: current directory
- `--lane`: `Backlog`
- `--triage`: `needs-triage`
- `--description`: placeholder summary for the agent to replace

The utility:

- reconciles `docs/agents/ticket-sequence.json` against existing board cards and `docs/plans/`
- blocks exact duplicate titles unless `--allow-duplicate` is passed
- allocates the next `HAG-0000` style ID
- appends the new card to the bottom of the target lane
- creates the linked plan file under `docs/plans/`
- advances `docs/agents/ticket-sequence.json`

## Tags

All tags live in the card's `Description` section.

The utility adds one triage tag by default: `#needs-triage`. Agents may replace it with exactly one of:

- `#needs-triage`
- `#needs-info`
- `#ready-for-agent`
- `#ready-for-human`
- `#wontfix`

Topic tags can be added with repeatable `--tag` flags or edited directly on the card.

## Working Tickets

Before implementing a ticket:

1. Read the Kanban card from the board.
2. Read the linked plan under `docs/plans/`.
3. Identify the requested goal, constraints, TODO checklist, Definition of Done, acceptance criteria, and verification commands.
4. If the card and plan conflict, stop and ask the user which source to update.

## Completing Tickets

A ticket is not complete until tracker closeout is done. Before saying the work is complete:

1. Verify every Definition of Done or acceptance criterion, or explicitly record why an item is not applicable.
2. Add a `## Completion Notes` or `## Outcome` section to the linked plan with implementation summary, commits, verification commands, and results.
3. Move the Kanban card to `Completed`.
4. Check applicable TODO and Definition of Done boxes on the card.
5. Add concise commit and verification bullets to the card's `Implementation Details` when useful.
6. Re-read the board and confirm the card is in `Completed` before the final response.

If closeout is blocked by filesystem permissions, missing board access, or unresolved acceptance criteria, do not call the ticket complete. Report the blocker and leave the card out of `Completed`.

## Plan Files

Plan files are long-lived project history. Keep them after completion.

Plan files should not contain a `Status` field. Use the card's lane on the board for current status.
