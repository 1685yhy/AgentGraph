# Phase 2b Implementation Plan

> **Goal:** Add `guild run` command — execute a multi-phase pipeline with automatic handoff between phases.

**Architecture:** Extend `scripts/nexus.sh` with `cmd_run()`. Pipeline definitions are YAML files in `pipelines/`. `guild run` iterates phases, calling internal handoff logic between each phase boundary.

**Tech Stack:** Bash 3.2+, YAML (pipeline definition)

## Global Constraints
- Bash 3.2+, zero external dependencies (python3 built-in ok)
- Do NOT modify agent files, existing scripts (only append to nexus.sh)
- Project root: ~/agentguild

---

### Task 1: Extend nexus.sh with `guild run`

**Files:**
- Modify: `scripts/nexus.sh` (append cmd_run function)
- Create: `pipelines/` directory
- Create: `pipelines/startup-mvp.yml`
- Create: `pipelines/feature-dev.yml`

**What to do:**

1. Read current nexus.sh to understand structure
2. Append `cmd_run()` function that:
   - Parses `--pipeline <name> --path <dir> [--dry-run]`
   - Reads pipeline YAML from `pipelines/<name>.yml`
   - Iterates phases in order
   - For each phase boundary: auto-runs handoff between current phase agents and next phase agents
   - If handoff incomplete: prints missing items, pauses (waits for user to hit Enter)
   - If handoff ready: proceeds to next phase
   - `--list` flag: lists available pipelines
3. Add `run` to the main command dispatcher
4. Verify: `bash -n scripts/nexus.sh`

**Pipeline run logic (pseudocode):**
```
load pipeline YAML
for i in range(0, len(phases) - 1):
  current = phases[i]
  next = phases[i+1]
  print "Phase: {current.phase} → {next.phase}"
  for agent in current.agents:
    print "  等待 {agent} 产出..."
  # Run handoff between each current agent and each next agent
  for from_agent in current.agents:
    for to_agent in next.agents:
      result = guild handoff --from {from_agent} --to {to_agent} --path {path}
      if result.incomplete:
        print "缺失项 → 暂停"
        wait_for_user()
  print "Phase {current.phase} → {next.phase} 完成"
```

### Task 2: Pipeline YAML files

Create `pipelines/startup-mvp.yml`:
```yaml
name: 创业 MVP 开发
description: 从零到 MVP 的完整产品开发流水线
phases:
  - phase: 发现与定义
    agents: [product-manager, ux-researcher]
    delivers: [问题陈述, 用户洞察, 产品需求文档]
  - phase: 设计
    agents: [ui-designer, interaction-designer]
    requires_from: 发现与定义
    delivers: [设计规范, 交互规范, 视觉稿]
  - phase: 工程实现
    agents: [frontend-engineer, backend-architect, devops-engineer]
    requires_from: 设计
    delivers: [可运行构建, API 规范, 部署流水线]
  - phase: 质量验证
    agents: [qa-engineer, creative-director]
    requires_from: 工程实现
    delivers: [质量报告, 设计评审, 发布决策]
```

Create `pipelines/feature-dev.yml`:
```yaml
name: 功能开发
description: 单个功能的开发流水线（PRD → 设计 → 实现 → 审查）
phases:
  - phase: 需求定义
    agents: [product-manager]
    delivers: [PRD, 用户故事, 验收条件]
  - phase: 设计
    agents: [ui-designer]
    requires_from: 需求定义
    delivers: [UI 设计稿, 交互说明]
  - phase: 实现
    agents: [frontend-engineer, backend-architect]
    requires_from: 设计
    delivers: [功能代码, API, 测试]
  - phase: 审查
    agents: [tech-writer, creative-director]
    requires_from: 实现
    delivers: [文档更新, 设计审查, 发布就绪]
```

### Task 3: Documentation

Create `docs/流水线指南.md` — Chinese guide explaining:
- What is a pipeline
- How to run one: `guild run --pipeline startup-mvp --path ./project/`
- How to define your own: YAML format
- How it works under the hood (calls guild handoff between phases)

### Task 4: Integration Test

1. `bash -n scripts/nexus.sh`
2. `./guild run --list` shows 2 pipelines
3. `./guild run --pipeline startup-mvp --dry-run` shows phases without writing
4. Phase 1 lint: `./scripts/lint.sh --all` still PASS
