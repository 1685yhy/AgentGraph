---
agent: devops-engineer
consumes: []
produces: agent-flow-doc
format: markdown
acceptance:
  - 完整 Agent 接力链
handoff_to: backend-architect
---

# AgentGraph 工作流 — 基础设施

## 接力链
```
devops-engineer      CI/CD 流水线 + Docker 化
    ↓
backend-architect   API 网关 + 服务架构
    ↓
security-engineer   安全审计 + 密钥管理
    ↓
qa-engineer         集成测试 + 压测
    ↓
devops-engineer     生产部署验收
```
