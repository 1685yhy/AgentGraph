---
agent: game-designer
consumes: []
produces: agent-flow-doc
format: markdown
acceptance:
  - 完整 Agent 接力链
handoff_to: game-programmer
---

# AgentGraph 工作流 — 微信小游戏

## 接力链
```
game-designer            GDD + 核心玩法 + 数值设计
    ↓
game-programmer          PhaserJS 客户端 + 引擎集成
    ↓
technical-artist         2D 美术 + 动效
    ↓
game-ui-designer         界面 + 商店 + 新手引导
    ↓
game-audio-engineer      音效 + BGM
    ↓
monetization-designer    广告 + 内购变现设计
    ↓
game-qa-engineer         真机测试 + 性能优化
    ↓
game-producer            提审 + 发布 + 数据复盘
```
