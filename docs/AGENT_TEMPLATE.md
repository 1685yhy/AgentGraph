# AgentGraph Agent Template

This document defines the standard for every Agent in the AgentGraph roster.
Every Agent file consists of **YAML frontmatter** followed by **13 body sections**.

## Frontmatter (YAML)

```yaml
---
name: Frontend Engineer
short: 前端工程师
role: engineering
description: Expert frontend engineer specializing in UI architecture,
             performance optimization, and design-system engineering.
             Keep under 160 characters.
color: "#3B82F6"
emoji: 🖥️
difficulty: advanced
pairing: [backend-architect, ui-designer]
---
```

| Field | Required | Notes |
|-------|----------|-------|
| `name` | Yes | Display name in English |
| `short` | Yes | Display name in Chinese (or native language) |
| `role` | Yes | Division key matching `guild.config.json` divisions |
| `description` | Yes | One sentence, under 160 chars |
| `color` | Yes | Hex color for UI display |
| `emoji` | Yes | Single emoji representing the role |
| `difficulty` | Yes | `beginner`, `intermediate`, or `advanced` |
| `pairing` | Yes | Array of slugs this Agent works best with |

## Body Sections (13 total)

### 1. Identity & Memory
Who you are, your personality traits, and what experiences shape your judgment.

### 2. Core Mission
What you're here to do, broken into specific competency areas.

### 3. Contrarian Take *(Guild signature)*
A professional opinion you hold that goes against mainstream consensus — but is defensible with evidence. This is what makes you think differently from a generic template. Minimum 3 sentences.

### 4. Critical Rules
Non-negotiable principles you will not violate under any circumstance.

### 5. Technical Deliverables
What your output looks like, with real examples. Must include at least one code block.

### 6. Workflow Process
Step-by-step how you approach a typical task in your domain.

### 7. Deliverable Template
A reusable output template in Markdown that downstream consumers can rely on.

### 8. Communication Style
How you talk — tone, precision level, what you emphasize and what you omit.

### 9. Success Metrics
Quantifiable criteria for "done well." Include concrete numbers.

### 10. Conflict Preferences *(Guild signature)*
Situations where you will push back, say no, or escalate. Who you're most likely to disagree with and why. Be specific — name the other Agent roles and the nature of the disagreement.

### 11. Blind Spots *(Guild signature)*
What you know you're bad at. When you will proactively request help from another Agent. This prevents you from "faking it" in domains outside your expertise.

### 12. Decision Authority *(Guild signature)*
What decisions you have final say on in a multi-agent collaboration. What decisions you defer to others. This creates clear ownership boundaries.

### 13. Collaboration Contract
What you promise to deliver to downstream Agents. What you require from upstream Agents before you can start. This makes handoffs explicit and testable.

## Quality Checklist

Before submitting an Agent, verify:

- [ ] Contrarian Take is genuinely contrarian (not a bland truism)
- [ ] Conflict Preferences name specific Agent roles
- [ ] Blind Spots are honest and specific (not "I'm a perfectionist")
- [ ] Decision Authority has clear boundaries
- [ ] Collaboration Contract lists concrete inputs and outputs
- [ ] Code examples are real, runnable code (not pseudocode)
- [ ] Success Metrics include numbers
- [ ] No section is shorter than 3 sentences
