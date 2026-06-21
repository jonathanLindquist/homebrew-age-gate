---
kanban-plugin: board
---

## Backlog

- [ ] # <span style="color: #77ccd5">ABC-0001 Ticket title</span>

    ## Description

    #needs-triage #optional-topic

    1-3 sentence summary.

    ## Implementation Details

    - Ticket: ABC-0001
    - Plan: docs/plans/ABC-0001-ticket-title.md

    ## TODO Checklist
    Items to implement:

    - [ ] First ticket-specific implementation step

    ## Acceptance Criteria

    - [ ] Observable ticket-specific result required for completion

    ## Verification

    Checks to run:

    - [ ] Ticket-specific command or review check

## In Progress

## Completed


%% kanban:settings
```
{
  "kanban-plugin": "board",
  "list-collapse": [
    false,
    false,
    false
  ],
  "lane-width": 400,
  "move-tags": true,
  "tag-action": "kanban",
  "tag-colors": [
    {
      "tagKey": "#needs-triage",
      "color": "#111827",
      "backgroundColor": "#f59e0b"
    },
    {
      "tagKey": "needs-triage",
      "color": "#111827",
      "backgroundColor": "#f59e0b"
    },
    {
      "tagKey": "#needs-info",
      "color": "#0f172a",
      "backgroundColor": "#38bdf8"
    },
    {
      "tagKey": "needs-info",
      "color": "#0f172a",
      "backgroundColor": "#38bdf8"
    },
    {
      "tagKey": "#ready-for-agent",
      "color": "#ffffff",
      "backgroundColor": "#8b5cf6"
    },
    {
      "tagKey": "ready-for-agent",
      "color": "#ffffff",
      "backgroundColor": "#8b5cf6"
    },
    {
      "tagKey": "#ready-for-human",
      "color": "#500724",
      "backgroundColor": "#f472b6"
    },
    {
      "tagKey": "ready-for-human",
      "color": "#500724",
      "backgroundColor": "#f472b6"
    },
    {
      "tagKey": "#wontfix",
      "color": "#ffffff",
      "backgroundColor": "#ef4444"
    },
    {
      "tagKey": "wontfix",
      "color": "#ffffff",
      "backgroundColor": "#ef4444"
    },
    {
      "tagKey": "#cli",
      "color": "#312e81",
      "backgroundColor": "#a5b4fc"
    },
    {
      "tagKey": "cli",
      "color": "#312e81",
      "backgroundColor": "#a5b4fc"
    },
    {
      "tagKey": "#sync",
      "color": "#064e3b",
      "backgroundColor": "#6ee7b7"
    },
    {
      "tagKey": "sync",
      "color": "#064e3b",
      "backgroundColor": "#6ee7b7"
    },
    {
      "tagKey": "#tests",
      "color": "#7c2d12",
      "backgroundColor": "#fdba74"
    },
    {
      "tagKey": "tests",
      "color": "#7c2d12",
      "backgroundColor": "#fdba74"
    },
    {
      "tagKey": "#obsidian",
      "color": "#581c87",
      "backgroundColor": "#d8b4fe"
    },
    {
      "tagKey": "obsidian",
      "color": "#581c87",
      "backgroundColor": "#d8b4fe"
    },
    {
      "tagKey": "#kanban",
      "color": "#164e63",
      "backgroundColor": "#67e8f9"
    },
    {
      "tagKey": "kanban",
      "color": "#164e63",
      "backgroundColor": "#67e8f9"
    },
    {
      "tagKey": "#triage",
      "color": "#451a03",
      "backgroundColor": "#fbbf24"
    },
    {
      "tagKey": "triage",
      "color": "#451a03",
      "backgroundColor": "#fbbf24"
    }
  ]
}
```
%%
