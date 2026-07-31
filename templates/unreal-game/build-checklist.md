---
agent: game-producer
consumes:
  - from: game-qa-engineer
    deliverable: qa-report
produces: release-build
format: markdown
acceptance:
  - 所有 5 关质量门禁通过
  - 包体大小在商店限制内
  - Shader 编译完成无遗漏
handoff_to: null
---

# 构建发布清单 — Unreal Engine 5

## 质量门禁
- [ ] Gate 1: 完整性
- [ ] Gate 2: 语法 (编译 0 Error)
- [ ] Gate 3: 行为 (核心循环可玩通)
- [ ] Gate 4: 可玩性 (帧率达标/无崩溃)
- [ ] Gate 5: Agent 标准

## UE5 特定检查
- [ ] Shader 编译完成 (无 PSO 遗漏)
- [ ] Cook 完成 (无缺失资产)
- [ ] 包体大小: ___ (目标 ≤ ___)
- [ ] 启动时间: ___ 秒 (目标 ≤ ___)

## 平台检查
- [ ] Windows: 打包通过
- [ ] PS5: 提交通过 (如适用)
- [ ] Xbox: 提交通过 (如适用)

## 最终签字
- [ ] game-producer: 发布批准
- [ ] 构建版本号: v___
