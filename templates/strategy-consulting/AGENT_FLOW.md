---
agent: product-manager
consumes: []
produces: agent-flow-doc
format: markdown
acceptance:
  - 完整 Agent 接力链
  - 每阶段输入输出清晰
handoff_to: ux-researcher
---

# AgentGraph 工作流 — 策略咨询

## 接力链

```
product-manager      定义策略范围+目标
    ↓
ux-researcher        市场/用户研究
    ↓
data-analyst         数据分析+市场洞察
    ↓
growth-hacker        增长策略+获客方案
    ↓
financial-analyst    财务模型+定价策略
    ↓
content-creator      撰写策略报告
```

## 阶段详情

### 1. 策略定义 (product-manager)
- **产出**: strategy-brief
- **内容**: 战略目标、范围、约束条件、成功指标

### 2. 市场研究 (ux-researcher)
- **输入**: strategy-brief
- **产出**: market-insights
- **方法**: 竞品分析、用户访谈、趋势研究

### 3. 数据分析 (data-analyst)
- **输入**: market-insights
- **产出**: market-analysis
- **内容**: TAM/SAM/SOM、增长趋势、市场结构

### 4. 增长策略 (growth-hacker)
- **输入**: market-analysis
- **产出**: growth-plan
- **内容**: 获客渠道、转化漏斗、增长实验

### 5. 财务建模 (financial-analyst)
- **输入**: growth-plan
- **产出**: financial-model
- **内容**: 单位经济学、盈亏分析、定价建议

### 6. 报告撰写 (content-creator)
- **输入**: financial-model, growth-plan
- **产出**: strategy-report
- **内容**: 策略摘要 + 执行路线图
