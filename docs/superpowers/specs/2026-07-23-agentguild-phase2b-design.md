# AgentGuild Phase 2b — Phase Orchestrator 设计文档

**版本**: v1.0 | **日期**: 2026-07-23 | **状态**: 已确认

## 一句话定位

把 Phase 2a 的手动 handoff 串成自动流水线——定义 pipeline → `guild run` → 自动流转。

## MVP 范围

**做**: `guild run` 命令、YAML pipeline 定义、串行阶段自动流转、缺失时暂停
**不做**: 并行阶段、条件分支、Web 触发

## Pipeline 格式

```yaml
name: 创业 MVP 开发
phases:
  - phase: 发现
    agents: [product-manager, ux-researcher]
    delivers: [problem_statement, user_insights]
  - phase: 设计
    agents: [ui-designer, interaction-designer]
    requires_from: 发现
    delivers: [design_spec, interaction_spec]
  - phase: 构建
    agents: [frontend-engineer, backend-architect]
    requires_from: 设计
    delivers: [working_build, api_spec]
  - phase: 验证
    agents: [qa-engineer, creative-director]
    requires_from: 构建
    delivers: [qa_report, design_review]
```

## CLI

```
guild run --pipeline <name> --path <dir> [--dry-run]
guild run --list
```

## 文件

- `scripts/nexus.sh` 扩展（新增 cmd_run）
- `pipelines/` 目录（pipeline YAML 文件）
- 2 条预置 pipeline
- 使用文档

## 与 Phase 2a 关系

`guild run` 内部调用 `guild handoff` + `guild check`，不重复造轮子。
