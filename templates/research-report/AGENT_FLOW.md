---
agent: product-manager
consumes: []
produces: agent-flow-doc
format: markdown
acceptance:
  - 完整的 Agent 接力链
  - 每个阶段的输入输出清晰
handoff_to: ux-researcher
---

# AgentGraph 工作流 — 研究报告

## 接力链

```
product-manager      定义研究范围+研究简报
    ↓
ux-researcher        执行用户研究(访谈/问卷/可用性测试)
    ↓
data-analyst         分析数据+提炼洞察
    ↓
tech-writer          撰写研究报告
    ↓
product-manager      审核+定稿
```

## 阶段详情

### 1. 需求定义 (product-manager)
- **产出**: research-brief (研究简报)
- **内容**: 研究目标、范围、关键问题、成功标准
- **交给**: ux-researcher

### 2. 用户研究 (ux-researcher)
- **输入**: research-brief
- **产出**: user-insights, behavior-data, personas
- **方法**: 访谈、问卷、可用性测试、焦点小组、二手数据
- **交给**: data-analyst

### 3. 数据分析 (data-analyst)
- **输入**: user-insights, behavior-data
- **产出**: data-analysis, findings
- **内容**: 量化分析、定性编码、关键洞察、统计显著性
- **交给**: tech-writer

### 4. 报告撰写 (tech-writer)
- **输入**: data-analysis, findings
- **产出**: report-draft
- **内容**: 执行摘要、研究方法、发现、建议
- **交给**: product-manager

### 5. 审核定稿 (product-manager)
- **输入**: report-draft
- **产出**: final-report
- **标准**: 数据来源可追溯、建议可执行、报告结构完整
