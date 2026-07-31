---
agent: product-manager
consumes: []
produces: agent-flow-doc
format: markdown
acceptance:
  - 完整 Agent 接力链
handoff_to: ux-researcher
---

# AgentGraph 工作流 — 移动App (iOS/Android)

## 接力链
```
product-manager      产品需求 + 版本规划
    ↓
ux-researcher        用户研究 + 体验设计
    ↓
ui-designer          界面设计（双端适配）
    ↓
mobile-developer     iOS/Android 客户端开发
    ↓
frontend-engineer    H5 / 内嵌页面配合
    ↓
backend-architect    后端 API + 推送
    ↓
security-engineer    安全审计 + 数据保护
    ↓
qa-engineer          双端测试 + 性能验证
```
