---
agent: product-manager
consumes: []
produces: agent-flow-doc
format: markdown
acceptance:
  - 完整 Agent 接力链
handoff_to: data-analyst
---

# AgentGraph 工作流 — 数据看板

## 接力链
```
product-manager      指标定义 + 看板需求
    ↓
data-analyst         数据口径 + 分析逻辑
    ↓
ui-designer          看板可视化设计
    ↓
backend-architect    数据服务 API
    ↓
database-specialist  数据仓库 + ETL
    ↓
frontend-engineer    看板前端开发
    ↓
qa-engineer          数据准确性 + 性能测试
```
