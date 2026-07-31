---
agent: game-producer
consumes:
  - from: game-qa-engineer
    deliverable: qa-report
produces: release-build
format: markdown
acceptance:
  - 所有 5 关质量门禁通过
  - 构建大小在商店限制内
handoff_to: null
---

# 构建发布清单

## 质量门禁
- [ ] Gate 1: 完整性 — 所有计划功能已实现
- [ ] Gate 2: 语法 — 无编译错误/警告
- [ ] Gate 3: 行为 — 核心循环可玩通
- [ ] Gate 4: 可玩性 — 帧率达标/无崩溃
- [ ] Gate 5: Agent 标准 — 所有 Agent 交接完成

## 平台检查
- [ ] iOS: 构建通过 + TestFlight 就绪
- [ ] Android: APK/AAB 构建通过 + 64位支持
- [ ] Web: WebGL 构建 ≤ ___MB
- [ ] PC: Standalone 构建通过

## 商店素材
- [ ] 图标 (1024×1024)
- [ ] 截图 (≥ 5 张)
- [ ] 宣传视频 (可选)
- [ ] 商店描述 (中文/英文)

## 最终签字
- [ ] game-producer: 发布批准
- [ ] 构建版本号: v___
