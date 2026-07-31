---
agent: product-manager
consumes: []
produces: agent-flow-doc
format: markdown
acceptance:
  - 完整 Agent 接力链
handoff_to: ux-researcher
---

# AgentGraph 工作流 — 后台管理系统

## 接力链
```
product-manager      需求定义 + PRD + 验收标准
    ↓
ux-researcher        用户调研 + 业务流程梳理
    ↓
ui-designer          界面设计 + 交互稿
    ↓
frontend-engineer    前端开发（CRUD / 审批流 / 权限页）
    ↓
backend-architect    后端架构 + API 设计
    ↓
database-specialist  数据模型 + 权限设计
    ↓
security-engineer    安全审计 + 越权校验
    ↓
qa-engineer          功能测试 + 回归
    ↓
devops-engineer      部署 + 监控
    ↓
product-manager      验收交付
```
