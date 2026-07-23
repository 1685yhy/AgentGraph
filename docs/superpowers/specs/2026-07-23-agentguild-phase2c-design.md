# AgentGuild Phase 2c — Context Bus + Conflict Resolver 设计文档

**版本**: v1.0 | **日期**: 2026-07-23 | **状态**: 已确认

## 定位

把 Agent 的隐形决策变成结构化记录，自动检测冲突，追溯决策后果。

## 三个命令

| 命令 | 作用 |
|------|------|
| `guild decide` | 记录结构化决策（提交前检查影响范围） |
| `guild context show` | 展示决策图谱（按 Agent/类型/状态分组） |
| `guild context check` | 检查冲突 + 交付物是否遵循决策 |

## 决策记录格式

每条决策一个 JSON 文件：`context/decisions/<id>-<agent>-<topic>.json`，包含 id、agent、timestamp、decision(type/topic/summary/rationale/constraints/authority)、impact(affects/breaking_changes/notified/confirmed)、traceability、status。

## 联动

- decide 时：读取 Agent 决策权重 + 协作契约 → 计算影响范围
- handoff 时：检查交付物是否遵循相关决策 → 偏离则标记
- run 时：每阶段结束自动 context check

## 交付

- nexus.sh 扩展（3 命令 + handoff 联动）
- context/ 目录 + 索引
- 使用文档
