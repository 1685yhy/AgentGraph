---
agent: game-designer
consumes: []
produces: game-design-document
format: markdown
acceptance:
  - 核心循环清晰
  - UE5 特色能力已考虑(Nanite/Lumen/World Partition)
  - 目标硬件规格明确
handoff_to: unreal-developer
---

# 游戏设计文档 (GDD) — Unreal Engine 5

## 游戏概述
- 游戏名: ___
- 类型: ___
- 视角: [第一人称/第三人称/俯视/2D]
- 目标平台: [PC/PS5/Xbox Series]
- 目标帧率: [30/60/120] FPS
- 一句话: ___

## UE5 技术选型
- [ ] Nanite (虚拟几何)
- [ ] Lumen (动态全局光照)
- [ ] World Partition (开放世界)
- [ ] MetaSounds (音频)
- [ ] Niagara (粒子/VFX)
- [ ] Gameplay Ability System (技能系统)
- [ ] Enhanced Input (输入系统)

## 核心循环
```
玩家行动 → ___ → ___
    ↑              ↓
    └── 奖励 ←──────┘
```

## 世界设计
- 地图大小: ___
- 区域数量: ___
- 美术风格方向: ___
- 参考: ___

## 性能目标
| 平台 | 分辨率 | 帧率 | 显存 |
|------|--------|------|------|
| PC | ___ | ___ | ___ |
| PS5 | ___ | ___ | ___ |
