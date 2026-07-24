# Agent Awareness System - Build Report

## Summary

Built and integrated the Agent Awareness System into AgentGuild, solving the C-grade problem of autonomous agent collaboration by giving every agent a structured inbox for self-directed work discovery.

## What Was Built

### 1. Agent Inbox System
- **Directory**: `context/inbox/` - each agent gets `<slug>.json`
- **Schema**: Structured JSON with `unread` count, `updated` timestamp, and typed `items` array
- **Message Types**: `handoff_incoming`, `conflict_active`, `decision_relevant`

### 2. Auto-Inbox Integration
- **Handoff** (`guild handoff`): Auto-writes to receiver's inbox with delivery status
- **Decide** (`guild decide`): Auto-notifies all affected downstream agents
- **Conflict Detection**: Both in handoff context check and `guild context check` - auto-writes to conflicting agents' inboxes

### 3. New Commands
- **`guild inbox`**: View agent inbox (single agent or all agents, with `--unread` filter)
- **`guild read`**: Mark messages as read (`--agent` required, `--all` optional)
- **`guild resolve`**: Conflict resolution based on decision authority (keyword-matched domains)

### 4. Pipeline Full-Auto
- `guild run --pipeline <name> --path <dir> --yes`: Removes all human prompts, shows inbox summary at end

### 5. Agent Activation Awareness
- **`scripts/agent-prompt.sh`**: Generates activation prompt with inbox context for any agent
- **`docs/Agent激活指南.md`**: User guide for inbox-aware workflows

### 6. Documentation
- **`docs/Agent协作系统详解.md`**: Full architecture document in Chinese for non-technical readers

### 7. Core Library
- **`scripts/lib.sh`**: Added `add_inbox_item()` function for all notification triggers

## Integration Test Results

| Test | Result |
|------|--------|
| Handoff creates inbox notification | PASS |
| `guild inbox --agent` displays inbox | PASS |
| `guild inbox` shows all unread | PASS |
| `guild read --agent --all` marks read | PASS |
| `guild resolve` identifies authority | PASS |
| `guild decide` auto-notifies affected | PASS |
| `agent-prompt.sh` generates prompt | PASS |
| `lint.sh --all` (40 files) | PASS |

## Files Modified
- `scripts/nexus.sh` - Added 3 new commands, auto-notify integration, full-auto pipeline mode
- `scripts/lib.sh` - Added `add_inbox_item()` function

## Files Created
- `scripts/agent-prompt.sh` - Activation prompt generator
- `docs/Agent激活指南.md` - Agent activation guide
- `docs/Agent协作系统详解.md` - Collaboration architecture document
- `.superpowers/sdd/awareness-system-report.md` - This report

## Decision Authority Resolution

`guild resolve` maps topic keywords to authoritative agents:

| Domain Keywords | Authority |
|----------------|-----------|
| api, schema, database, model, auth | backend-architect |
| ui, design, component, layout | ui-designer / creative-director |
| game, mechanic, gameplay | game-designer |
| scope, feature, priority, prd | product-manager |
| security, permission | security-engineer |
