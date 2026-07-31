---
agent: backend-architect
consumes: []
produces: agent-flow-doc
format: markdown
acceptance:
  - 完整 Agent 接力链
handoff_to: database-specialist
---

# AgentGraph 工作流 — API 服务

## 接力链
```
backend-architect    服务架构 + API 设计
    ↓
database-specialist  数据模型 + 存储设计
    ↓
security-engineer    鉴权 + 安全审计
    ↓
qa-engineer          接口测试 + 压测
    ↓
devops-engineer      部署上线 + 监控
```
