---
agent: ai-engineer
consumes:
  - from: data-analyst
    deliverable: model-evaluation
produces: model-card
format: markdown
acceptance:
  - 包含模型/数据/评估/伦理四部分
  - 遵循 HuggingFace Model Card 规范
handoff_to: devops-engineer
---

# 模型卡 (Model Card)

## 模型
- 名称: ___
- 基础模型: ___
- 参数量: ___
- 训练框架: ___

## 数据
- 训练集规模: ___
- 数据来源: ___
- 预处理: ___

## 评估
| 指标 | 训练集 | 验证集 | 测试集 |
|------|--------|--------|--------|
| Accuracy | ___ | ___ | ___ |
| F1 | ___ | ___ | ___ |
| 推理延迟 (p99) | — | — | ___ ms |

## 伦理考量
- 已知偏置: ___
- 不适用场景: ___
- 公平性评估: ___
