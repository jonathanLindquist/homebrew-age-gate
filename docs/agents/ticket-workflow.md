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

## Plan Files

Plan files are long-lived project history. Keep them after completion.

Plan files should not contain a `Status` field. Use the card's lane on the board for current status.
