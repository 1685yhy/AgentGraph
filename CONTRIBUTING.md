# Contributing to AgentGraph

Thank you for your interest in AgentGraph! This document outlines the quality standards, processes, and guidelines for contributing new agents, tools, or improvements to the guild.

**Table of Contents**

- [Quality Bar for Agents](#quality-bar-for-agents)
- [Agent Template Reference](#agent-template-reference)
- [How to Propose a New Agent](#how-to-propose-a-new-agent)
- [How to Add Support for a New AI Tool](#how-to-add-support-for-a-new-ai-tool)
- [Code of Conduct](#code-of-conduct)
- [Pull Request Process](#pull-request-process)

---

## Quality Bar for Agents

AgentGraph is a curated roster. Not every agent file belongs here. Every agent must meet the following criteria to be considered for inclusion.

### Required: Four Guild Signatures

Every agent must have all four of AgentGraph's signature sections, and they must be **genuine**:

1. **Contrarian Take** — A professional opinion that goes against mainstream consensus. It must be defensible with evidence (minimum 3 sentences). If your contrarian take sounds like something everyone agrees with, it is not contrarian enough.

2. **Conflict Preferences** — Specific situations where the agent will push back, say no, or escalate. Must name specific Agent roles as disagreement partners (e.g., "I will push back against the Product Manager when..."). Generic statements like "I disagree with bad ideas" are not acceptable.

3. **Blind Spots** — Honest self-assessment of limitations. Must name specific areas outside the agent's expertise and name specific Agent roles they would defer to. "I am a perfectionist" is not a blind spot. "I lack expertise in backend database optimization and defer to the Backend Architect" is a real blind spot.

4. **Decision Authority** — Clear boundaries on what the agent has final say over and what they defer to others. Both sides must be specified.

### Required: Complete Collaboration Contract

The agent must specify:
- Concrete deliverables it provides to downstream agents (with real examples, not generic promises)
- Concrete requirements it needs from upstream agents before it can start working

### Required: Quality Checklist

- [ ] Contrarian Take is genuinely contrarian (not a bland truism)
- [ ] Conflict Preferences name specific Agent roles
- [ ] Blind Spots are honest and specific (not "I'm a perfectionist")
- [ ] Decision Authority has clear boundaries
- [ ] Collaboration Contract lists concrete inputs and outputs
- [ ] Code examples are real, runnable code (not pseudocode)
- [ ] Success Metrics include numbers
- [ ] No section is shorter than 3 sentences

---

## Agent Template Reference

Every agent file must follow the structure defined in [`docs/AGENT_TEMPLATE.md`](docs/AGENT_TEMPLATE.md). This includes:

- **YAML frontmatter** — `name`, `short` (Chinese name), `role`, `description`, `color`, `emoji`, `difficulty`, `pairing`
- **13 body sections** — Identity & Memory, Core Mission, Contrarian Take, Critical Rules, Technical Deliverables, Workflow Process, Deliverable Template, Communication Style, Success Metrics, Conflict Preferences, Blind Spots, Decision Authority, Collaboration Contract

A Chinese version of the template is available at [`docs/AGENT_TEMPLATE_zh-CN.md`](docs/AGENT_TEMPLATE_zh-CN.md).

---

## How to Propose a New Agent

### Step 1: Open an Issue

Open a GitHub issue using the Agent Proposal template. Your issue must include:

- Proposed agent name and emoji
- Which division (engineering, product, design) it belongs to
- A one-sentence description
- A draft of the Contrarian Take and Conflict Preferences (minimum requirement for discussion)
- Why this agent fills a gap in the current roster

### Step 2: Community Discussion

The maintainers and community will review your proposal for:
- Fit with AgentGraph's quality bar
- Distinctiveness from existing agents (no overlap)
- Relevance to software development teams
- Feasibility of the contrarian take and conflict preferences

### Step 3: Submit a PR

Once your proposal is approved, submit a pull request that:

1. Creates the agent file at `agents/<division>/<agent-slug>.md` following `docs/AGENT_TEMPLATE.md`
2. Registers the agent in `guild.config.json` (add an entry to the `agents` array)
3. Runs `./scripts/lint.sh` to verify the agent passes validation
4. Validates that the `role` field matches a division key in `guild.config.json`

### Step 4: Review

Your PR will be reviewed for:
- Completeness of all 13 body sections
- Genuine contrarian take (not a bland truism)
- Specific conflict preferences (naming other agents)
- Honest blind spots
- Clear decision authority boundaries
- Runnable code examples
- Measurable success metrics

---

## How to Add Support for a New AI Tool

AgentGraph supports Claude Code, Cursor, GitHub Copilot, and Windsurf. To add a new AI tool:

### Step 1: Register the tool in `guild.config.json`

Add a new entry to the `tools` object:

```json
{
  "tools": {
    "your-tool": {
      "label": "Your Tool Display Name",
      "format": "identity" | "cursor-mdc" | "windsurf-rules",
      "installKind": "per-agent" | "roster",
      "dest": {
        "user": ["path/to/config/{slug}.md"],
        "project": ["path/to/config/{slug}.md"]
      }
    }
  }
}
```

- `format`: The output format. `identity` copies the `.md` file as-is. Other formats require adding conversion logic to `convert.sh`.
- `installKind`: `per-agent` installs individual agent files. `roster` creates a single roster file containing all agents.
- `dest`: Array of destination paths relative to the target tool's config directory. Use `{slug}` as a placeholder for the agent slug.

### Step 2: Add conversion support (if needed)

If your tool requires a different format than the original `.md` files, add the conversion logic to `scripts/convert.sh`. The script uses `scripts/lib.sh` for shared helpers.

### Step 3: Add installation support

Add installation logic to `scripts/install.sh`. This script reads `guild.config.json` and copies or generates the appropriate files in the target tool's configuration directory.

### Step 4: Update documentation

Add your tool to the Supported Tools table in `README.md` and `README_zh-CN.md`.

---

## Code of Conduct

### Our Pledge

We are committed to providing a welcoming, inclusive, and harassment-free experience for everyone in the AgentGraph community, regardless of age, body size, disability, ethnicity, gender identity, experience level, nationality, personal appearance, race, religion, or sexual identity and orientation.

### Our Standards

**Positive behavior:**

- Using welcoming and inclusive language
- Being respectful of differing viewpoints and experiences
- Gracefully accepting constructive criticism
- Focusing on what is best for the community
- Showing empathy towards other community members

**Unacceptable behavior:**

- Harassment, intimidation, or discrimination in any form
- Trolling, insulting/derogatory comments, and personal or political attacks
- Publishing others' private information without explicit permission
- Other conduct which could reasonably be considered inappropriate in a professional setting

### Enforcement

Project maintainers are responsible for clarifying the standards of acceptable behavior and are expected to take appropriate and fair corrective action in response to any instances of unacceptable behavior.

Instances of abusive, harassing, or otherwise unacceptable behavior may be reported by contacting the project maintainers. All complaints will be reviewed and investigated and will result in a response that is deemed necessary and appropriate to the circumstances.

---

## Pull Request Process

1. **Branch from `main`** and name your branch descriptively (e.g., `feat/data-scientist-agent`, `feat/tool-vscode-copilot`).

2. **Keep changes focused** — a PR should address one concern: a new agent, a new tool, or a documentation improvement.

3. **Run validation** — before submitting, run `./scripts/lint.sh` and ensure it passes without errors. All agent files must pass the lint check.

4. **Update documentation** — if your PR adds a new agent, the agent roster in `README.md` and `README_zh-CN.md` must be updated. If your PR adds a new tool, the Supported Tools table must be updated.

5. **Wait for review** — maintainers will review your PR within 5 business days. Address any requested changes promptly.

6. **Squash merge** — PRs are squash-merged into `main` to keep a clean history. Ensure your PR description clearly explains what the change does and why.

---

Thank you for helping make AgentGraph better. Every agent, every tool integration, and every improvement starts with someone who cares about quality.

<p align="center">
  <sub>Built with conviction, not consensus.</sub>
</p>
