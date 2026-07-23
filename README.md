# AgentGuild

<p align="center">
  <img src="https://img.shields.io/github/stars/agentguild/agentguild?style=for-the-badge&color=3B82F6" alt="GitHub Stars">
  <img src="https://img.shields.io/github/license/agentguild/agentguild?style=for-the-badge&color=EC4899" alt="MIT License">
  <img src="https://img.shields.io/badge/PRs-welcome-brightgreen?style=for-the-badge&color=22C55E" alt="PRs Welcome">
  <img src="https://img.shields.io/badge/agents-12-3B82F6?style=for-the-badge" alt="12 Agents">
</p>

<p align="center">
  <strong>A guild of AI agents for software development — each with real personality, strong opinions, and clear boundaries.</strong>
</p>

<p align="center">
  <a href="#-quick-start">Quick Start</a> ·
  <a href="#-agent-roster">Agents</a> ·
  <a href="#-what-makes-agentguild-different">Why AgentGuild</a> ·
  <a href="#-supported-tools">Supported Tools</a> ·
  <a href="#-project-structure">Structure</a> ·
  <a href="#-contributing">Contributing</a> ·
  <a href="README_zh-CN.md">中文</a>
</p>

---

## What is AgentGuild?

AgentGuild is a **curated roster of 12 AI agents** purpose-built for software development teams. Each agent is a detailed markdown file defining a specialized role — complete with identity, expertise, and most importantly, **opinions**.

Unlike generic AI agent frameworks that give you empty templates, AgentGuild agents come with:

- **Contrarian Takes** — professional opinions that go against mainstream consensus
- **Conflict Preferences** — when they will push back, say no, or escalate
- **Blind Spots** — what they know they are bad at and when to ask for help
- **Decision Authority** — clear ownership boundaries in multi-agent collaboration

AgentGuild works with **Claude Code**, **Cursor**, **GitHub Copilot**, and **Windsurf**. Install the agents you need, and your AI coding tool will understand exactly which expert is responding, what they care about, and what decisions they own.

---

## How is this different from agency-agents?

[agency-agents](https://github.com/ai-hero/agency-agents) pioneered the concept of system-prompt-based AI agents. AgentGuild builds on that foundation with a fundamentally different philosophy:

| Dimension | agency-agents | AgentGuild |
|-----------|--------------|------------|
| **Philosophy** | Quantity — broad coverage | Quality — curated, opinionated |
| **Personality** | Generic role descriptions | Real contrarian opinions and personality |
| **Conflict** | No conflict defined | Explicit disagreement boundaries between agents |
| **Blind Spots** | Not addressed | Honest self-assessment of limitations |
| **Decision Authority** | Not defined | Clear who has final say on what |
| **Format Support** | Claude Code only | Claude Code, Cursor, Copilot, Windsurf |
| **Agent Count** | Many, varying quality | 12 carefully crafted agents |

AgentGuild is **not a fork** of agency-agents. It is a next-generation approach where every agent in the guild has real personality, strong professional opinions, and clear boundaries about what they will and will not do.

---

## Agent Roster

### Engineering Division

| Emoji | Agent | Description | Difficulty |
|-------|-------|-------------|------------|
| 🖥️ | Frontend Engineer | UI architecture, performance optimization, and design-system engineering | Advanced |
| 🗄️ | Backend Architect | API design, data modeling, authentication, and service reliability | Advanced |
| 🚀 | DevOps Engineer | CI/CD, infrastructure, monitoring, incident response, and reliability | Advanced |
| 🤖 | AI Engineer | Model selection, prompt architecture, evaluation, and AI feature design | Advanced |

### Product Division

| Emoji | Agent | Description | Difficulty |
|-------|-------|-------------|------------|
| 📋 | Product Manager | Problem definition, prioritization, and scope management | Intermediate |
| 🔍 | UX Researcher | User research methodology, insight validation, and behavioral analysis | Intermediate |
| 📊 | Data Analyst | Metric definition, statistical analysis, and evidence-based decision support | Intermediate |
| 📝 | Tech Writer | API documentation, naming consistency, and information architecture | Beginner |

### Design Division

| Emoji | Agent | Description | Difficulty |
|-------|-------|-------------|------------|
| 🎨 | UI Designer | Visual design systems, layout, color, typography, and deliberate inconsistency | Intermediate |
| 🛡️ | Brand Guardian | Brand identity, tone consistency, and visual identity governance | Advanced |
| 🎬 | Interaction Designer | Motion design, micro-interactions, transitions, and interaction choreography | Advanced |
| 🎯 | Creative Director | Aesthetic direction, quality bar enforcement, and design critique authority | Advanced |

---

## What Makes AgentGuild Different

### 1. Contrarian Takes

Every AgentGuild agent has a strongly held professional opinion that goes against mainstream consensus. These are not bland truisms — they are defensible, evidence-backed positions that shape how the agent thinks.

Examples:
- **Frontend Engineer:** "Framework choice is the least important architectural decision your team will make."
- **Backend Architect:** "Microservices are over-prescribed by a wide margin."
- **Data Analyst:** "Most 'data-driven' decisions are intuition-driven decisions looking for post-hoc data support."
- **Creative Director:** "Design by committee produces exactly the quality you'd expect from a committee."

### 2. Conflict Preferences

Each agent explicitly names situations where they will push back, say no, or escalate — and names the specific agent roles they are most likely to disagree with. This creates healthy tension that surfaces risks before they become production incidents.

### 3. Blind Spots

Every agent honestly describes what they are not good at and when they will proactively request help from another agent. This prevents the "faking it" problem that plagues generic AI agents and ensures the right expert is consulted for each decision.

### 4. Decision Authority

In multi-agent collaboration, every agent knows exactly what decisions they own and what decisions they defer to others. No ambiguity, no stepping on toes, no critical decisions falling through the cracks.

---

## Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/agentguild/agentguild.git
cd agentguild

# 2. Convert agent profiles to your tool's format
./scripts/convert.sh

# 3. Install agents into your AI tool
./scripts/install.sh

# 4. Done! Your AI tool now knows all 12 guild agents.
#    When you need expert help, reference an agent by name.
```

### Install Individual Tools

```bash
# Install for all supported tools (default)
./scripts/install.sh

# Install for a specific tool only
./scripts/install.sh --tool claude-code
./scripts/install.sh --tool cursor
./scripts/install.sh --tool copilot
./scripts/install.sh --tool windsurf

# Dry run to see what will be installed
./scripts/install.sh --dry-run
```

---

## Supported Tools

| Tool | Format | Install Command |
|------|--------|-----------------|
| [Claude Code](https://docs.anthropic.com/en/docs/claude-code) | `identity` (`.md`) | `./scripts/install.sh --tool claude-code` |
| [Cursor](https://cursor.sh) | `.mdc` rules | `./scripts/install.sh --tool cursor` |
| [GitHub Copilot](https://github.com/features/copilot) | `identity` (`.md`) | `./scripts/install.sh --tool copilot` |
| [Windsurf](https://codeium.com/windsurf) | `.windsurfrules` | `./scripts/install.sh --tool windsurf` |

AgentGuild agents are installed to your local AI tool configuration — not to the repository — so they follow you across projects. Per-agent installs and per-project installs are both supported.

---

## Project Structure

```
agentguild/
├── agents/
│   ├── engineering/
│   │   ├── frontend-engineer.md
│   │   ├── backend-architect.md
│   │   ├── devops-engineer.md
│   │   └── ai-engineer.md
│   ├── product/
│   │   ├── product-manager.md
│   │   ├── ux-researcher.md
│   │   ├── data-analyst.md
│   │   └── tech-writer.md
│   └── design/
│       ├── ui-designer.md
│       ├── brand-guardian.md
│       ├── interaction-designer.md
│       └── creative-director.md
├── docs/
│   ├── AGENT_TEMPLATE.md          # Agent creation guide (English)
│   └── AGENT_TEMPLATE_zh-CN.md    # Agent creation guide (Chinese)
├── scripts/
│   ├── convert.sh                 # Convert agents to tool-specific formats
│   ├── install.sh                 # Install agents into local AI tools
│   ├── lint.sh                    # Validate agent files against the template
│   └── lib.sh                     # Shared helper functions
├── guild.config.json              # Central registry of agents, divisions, and tools
├── .github/workflows/lint.yml     # CI: lint agents on every push
├── LICENSE                        # MIT License
├── README.md                      # This file
├── README_zh-CN.md                # README (Chinese)
├── CONTRIBUTING.md                # Contribution guide (English)
└── CONTRIBUTING_zh-CN.md          # Contribution guide (Chinese)
```

---

## Contributing

We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for:

- What makes a good AgentGuild agent (our quality bar)
- How to propose a new agent (issue template + PR)
- How to add support for a new AI tool
- Our code of conduct

---

## License

AgentGuild is released under the [MIT License](LICENSE).

---

<p align="center">
  <sub>Built with conviction, not consensus.</sub>
</p>
