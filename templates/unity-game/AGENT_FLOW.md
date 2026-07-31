---
agent: game-designer
consumes: []
produces: agent-flow-doc
format: markdown
acceptance:
  - 完整 Agent 接力链
  - 标注并行环节
handoff_to: unity-developer
---

# AgentGraph 工作流 — Unity 游戏

## 接力链
```
game-designer         GDD + 核心循环
    ↓
    ┌─────────────────┬──────────────────┬─────────────────┬──────────────────┐
    ↓                 ↓                  ↓                 ↓                  ↓
unity-developer   technical-artist   game-ui-designer  game-audio-engineer  monetization-designer
(代码+框架)       (美术+Shader)      (UI+UX)           (音效+BGM)          (变现设计)
    └─────────────────┴──────────────────┴─────────────────┴──────────────────┘
    ↓
game-qa-engineer      测试+bug报告
    ↓ (回路)
unity-developer       修复bug
    ↓
game-producer         发布管理
```
