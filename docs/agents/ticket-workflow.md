# Ticket Workflow

How agents create and maintain project tickets.

## Source Of Truth

- Visible ticket state lives in the Obsidian Kanban board.
- Current status is the card's lane on the board.
- Longform execution context lives in stable Markdown files under `docs/plans/`.
- Ticket numbering state lives in committed repo file `docs/agents/ticket-sequence.json`.
- Tool-readable workflow config lives in `docs/agents/project-workflow.json`.
- Local vault root lives in ignored `.env` as `PROJECT_WORKFLOW_OBSIDIAN_VAULT`.

Lane-named plan folders such as `docs/plans/Backlog/`, `docs/plans/In Progress/`, and `docs/plans/Completed/` are legacy. Do not create new plan files there.

## Creating Tickets

Use the bundled utility from the repo root:

```bash
node "$HOME/.agents/skills/setup-project-workflow/scripts/new_project_ticket.mjs" \
  --title "Ticket title" \
  --description "Short 1-3 sentence summary." \
  --todo "First implementation step." \
  --acceptance "Observable result required for completion." \
  --verification "Command or review step that proves completion." \
  --tag optional-topic
```

Only `--title` is required. Defaults:

- `--project-root`: current directory
- `--lane`: `Backlog`
- `--triage`: `needs-triage`
- `--description`: placeholder summary for the agent to replace
- `--todo`, `--acceptance`, `--verification`: explicit placeholders for the agent to replace

`--triage ready-for-agent` requires `--description` plus at least one `--todo`, `--acceptance`, and `--verification` field. Leave incomplete tickets as `#needs-triage`.

The utility:

- reconciles `docs/agents/ticket-sequence.json` against existing board cards and `docs/plans/`
- blocks exact duplicate titles unless `--allow-duplicate` is passed
- allocates the next `HAG-0000` style ID
- appends the new card to the bottom of the target lane with ticket-specific checklist sections
- creates the linked plan file under `docs/plans/` with the same TODO, acceptance, and verification items
- advances `docs/agents/ticket-sequence.json`

## Updating Ticket Status

Use the status utility whenever implementation state changes:

```bash
node "$HOME/.agents/skills/setup-project-workflow/scripts/update_project_ticket.mjs" \
  --ticket "HAG-0002" \
  --lane "In Progress" \
  --note "Started implementation after updating code."
```

Rules:

- After changing implementation code for a ticket, move the card to `In Progress` unless it is already there.
- If acceptance criteria are complete, move the card to `Completed` with `--complete`.
- Status lives in the board lane, not in the linked plan filename or a plan `Status` field.
- The utility appends progress or completion notes to the linked plan when `--note` is provided.

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
3. Identify the requested goal, constraints, TODO checklist, acceptance criteria, and verification commands.
4. If the card and plan conflict, stop and ask the user which source to update.

After changing code for a ticket, run `update_project_ticket.mjs --ticket <id> --lane "In Progress"` before continuing unless the ticket is already complete.

## Completing Tickets

A ticket is not complete until tracker closeout is done. Before saying the work is complete:

1. Verify every acceptance criterion and verification item, or explicitly record why an item is not applicable.
2. Add completion notes to the linked plan with implementation summary, commits, verification commands, and results.
3. Run `update_project_ticket.mjs --ticket <id> --lane "Completed" --complete --note "<summary>"`.
4. Check applicable TODO, Acceptance Criteria, and Verification boxes on the card.
5. Add concise commit and verification bullets to the card's `Implementation Details` when useful.
6. Re-read the board and confirm the card is in `Completed` before the final response.

If closeout is blocked by filesystem permissions, missing board access, or unresolved acceptance criteria, do not call the ticket complete. Report the blocker and leave the card out of `Completed`.

## Plan Files

Plan files are long-lived project history. Keep them after completion.

Plan files should not contain a `Status` field. Use the card's lane on the board for current status.
