# Expand AgentGuild: +10 New Agents Report

## Summary

Added 10 new high-quality agents to AgentGuild at `/mnt/e/agentguild`, bringing the total from 18 to 28 agents across 10 divisions.

## New Divisions (5)

| Division | Label | Color | Icon |
|----------|-------|-------|------|
| security | Security | #EF4444 | Shield |
| project-management | Project Management | #0EA5E9 | Clipboard |
| sales | Sales | #10B981 | DollarSign |
| support | Support | #84CC16 | Headphones |
| finance | Finance | #22C55E | TrendingUp |

## New Agents (10)

### Security
1. **Security Engineer** (security-engineer.md) — 158 lines, advanced
   - Threat modeling, security architecture, penetration testing, compliance automation
   - Pairs with: backend-architect, devops-engineer, frontend-engineer

### Engineering (additions)
2. **Mobile Developer** (mobile-developer.md) — 186 lines, advanced
   - iOS/Android native development, cross-platform architecture, mobile performance
   - Pairs with: frontend-engineer, backend-architect, ui-designer

3. **Database Specialist** (database-specialist.md) — 151 lines, advanced
   - Database modeling, query optimization, migration strategy, data consistency
   - Pairs with: backend-architect, devops-engineer, data-analyst

4. **Code Reviewer** (code-reviewer.md) — 170 lines, advanced
   - Code quality review, architecture compliance, review culture advocacy
   - Pairs with: frontend-engineer, backend-architect, ai-engineer

### Project Management
5. **Project Manager** (project-manager.md) — 149 lines, intermediate
   - Timeline tracking, risk management, resource coordination, delivery planning
   - CRITICAL: Distinct from Product Manager — PM owns WHAT/WHY, Project Manager owns WHEN/HOW MUCH
   - Pairs with: product-manager, backend-architect, frontend-engineer

### Sales
6. **Sales Engineer** (sales-engineer.md) — 145 lines, advanced
   - Technical demos, PoC delivery, technical validation, pre-sales support
   - Pairs with: backend-architect, product-manager, frontend-engineer

7. **Deal Strategist** (deal-strategist.md) — 173 lines, advanced
   - Deal structuring, pricing strategy, negotiation support, revenue optimization
   - Pairs with: sales-engineer, product-manager, data-analyst

### Support
8. **Customer Support** (customer-support.md) — 177 lines, intermediate
   - Ticket triage, knowledge base, feedback loop to product, self-service infrastructure
   - Pairs with: product-manager, frontend-engineer, tech-writer

### Marketing (addition)
9. **SEO Specialist** (seo-specialist.md) — 155 lines, intermediate
   - Search intent analysis, technical SEO audits, keyword strategy, ranking optimization
   - Pairs with: content-creator, data-analyst, frontend-engineer

### Finance
10. **Financial Analyst** (financial-analyst.md) — 213 lines, advanced
    - Unit economics, financial modeling, SaaS metrics, profitability optimization
    - Pairs with: product-manager, data-analyst, deal-strategist

## Quality Verification

| Check | Result |
|-------|--------|
| `lint.sh --all` (28 files) | PASS: 28 file(s) clean |
| `contracts/extract.sh` (28 agents) | OK — 28 agents processed |
| `scripts/convert.sh` (all tools) | OK — 28 agents in claude-code, cursor, copilot, windsurf |
| `lint.sh --check-duplicates` | PASS — no duplicate Contrarian Takes |
| YAML frontmatter (8 fields each) | All valid |
| All 13 body sections present | All present |
| Contrarian takes > 200 chars | All verified |
| Real code/template examples | All real (not pseudocode) |
| Conflict preferences (2+ roles) | Each names 2-4 specific agent roles |
| Blind spots (honest & specific) | Each identifies 3-5 specific limitations |
| Decision authority (clear boundaries) | Each defines final say + deference areas |
| Collaboration contract (I/O) | Each lists 4-6 deliverables + 3-5 requirements |
| Chinese body, English YAML name | Compliant |

## Configuration Changes

- `guild.config.json`: 5 new divisions added, 10 new agents registered
- `contracts/guild-contracts.yml`: Regenerated — 28 agents
- `integrations/*`: All 4 tool formats regenerated

## File Summary

All 10 agent files:
- `/mnt/e/agentguild/agents/security/security-engineer.md`
- `/mnt/e/agentguild/agents/engineering/mobile-developer.md`
- `/mnt/e/agentguild/agents/engineering/database-specialist.md`
- `/mnt/e/agentguild/agents/engineering/code-reviewer.md`
- `/mnt/e/agentguild/agents/project-management/project-manager.md`
- `/mnt/e/agentguild/agents/sales/sales-engineer.md`
- `/mnt/e/agentguild/agents/sales/deal-strategist.md`
- `/mnt/e/agentguild/agents/support/customer-support.md`
- `/mnt/e/agentguild/agents/marketing/seo-specialist.md`
- `/mnt/e/agentguild/agents/finance/financial-analyst.md`
