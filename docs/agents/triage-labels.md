# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those roles to the strings used in this repo's issue tracker.

| Skill role | Obsidian tag | Kanban color | Meaning |
| --- | --- | --- | --- |
| `needs-triage` | `#needs-triage` | Amber | Maintainer needs to evaluate this issue |
| `needs-info` | `#needs-info` | Blue | Waiting on reporter for more information |
| `ready-for-agent` | `#ready-for-agent` | Violet | Fully specified, ready for an agent |
| `ready-for-human` | `#ready-for-human` | Pink | Requires human implementation |
| `wontfix` | `#wontfix` | Red | Will not be actioned |

When a skill mentions a role, use the corresponding Obsidian tag from this table. In the Obsidian Kanban board, record tags in the ticket's `Description` section.

## Kanban Tag Lines

Use these exact tags:

```markdown
#needs-triage
#needs-info
#ready-for-agent
#ready-for-human
#wontfix
```

The colors are configured in the Obsidian Kanban plugin's vault-level `tag-colors` setting and in board-local Kanban settings, so these tags render consistently across Kanban boards in the vault.
