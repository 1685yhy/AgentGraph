# AgentGraph AI 元数据规范

## 目的

每个模板文件自带 AI Agent 可解析的上下文，让 AI 打开文件即可知道：产出什么、什么格式、什么标准、交给谁。

## Frontmatter Schema

```yaml
---
agent: <agent-slug>              # 谁负责产出这个文件
consumes:                         # 需要上游 Agent 的什么交付物
  - from: <agent-slug>
    deliverable: <deliverable-name>
produces: <deliverable-name>      # 本文件的产出物名称
format: markdown|json|yaml|csharp|cpp|python|dockerfile|terraform   # 输出格式
acceptance:                       # 验收标准（至少 1 条）
  - <criterion 1>
  - <criterion 2>
handoff_to: <agent-slug>          # 产出后自动交给谁
---
```

## 字段说明

| 字段 | 必需 | 类型 | 说明 |
|------|------|------|------|
| agent | ✅ | string | 负责产出的 Agent slug |
| consumes | ✅ | array | 上游依赖列表，每项含 from + deliverable |
| produces | ✅ | string | 本文件产出物名称（用于 handoff 追踪） |
| format | ✅ | string | 输出格式，影响 gate 检查策略 |
| acceptance | ✅ | array | 验收标准列表，AI 必须逐条满足 |
| handoff_to | ✅ | string | 交付目标 Agent slug |

## 使用示例

```markdown
---
agent: ux-researcher
consumes:
  - from: product-manager
    deliverable: research-brief
produces: user-personas
format: markdown
acceptance:
  - 至少 3 个用户画像
  - 每个画像包含: 人口统计/行为模式/痛点/目标
  - 数据来源标注
handoff_to: data-analyst
---

# 用户画像

## Persona 1: [姓名]

...
```
