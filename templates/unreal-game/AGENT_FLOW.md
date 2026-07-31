---
agent: game-designer
consumes: []
produces: agent-flow-doc
format: markdown
acceptance:
  - 完整 Agent 接力链
  - 标注并行环节
handoff_to: unreal-developer
---

# AgentGraph 工作流 — Unreal Engine 5 游戏

## 接力链
```
game-designer         GDD + 核心循环 + 世界设定
    ↓
    ┌─────────────────┬──────────────────┬─────────────────┬──────────────────┐
    ↓                 ↓                  ↓                 ↓                  ↓
unreal-developer   technical-artist   game-ui-designer  game-audio-engineer  (narrative-designer)
(C++/蓝图)         (材质/Niagara)     (UMG/UI)         (MetaSounds)         (剧情/对话)
    └─────────────────┴──────────────────┴─────────────────┴──────────────────┘
    ↓
game-qa-engineer      测试+性能分析
    ↓ (回路)
unreal-developer      修复
    ↓
game-producer         打包+发布
```

## 并行说明
- **unreal-developer**: 等待 GDD 完成后立即开始 Gameplay Ability System 搭建
- **technical-artist**: 与 GDD 并行 — 先确定美术风格方向，不需要等完整设计
- **game-audio-engineer**: 可与开发并行 — 音效触发逻辑后期集成
- **narrative-designer**: 仅在剧情驱动游戏时激活
