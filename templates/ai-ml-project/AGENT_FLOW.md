---
agent: ai-engineer
consumes: []
produces: agent-flow-doc
format: markdown
acceptance:
  - 完整 Agent 接力链
handoff_to: backend-architect
---

# AgentGraph 工作流 — AI/ML 项目

## 接力链
```
ai-engineer          模型选择 + 训练pipeline + 特征工程
    ↓
backend-architect    API 封装 + 模型服务化
    ↓
data-analyst         模型评估 + 数据质量分析
    ↓
qa-engineer          准确率验证 + 性能测试
    ↓
devops-engineer      模型部署 + 监控
    ↓
ai-engineer          线上效果验收
```
