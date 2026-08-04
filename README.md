# 🎭 AgentGraph — AI Team Collaboration OS

<p align="center">
  <img src="https://img.shields.io/github/stars/1685yhy/AgentGraph?style=for-the-badge&color=3B82F6" alt="GitHub Stars">
  <img src="https://img.shields.io/github/license/1685yhy/AgentGraph?style=for-the-badge&color=EC4899" alt="MIT License">
  <img src="https://img.shields.io/badge/PRs-welcome-brightgreen?style=for-the-badge&color=22C55E" alt="PRs Welcome">
  <img src="https://img.shields.io/badge/agents-40-3B82F6?style=for-the-badge" alt="40 Agents">
  <img src="https://img.shields.io/badge/Bash_Python3-Bash_3.2++Python3-D946EF?style=for-the-badge" alt="Bash+Python3">
</p>

<p align="center">
  <a href="#what-is-agentgraph">What</a> ·
  <a href="#quick-start-5-minutes">Quick Start</a> ·
  <a href="#core-concepts">Concepts</a> ·
  <a href="#command-reference">Commands</a> ·
  <a href="#typical-workflows">Workflows</a> ·
  <a href="#quality-gates">Gates</a> ·
  <a href="#troubleshooting">Troubleshooting</a> ·
  <a href="README_zh-CN.md">中文</a>
</p>

---

## What Is AgentGraph

**AgentGraph is a collaboration system where 40 AI Agents work together like a real team, driven by a Graph execution engine.**

It solves the problem of "AI agents making contradictory decisions" by providing structured handoffs, automated quality gates, and conflict detection.

Two things make it unique:

1. **40 opinionated AI Agents** — Each has a real personality, stance, blind spots, and domain expertise. Not a template with a swapped name.
2. **Graph Collaboration Engine** — Agents pass work through standardized handoffs. The system automatically checks completeness, detects conflicting decisions, orchestrates pipelines, and generates changelogs.

> In one sentence: You write the PRD, AgentGraph handles the rest — from requirements to deployment — with automated quality checks at every step.

Beyond the 40 agents and the Graph engine, AgentGraph has grown a full self-built capability chain: **Classifier → Templates → MCP Adapter → Custom Runtime**. A natural-language task is first classified into one of 18 product types, then scaffolded from one of 18 project templates; an MCP server exposes 23 tools to any AI host (Claude Code, Cursor, etc.); finally a custom runtime plugs into real LLM backends (Anthropic / OpenAI / DeepSeek) and drives agents through the full delivery chain — classify → plan → execute → review → fix — with real API calls from requirements to a playable prototype.

---

## Quick Start (5 Minutes)

### 1. Install

```bash
# Clone the repo
git clone https://github.com/1685yhy/AgentGraph.git
cd AgentGraph

# Convert agents to your AI tool format
bash scripts/convert.sh

# Install into Claude Code
bash scripts/install.sh --tool claude-code

# Or install into all detected tools
bash scripts/install.sh
```

### 2. Your First Handoff

A handoff is when one Agent passes deliverables to another.

```bash
# Create a directory with your PRD
mkdir -p /tmp/my-project
echo "# My Project PRD" > /tmp/my-project/prd.md

# PM hands off to frontend engineer
./guild handoff --from product-manager --to frontend-engineer --path /tmp/my-project
```

Example output:
```
Creating handoff #1: product-manager → frontend-engineer
  Status: incomplete
  Completeness: 1/3 items provided
  [!!] Missing 2 items:
       - Design spec or prototype link
       - Acceptance criteria
```

The system tells you what's missing. Add the files and handoff again.

### 3. Verify Deliverable Quality

```bash
# Verify files in handoff #1's directory
./guild verify --handoff 1

# Or verify a single file by type
./guild verify --type html --file ./index.html
```

### 4. Run Quality Gates

```bash
# Run all 5 quality gates on handoff #1
./guild gate --handoff 1
```

All gates must pass before the receiver can accept.

### 5. Accept the Handoff

```bash
# The receiver formally accepts (runs all gates automatically)
./guild accept --handoff 1 --as frontend-engineer
```

### 6. View All Handoffs

```bash
./guild status
```

---

## Core Concepts

### Agent

40 built-in AI Agents across 11 divisions:

| Division | Count | Agents |
|----------|-------|--------|
| Engineering | 7 | Frontend Engineer, Backend Architect, DevOps, AI Engineer, Mobile Dev, DBA, Code Reviewer |
| Product | 4 | PM, UX Researcher, Data Analyst, Tech Writer |
| Design | 4 | UI Designer, Brand Guardian, Interaction Designer, Creative Director |
| Testing | 3 | QA Engineer, Performance Tester, Accessibility Auditor |
| Marketing | 4 | Growth Hacker, Content Creator, Social Media Strategist, SEO |
| Security | 1 | Security Engineer |
| Project Mgmt | 1 | Project Manager |
| Sales | 2 | Sales Engineer, Deal Strategist |
| Support | 1 | Customer Support |
| Finance | 1 | Financial Analyst |
| Game Dev | 12 | Game Designer, Level Designer, Narrative Designer, Game Programmer, Unity/Unreal Devs, Tech Artist, Game UI, Audio, Monetization, Producer, QA |

Each Agent has 13 sections: provocative opinion, hard rules, conflict preferences, blind spot declarations, decision authority, and collaboration contracts.

### Handoff

One Agent passes deliverables to another. On handoff, the system automatically:

- Checks if all required items are present
- Validates file quality (syntax, encoding, structure)
- Detects relevant decisions and potential conflicts
- Notifies the receiver via their inbox

### Graph Engine

A directed-graph execution engine supporting:

- **Sequential** — A must finish before B starts
- **Parallel** — Independent tasks execute simultaneously
- **Conditional branches** — Pass/fail determines the next step
- **Loops** — Failed QA goes back for fixes, then retests
- **Checkpoint resume** — Pick up where you left off after interruption

### Quality Gates

5 gates that must pass before a handoff can be accepted:

1. completeness — All required deliverables present
2. syntax — All files pass syntax validation
3. behavior — Behavioral patterns exist (event binding, error handling)
4. playability — UX checks (tutorial, audio init, mobile readiness)
5. agent-standards — Matches downstream Agent's success metrics

### Feedback

Found a bug or improvement during a handoff? Record feedback linked to the handoff. When fixed, mark it resolved.

---

## Command Reference

All commands run through `./guild` (symlink to `scripts/nexus.sh`).

| Command | Description | Example |
|---------|-------------|---------|
| `guild handoff` | Create a handoff (Agent A → Agent B) | `guild handoff --from pm --to backend --path ./prd/` |
| `guild check` | Check handoff completeness | `guild check --handoff 1` |
| `guild status` | List all handoffs | `guild status` |
| `guild status --agent <name>` | Filter by agent | `guild status --agent frontend-engineer` |
| `guild status --status <s>` | Filter by status | `guild status --status incomplete` |
| `guild accept` | Accept a handoff (auto-runs gates) | `guild accept --handoff 1 --as frontend-engineer` |
| `guild verify` | Validate deliverable quality | `guild verify --handoff 1` |
| `guild verify --type html --file <path>` | Validate a single file by type | `guild verify --type html --file ./index.html` |
| `guild verify --path <dir>` | Validate an entire directory | `guild verify --path ./my-project/` |
| `guild test` | Run behavioral tests | `guild test --handoff 1` |
| `guild test --file <path>` | Test a single file | `guild test --file ./game.html` |
| `guild test --generate` | Auto-generate tests from an Agent | `guild test --generate --from-agent game-designer --file ./game.html` |
| `guild feedback` | Record bug or improvement | `guild feedback --handoff 1 --type bug --summary "Button unresponsive"` |
| `guild feedback --list` | List all feedback | `guild feedback --list` |
| `guild feedback --fix fb-001 --handoff 2` | Mark feedback as fixed | `guild feedback --fix fb-001 --handoff 2` |
| `guild changelog` | Generate changelog | `guild changelog` |
| `guild changelog --since v0.1.0` | Changelog from a version | `guild changelog --since v0.1.0` |
| `guild list` | List handoff records | `guild list` |
| `guild list --contracts` | List collaboration contracts | `guild list --contracts` |
| `guild decide` | Record a decision (ADR pattern) | `guild decide --agent backend --type api-design --topic "API format" --summary "Unified wrapper"` |
| `guild context show` | View decision graph | `guild context show` |
| `guild context check` | Check for decision conflicts | `guild context check` |
| `guild run` | Run a graph with the runtime (real LLM drives the whole chain) | `guild run --graph feature-dev --task "Build an admin system"` |
| `guild run --graph <name> --task "<desc>" --yes` | Auto mode (skip confirmations) | `guild run --graph game-mvp --task "Make a snake game" --yes` |
| `guild run-agent` | Run a single agent with the runtime (real LLM) | `guild run-agent game-designer "Design a core loop" --upstream 1` |
| `guild watch` | Watch a project directory and trigger execution on changes | `guild watch --timeout 120` |
| `guild graph run` | Execute a graph | `guild graph run --graph game-mvp --path ./my-game/` |
| `guild graph status` | View graph execution status | `guild graph status game-mvp` |
| `guild graph show <name>` | Display graph structure | `guild graph show game-mvp` |
| `guild graph list` | List available graph definitions | `guild graph list` |
| `guild graph resume` | Resume a graph from checkpoint | `guild graph resume --graph game-mvp --path ./my-game/` |
| `guild inbox` | View all agent inboxes | `guild inbox` |
| `guild inbox --agent <name>` | View a specific agent's inbox | `guild inbox --agent frontend-engineer` |
| `guild inbox --agent <name> --unread` | Unread only | `guild inbox --agent backend-architect --unread` |
| `guild read --agent <name>` | Mark inbox as read | `guild read --agent frontend-engineer` |
| `guild resolve --topic <topic>` | Resolve conflicts by authority | `guild resolve --topic "API response format"` |
| `guild gate` | Run quality gates on a handoff | `guild gate --handoff 1` |
| `guild gate --handoff 1 --gate <name>` | Run one specific gate | `guild gate --handoff 1 --gate completeness` |
| `guild gate --list` | List all quality gates | `guild gate --list` |

> **Shortcuts**: Agent names support abbreviations, partial matching, and case-insensitive input. E.g., `pm` resolves to `product-manager`, `backend` to `backend-architect`.

---

## Typical Workflows

### Scenario A: Feature Dev from PRD to Launch (Graph-Driven)

Full feature development from requirements to release.

```bash
mkdir -p /tmp/feature-x
# Put your PRD, design specs, etc. in this directory

# Run the graph — it handles everything
./guild graph run --graph feature-dev --path /tmp/feature-x
```

The built-in `feature-dev` graph (`graphs/feature-dev.yml`) runs:
- `define` (PM) → `design` (UI designer) → `build-frontend` + `build-backend` (parallel) → `test` (QA) → pass: `approve` / fail: `fix` → retest

### Scenario B: Bug Fix Iteration (Feedback Loop)

For continuous iteration, collecting feedback, fixing, and verifying.

```bash
# 1. PM hands off to frontend
./guild handoff --from pm --to frontend --path /tmp/feature-x

# 2. QA records a bug
./guild feedback --handoff 1 --type bug --severity high \
  --summary "Submit button unresponsive on mobile"

# 3. Fix and create new handoff
./guild handoff --from frontend --to qa --path /tmp/feature-x

# 4. Mark feedback as fixed
./guild feedback --fix fb-001 --handoff 2

# 5. View changelog
./guild changelog
```

Or use the `iterate` graph:

```bash
./guild graph run --graph iterate --path /tmp/my-project
```

### Scenario C: Game MVP (Game-Dev Pipeline)

From concept to playable prototype.

```bash
mkdir -p /tmp/my-game

# Graph mode: parallel art + code + UI + audio
./guild graph run --graph game-mvp --path /tmp/my-game

# Or runtime mode: a real LLM drives the whole graph automatically
./guild run --graph game-mvp --task "Make a snake game" --yes
```

The `game-mvp` graph runs: concept → art (parallel), code (parallel), UI (parallel), audio (parallel) → integration → QA → pass: ship / fail: fix → retest

---

## Quality Gates

Quality Gates are AgentGraph's core quality system. Every `guild accept` runs all 5 gates automatically.

| # | Gate | What It Checks | Failure Example |
|---|------|---------------|-----------------|
| 1 | **completeness** | All required deliverables present | Backend needs API contract, directory has none |
| 2 | **syntax** | Files pass syntax validation (per type) | HTML missing `</script>` closing tag |
| 3 | **behavior** | Event bindings, guards, error handling exist | No event handlers found in HTML |
| 4 | **playability** | Tutorial, audio init, core interaction, mobile | Missing viewport meta tag |
| 5 | **agent-standards** | Matches receiver Agent's success metrics | QA requires Chinese text, HTML is all English |

### Manual Gate Usage

```bash
# All 5 gates
./guild gate --handoff 1

# Single gate
./guild gate --handoff 1 --gate completeness
./guild gate --handoff 1 --gate syntax

# List gates
./guild gate --list
```

### Gate Flow

```
handoff → verify (optional) → gate (MUST pass all 5) → accept
```

If any gate fails, `guild accept` refuses to proceed.

---

## Troubleshooting

**Q: `./guild` says command not found**

It's a symlink to `scripts/nexus.sh`. Either use `bash scripts/nexus.sh` or make sure the symlink is executable:

```bash
bash scripts/nexus.sh handoff --from pm --to backend --path ./
```

**Q: "Unknown agent" error**

Agent names support abbreviations but must map to a registered slug:

```bash
# See all agents
cat guild.config.json | grep -A1 '"slug"'

# Valid shortcuts: pm → product-manager, backend → backend-architect
```

**Q: What exactly is missing from my handoff?**

```bash
./guild check --handoff 1
# Shows the full artifacts list — items with "status: missing" are what you need
```

**Q: How do I see all handoffs?**

```bash
./guild status
./guild list   # same thing
```

**Q: Gate keeps failing, how do I debug?**

Run individual gates to find the problem:

```bash
./guild gate --handoff 1 --gate syntax
./guild gate --handoff 1 --gate completeness
```

Fix the issue, create a new handoff, then run gates again.

**Q: Graph execution was interrupted. How do I resume?**

```bash
./guild graph resume --graph game-mvp --path /tmp/my-game/

# Check current progress
./guild graph status game-mvp
```

**Q: How do I know which Agent has authority on a topic?**

```bash
# View decision graph
./guild context show

# Resolve conflicts — the system analyzes decision weights automatically
./guild resolve --topic "API format"
```

---

## Project Structure

```
AgentGraph/
├── agents/                    40 Agent definition files (Markdown)
│   ├── engineering/           7 agents
│   ├── product/               4 agents
│   ├── design/                4 agents
│   ├── testing/               3 agents
│   ├── marketing/             4 agents
│   ├── security/              1 agent
│   ├── project-management/    1 agent
│   ├── sales/                 2 agents
│   ├── support/               1 agent
│   ├── finance/               1 agent
│   └── game-development/      10 agents
├── scripts/                   Core scripts
│   ├── nexus.sh               Main CLI entry point
│   ├── runtime/               Custom runtime engine (v0.6a)
│   │   ├── run.sh             Runtime orchestrator (guild run)
│   │   ├── agent-runner.sh    Single-agent executor (real LLM)
│   │   ├── llm-backend.js     LLM backend adapter (Anthropic/OpenAI/DeepSeek)
│   │   └── event-bus.sh       Event bus (guild watch)
│   ├── mcp-server.js          MCP server (23 tools)
│   ├── graph-generator.sh     Classifier + plan generator (18 product types)
│   ├── research-engine.sh     Research & ideation engine (guild research/ideate)
│   ├── graph-engine.sh        Graph execution engine
│   ├── modules/               Modular command implementations
│   ├── test-runner.sh         Behavioral test engine
│   ├── runtime-test.sh        Browser runtime tests
│   ├── self-test.sh           System self-test
│   ├── ci-test.sh             CI self-test
│   ├── lib.sh                 Shared function library
│   ├── lint.sh                Agent quality checks
│   ├── convert.sh             Format conversion (agent.md → tool format)
│   ├── install.sh             Install agents into AI tools
│   └── agent-prompt.sh        Agent prompt utility
├── contracts/                 Collaboration contracts
│   └── guild-contracts.yml    All agent deliverable/requirement matrix
├── pipelines/                 Pipeline definitions (YAML)
│   ├── feature-dev.yml        Feature development
│   ├── game-mvp.yml           Game MVP development
│   ├── iterate.yml            Product iteration
│   └── startup-mvp.yml        Startup MVP development
├── graphs/                    Graph definitions (YAML, 5 total)
│   ├── feature-dev.yml        Feature dev graph
│   ├── game-mvp.yml           Game MVP graph
│   ├── iterate.yml            Product iteration graph
│   ├── research-report.yml    Research report graph
│   └── unity-game.yml         Unity game graph
├── templates/                 18 project templates (for guild init)
│   ├── admin-system/          Admin system template
│   ├── web-app/               Web application template
│   └── ...                    (guild init --template <name> <dir>)
├── context/memory/            Runtime Memory Store (auto-created, gitignored)
├── integrations/              Tool-specific output (auto-generated)
├── demos/                     Handoff walkthrough scenarios
├── docs/                      Documentation
├── website/                   Project website
├── guild → scripts/nexus.sh   CLI entry
└── guild.config.json          40 Agent + 4 tool registry
```

---

## Supported Tools

| Tool | Install Command |
|------|----------------|
| **Claude Code** | `bash scripts/install.sh --tool claude-code` |
| **Cursor** | `bash scripts/install.sh --tool cursor` |
| **GitHub Copilot** | `bash scripts/install.sh --tool copilot` |
| **Windsurf** | `bash scripts/install.sh --tool windsurf` |

Run `bash scripts/convert.sh` first to generate tool-specific files.

---

## Version History

- **v0.3 — Classifier**: natural-language classifier identifying 18 product types
- **v0.4 — Templates**: 18 project template scaffolds (doc + engineering types)
- **v0.5 — MCP**: MCP adapter exposing 23 AgentGraph tools to any AI host
- **v0.6a — Runtime Engine**: custom runtime (llm-backend / agent-runner / event-bus / run) wired to real LLMs

---

## License

MIT — use, modify, distribute freely.

---

<p align="center">
  <sub>Built with conviction, not consensus.</sub>
</p>
