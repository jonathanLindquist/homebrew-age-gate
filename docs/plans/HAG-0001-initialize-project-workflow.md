# HAG-0001 Initialize Project Workflow

- Ticket: HAG-0001
- Board: derived from `PROJECT_WORKFLOW_OBSIDIAN_VAULT` and this repo path relative to `$HOME`
- Card: HAG-0001 Initialize Project Workflow
- Created: 2026-06-19

## Summary

Set up repo-local agent instructions, Obsidian Kanban issue tracking, ticket numbering, stable repo plan files, and domain documentation conventions for this project.

## Context

This project uses an Obsidian Kanban board for visible ticket state and stores long-lived execution plans in stable Markdown files under `docs/plans/`.

## Plan

- [x] Create or update `AGENTS.md`
- [x] Create or update `CLAUDE.md`
- [x] Create `docs/agents/*`
- [x] Create `docs/agents/project-workflow.json`
- [x] Create `docs/agents/ticket-sequence.json`
- [x] Create `.env.example` and ignored `.env` local vault config
- [x] Create `docs/agents/kanban-template.md`
- [x] Create `docs/plans/`
- [x] Create ticket start and closeout workflow instructions
- [x] Create Obsidian Kanban board
- [x] Configure Kanban tag colors

## Verification

- [x] Board path mirrors the project path relative to home
- [x] Vault root is stored in ignored `.env`
- [x] `.env.example` documents `PROJECT_WORKFLOW_OBSIDIAN_VAULT`
- [x] Ticket sequence state is initialized
- [x] Bootstrap card links to this plan
- [x] Generated ticket workflow includes deterministic closeout rules
- [x] Triage tags are Obsidian tags
- [x] Kanban tag colors are present in board/template settings

## Outcome

Project workflow initialized and refreshed to the current setup-project-workflow generated pattern.
