# AgentGraph v0.4 — 模板脚手架填充 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 填充 9 个空模板为可直接使用的项目脚手架，建立 AI Agent 友好的 YAML frontmatter 元数据规范。

**Architecture:** 所有模板文件统一使用 YAML frontmatter（agent/consumes/produces/acceptance/handoff_to），每个模板包含 AGENT_FLOW.md 记录 Agent 接力链。文档型模板为纯 Markdown 文件，工程型模板包含代码骨架。

**Tech Stack:** Markdown + YAML frontmatter, C# (Unity), C++ (Unreal), Docker/Terraform, Python

**Spec:** `docs/superpowers/specs/2026-07-31-agentgraph-v0.4-template-scaffolding.md`

## Global Constraints

- 所有新增模板文件必须包含 YAML frontmatter（agent/consumes/produces/acceptance/handoff_to 五字段）
- 所有 18 个模板 `guild init --template <name>` 可用
- 自测无回归
- Bash 3.2+ 兼容
- 模板文件 Markdown，中文为主，frontmatter 字段名用英文

---

### Task 1: AI 元数据规范落地 + 现有模板补齐 README

**Files:**
- Create: `docs/AI_METADATA_SPEC.md`

**Interfaces:**
- Produces: 元数据规范文档（所有后续模板任务遵循此规范）
- 定义 frontmatter schema: `agent`, `consumes`, `produces`, `format`, `acceptance`, `handoff_to`

- [ ] **Step 1: 创建 AI 元数据规范文档**

```bash
cat > /mnt/e/agentguild/docs/AI_METADATA_SPEC.md << 'EOF'
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
EOF
```

- [ ] **Step 2: Commit**

```bash
cd /mnt/e/agentguild
git add docs/AI_METADATA_SPEC.md
git commit -m "docs: AI 元数据规范 — YAML frontmatter schema (agent/consumes/produces/acceptance/handoff_to)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: 第一批 4 个文档型模板

**Files:**
- Create: `templates/research-report/AGENT_FLOW.md`, `report-outline.md`, `methodology-guide.md`, `personas-template.md`, `findings-template.md`, `survey-template.md`
- Create: `templates/strategy-consulting/AGENT_FLOW.md`, `strategy-brief.md`, `bmc-canvas.md`, `gtm-checklist.md`, `exec-summary.md`, `swot-analysis.md`
- Create: `templates/brand-identity/AGENT_FLOW.md`, `brand-guide.md`, `color-palette.md`, `typography-spec.md`, `logo-brief.md`
- Create: `templates/content-project/AGENT_FLOW.md`, `content-strategy.md`, `editorial-calendar.md`, `style-guide.md`, `article-template.md`

**Interfaces:**
- Produces: 4 个模板的完整脚手架文件，每个文件带 frontmatter

- [ ] **Step 1: 创建 research-report 模板文件**

```bash
cd /mnt/e/agentguild

# AGENT_FLOW.md
cat > templates/research-report/AGENT_FLOW.md << 'EOF'
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
EOF

# report-outline.md
cat > templates/research-report/report-outline.md << 'EOF'
---
agent: tech-writer
consumes:
  - from: data-analyst
    deliverable: data-analysis
produces: report-outline
format: markdown
acceptance:
  - 包含执行摘要/方法/发现/建议四大章节
  - 每章节有 2-3 个关键要点提示
  - 字数目标标注
handoff_to: product-manager
---

# 研究报告大纲

## 1. 执行摘要
- _关键发现一句话_
- _核心建议一句话_
- _目标读者: 决策者, 3 分钟可读完_

## 2. 研究背景与目标
- 研究问题
- 目标受众
- 研究范围

## 3. 研究方法
- 方法 1: _[访谈/问卷/可用性测试/数据分析]_
  - 样本量: ___
  - 时间: ___
- 方法 2: ___

## 4. 核心发现
- 发现 1: ___
  - 数据支撑: ___
- 发现 2: ___
- 发现 3: ___

## 5. 建议与下一步
- 建议 1: ___
  - 优先级: [高/中/低]
  - 预期影响: ___
- 建议 2: ___

## 6. 附录
- 原始数据来源
- 问卷/访谈提纲
EOF

# methodology-guide.md
cat > templates/research-report/methodology-guide.md << 'EOF'
---
agent: ux-researcher
consumes:
  - from: product-manager
    deliverable: research-brief
produces: methodology-plan
format: markdown
acceptance:
  - 至少选择 2 种互补方法
  - 每种方法有样本量/时间/预算估算
  - 每种方法对应具体的研究问题
handoff_to: product-manager
---

# 调研方法指南

## 方法选择矩阵

| 方法 | 适用场景 | 样本量 | 成本 | 周期 |
|------|---------|--------|------|------|
| 用户访谈 | 深度理解动机/痛点 | 8-15人 | 中 | 1-2周 |
| 问卷调查 | 量化验证假设 | 100-1000+ | 低-中 | 1-3周 |
| 可用性测试 | 评估产品体验 | 5-8人/轮 | 中 | 3-5天 |
| 焦点小组 | 探索态度/偏好 | 3-5组×6-8人 | 高 | 2-4周 |
| 数据分析 | 行为模式挖掘 | 全量 | 低 | 1-2周 |
| 竞品分析 | 市场定位 | 5-10个竞品 | 低 | 1-2周 |
| A/B测试 | 因果验证 | 按效应量 | 中 | 1-4周 |

## 方法组合建议

### 探索性研究（新市场/新需求）
访谈 → 问卷 → 数据分析
_先定性探索，再定量验证_

### 评估性研究（现有产品改进）
数据分析 → 可用性测试 → 问卷
_先看数据定位问题，再深入测试，最后量化满意度_

### 策略性研究（竞争/市场）
竞品分析 → 焦点小组 → 问卷
_先建立市场全貌，再探索用户态度，最后量化验证_
EOF

# personas-template.md
cat > templates/research-report/personas-template.md << 'EOF'
---
agent: ux-researcher
consumes:
  - from: ux-researcher
    deliverable: user-interviews
produces: user-personas
format: markdown
acceptance:
  - 至少 3 个用户画像
  - 每个包含: 人口统计/行为模式/痛点/目标/使用场景
  - 数据来源标注(访谈/问卷/二手数据)
handoff_to: data-analyst
---

# 用户画像

## Persona 1: [姓名/代号]

### 人口统计
- 年龄: ___
- 职业: ___
- 城市: ___
- 收入水平: ___

### 行为模式
- 使用频率: ___
- 使用设备: ___
- 关键行为: ___

### 痛点
1. ___
2. ___

### 目标
1. ___
2. ___

### 使用场景
- 场景描述: ___
- 触发条件: ___

### 数据来源
- [ ] 访谈 (_N=___)
- [ ] 问卷 (_N=___)
- [ ] 二手数据

---

## Persona 2: [姓名/代号]
_(同上结构)_

---

## Persona 3: [姓名/代号]
_(同上结构)_
EOF

# findings-template.md
cat > templates/research-report/findings-template.md << 'EOF'
---
agent: data-analyst
consumes:
  - from: ux-researcher
    deliverable: user-personas
produces: research-findings
format: markdown
acceptance:
  - 每个发现附带量化或定性证据
  - 每条建议有优先级和预期影响
  - 区分"事实发现"和"推断建议"
handoff_to: tech-writer
---

# 调研发现与建议

## 发现 1: [标题]

### 证据
- 量化数据: ___
- 定性引用: "___"
- 来源: ___

### 影响
- 对产品的影响: ___
- 对业务的影响: ___

### 建议
- 行动: ___
- 优先级: [高/中/低]
- 预期效果: ___

---

## 发现 2: [标题]
_(同上结构)_

---

## 发现 3: [标题]
_(同上结构)_

---

## 建议优先级矩阵

| 建议 | 影响 | 成本 | 优先级 |
|------|------|------|--------|
| ___ | 高/中/低 | 高/中/低 | P0/P1/P2 |
EOF

# survey-template.md
cat > templates/research-report/survey-template.md << 'EOF'
---
agent: ux-researcher
consumes:
  - from: product-manager
    deliverable: research-brief
produces: survey-design
format: markdown
acceptance:
  - 包含筛选/主体/结尾三部分
  - 问题类型多样(单选/多选/量表/开放)
  - 预估完成时间标注
handoff_to: product-manager
---

# 问卷设计

## 基本信息
- 目标受众: ___
- 目标样本量: ___
- 分发渠道: ___
- 预估时长: ___ 分钟

## 筛选部分

Q1. [筛选问题 — 确保受访者符合目标]
- [ ] 选项 A
- [ ] 选项 B
- [ ] 以上皆非 → 终止

## 主体部分

### 板块 A: [主题]
Q2. [单选 — 行为频率]
- [ ] 每天
- [ ] 每周 3-5 次
- [ ] 每周 1-2 次
- [ ] 每月几次
- [ ] 从不

Q3. [量表 — 满意度, 1-5 分]
1 ___ 2 ___ 3 ___ 4 ___ 5 ___

Q4. [多选 — 使用场景]
- [ ] 场景 A
- [ ] 场景 B
- [ ] 场景 C

### 板块 B: [主题]
Q5. [开放题]
___

## 结尾部分

Q6. [NPS/推荐意愿, 0-10]
0 ___ 1 ___ 2 ___ 3 ___ 4 ___ 5 ___ 6 ___ 7 ___ 8 ___ 9 ___ 10 ___

Q7. [改进建议 — 开放题]
___
EOF

echo "research-report: $(ls templates/research-report/ | wc -l) files"
```

- [ ] **Step 2: 创建 strategy-consulting 模板文件**

```bash
cd /mnt/e/agentguild

# AGENT_FLOW.md
cat > templates/strategy-consulting/AGENT_FLOW.md << 'EOF'
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
EOF

# strategy-brief.md
cat > templates/strategy-consulting/strategy-brief.md << 'EOF'
---
agent: product-manager
consumes: []
produces: strategy-brief
format: markdown
acceptance:
  - 明确战略目标(1 句话)
  - 定义范围和约束
  - 成功指标可量化
handoff_to: ux-researcher
---

# 策略简报

## 战略问题
_一句话描述需要解决的战略问题_

## 目标
- 短期 (3个月): ___
- 中期 (1年): ___
- 长期 (3年): ___

## 范围
- 在范围内: ___
- 不在范围内: ___

## 约束
- 预算: ___
- 时间: ___
- 人力: ___
- 其他: ___

## 成功指标
| 指标 | 当前值 | 目标值 | 时间框架 |
|------|--------|--------|----------|
| ___ | ___ | ___ | ___ |
EOF

# bmc-canvas.md
cat > templates/strategy-consulting/bmc-canvas.md << 'EOF'
---
agent: product-manager
consumes:
  - from: ux-researcher
    deliverable: market-insights
produces: business-model-canvas
format: markdown
acceptance:
  - 9 个模块全部填满
  - 每个模块 2-4 个要点
  - 收入与成本结构自洽
handoff_to: growth-hacker
---

# 商业模式画布 (BMC)

## 1. 客户细分
- ___
- ___

## 2. 价值主张
- ___
- ___

## 3. 渠道
- ___
- ___

## 4. 客户关系
- ___
- ___

## 5. 收入来源
- ___
- ___

## 6. 核心资源
- ___
- ___

## 7. 关键业务
- ___
- ___

## 8. 重要伙伴
- ___
- ___

## 9. 成本结构
- ___
- ___

## 检验
- [ ] 收入 ≥ 成本 × 1.3？
- [ ] 价值主张是否匹配客户痛点？
EOF

# gtm-checklist.md
cat > templates/strategy-consulting/gtm-checklist.md << 'EOF'
---
agent: growth-hacker
consumes:
  - from: data-analyst
    deliverable: market-analysis
produces: gtm-plan
format: markdown
acceptance:
  - 覆盖产品/定价/渠道/促销 4P
  - 每个渠道有预估获客成本
  - 含时间线(前3个月按周)
handoff_to: financial-analyst
---

# GTM 上市清单

## 产品 (Product)
- [ ] MVP 功能清单确认
- [ ] 核心差异化卖点 (3 个)
- [ ] 产品命名 + 一句话简介

## 定价 (Pricing)
- [ ] 定价策略: [免费增值/订阅/一次性/使用量]
- [ ] 价格点: 入门___ / 标准___ / 企业___
- [ ] 竞品价格对比

## 渠道 (Place)
- [ ] 渠道 1: ___ — 预估 CAC: ___
- [ ] 渠道 2: ___ — 预估 CAC: ___
- [ ] 渠道 3: ___ — 预估 CAC: ___

## 促销 (Promotion)
- [ ] 冷启动策略
- [ ] 内容营销计划
- [ ] KOL/合作伙伴

## 时间线

| 周次 | 里程碑 | 负责人 |
|------|--------|--------|
| W1 | ___ | ___ |
| W2 | ___ | ___ |
| W3-4 | ___ | ___ |
| W5-8 | ___ | ___ |
| W9-12 | ___ | ___ |
EOF

# exec-summary.md
cat > templates/strategy-consulting/exec-summary.md << 'EOF'
---
agent: content-creator
consumes:
  - from: financial-analyst
    deliverable: financial-model
produces: executive-summary
format: markdown
acceptance:
  - 1 页可读完 (≤800 字)
  - 包含: 问题/方案/市场/财务/风险
  - 每个部分 2-3 句
handoff_to: product-manager
---

# 执行摘要

## 我们解决什么问题
___

## 我们怎么做
___

## 市场机会
- 市场规模 (TAM): ___
- 可获得市场 (SAM): ___
- 目标市场 (SOM): ___

## 商业模式
- 收入来源: ___
- 单位经济学: CAC ___ / LTV ___
- 盈亏平衡: ___ 个月

## 竞争优势
1. ___
2. ___

## 财务预测
| 年度 | 收入 | 成本 | 利润 |
|------|------|------|------|
| Y1 | ___ | ___ | ___ |
| Y2 | ___ | ___ | ___ |
| Y3 | ___ | ___ | ___ |

## 关键风险
1. ___ — 缓解: ___
2. ___ — 缓解: ___

## 我们要什么
- 融资: ___ (出让 ___%)
- 团队: ___ 人
- 时间: ___ 个月到 MVP
EOF

# swot-analysis.md
cat > templates/strategy-consulting/swot-analysis.md << 'EOF'
---
agent: ux-researcher
consumes:
  - from: product-manager
    deliverable: strategy-brief
produces: swot-analysis
format: markdown
acceptance:
  - 四象限各 3-5 条
  - 每条有证据或推理依据
  - SO/WO/ST/WT 策略各 1 条
handoff_to: data-analyst
---

# SWOT 分析

## 优势 (Strengths) — 内部/有利
1. ___
2. ___
3. ___

## 劣势 (Weaknesses) — 内部/不利
1. ___
2. ___
3. ___

## 机会 (Opportunities) — 外部/有利
1. ___
2. ___
3. ___

## 威胁 (Threats) — 外部/不利
1. ___
2. ___
3. ___

## 策略矩阵

| | 优势 | 劣势 |
|------|------|------|
| **机会** | SO: ___ | WO: ___ |
| **威胁** | ST: ___ | WT: ___ |
EOF

echo "strategy-consulting: $(ls templates/strategy-consulting/ | wc -l) files"
```

- [ ] **Step 3: 创建 brand-identity 和 content-project 模板**

```bash
cd /mnt/e/agentguild

# brand-identity AGENT_FLOW.md
cat > templates/brand-identity/AGENT_FLOW.md << 'EOF'
---
agent: brand-guardian
consumes: []
produces: agent-flow-doc
format: markdown
acceptance:
  - 完整 Agent 接力链
  - 每阶段输入输出清晰
handoff_to: creative-director
---

# AgentGraph 工作流 — 品牌设计

## 接力链
```
brand-guardian      品牌定位+品牌基因
    ↓
creative-director   创意方向+视觉策略
    ↓
ui-designer         色彩/字体/视觉系统
    ↓
content-creator     品牌文案+调性指南
    ↓
brand-guardian      审核+发布品牌手册
```
EOF

# brand-guide.md
cat > templates/brand-identity/brand-guide.md << 'EOF'
---
agent: brand-guardian
consumes: []
produces: brand-guide
format: markdown
acceptance:
  - 包含品牌定位/调性/受众/价值观
  - 品牌人格描述具体(可用"品牌原型"框架)
  - 有"品牌不是什么"的边界描述
handoff_to: creative-director
---

# 品牌手册

## 品牌核心
- 品牌名: ___
- 一句话: ___
- 品牌原型: [天真者/探险家/智者/英雄/ outlaw/魔法师/凡人/情人/小丑/照顾者/创造者/统治者]

## 品牌定位
- 目标受众: ___
- 核心价值: ___
- 差异化: ___
- RTB (相信理由): ___

## 品牌调性
- 是: ___
- 不是: ___

## 品牌人格
- 如果这个品牌是一个人，TA 是: ___
- TA 说话的方式: ___
- TA 不会做的事: ___

## 品牌价值观
1. ___
2. ___
3. ___
EOF

# color-palette.md
cat > templates/brand-identity/color-palette.md << 'EOF'
---
agent: ui-designer
consumes:
  - from: creative-director
    deliverable: creative-direction
produces: color-system
format: markdown
acceptance:
  - 主色/辅色/中性色各 1-3 个
  - 每个颜色有 HEX 和用途说明
  - 包含亮色/暗色模式适配
handoff_to: brand-guardian
---

# 色彩系统

## 主色 (Primary)
| 色块 | HEX | 用途 |
|------|-----|------|
| ██ | `#_____` | 主按钮、品牌标识 |
| ██ | `#_____` | 悬停态 |
| ██ | `#_____` | 点击态 |

## 辅色 (Secondary)
| 色块 | HEX | 用途 |
|------|-----|------|
| ██ | `#_____` | 强调元素 |
| ██ | `#_____` | 辅助图标 |

## 中性色 (Neutral)
| 色块 | HEX | 用途 |
|------|-----|------|
| ██ | `#_____` | 标题文字 |
| ██ | `#_____` | 正文文字 |
| ██ | `#_____` | 辅助文字 |
| ██ | `#_____` | 背景 |
| ██ | `#_____` | 分割线 |

## 语义色
| 语义 | HEX | 用途 |
|------|-----|------|
| 成功 | `#_____` | 正向反馈 |
| 警告 | `#_____` | 提示信息 |
| 错误 | `#_____` | 危险操作 |
| 信息 | `#_____` | 中性提示 |

## 可访问性
- [ ] 正文对比度 ≥ 4.5:1
- [ ] 大文字对比度 ≥ 3:1
- [ ] 不依赖颜色传达信息
EOF

# typography-spec.md
cat > templates/brand-identity/typography-spec.md << 'EOF'
---
agent: ui-designer
consumes:
  - from: creative-director
    deliverable: creative-direction
produces: typography-system
format: markdown
acceptance:
  - 中文+英文各 1 款字体
  - 包含字号层级(≥5 级)
  - 行高/字重/字间距规范
handoff_to: brand-guardian
---

# 字体规范

## 字体选择

| 用途 | 中文 | 英文 | 备选 |
|------|------|------|------|
| 标题 | ___ | ___ | ___ |
| 正文 | ___ | ___ | ___ |
| 代码 | — | ___ | ___ |

## 字号层级

| 层级 | 字号 | 行高 | 字重 | 用途 |
|------|------|------|------|------|
| H1 | ___px | ___ | Bold | 页面主标题 |
| H2 | ___px | ___ | Semibold | 区块标题 |
| H3 | ___px | ___ | Medium | 子标题 |
| Body | ___px | ___ | Regular | 正文 |
| Caption | ___px | ___ | Regular | 辅助说明 |

## 排版规则
- 段落间距: ___
- 最大行宽: ___ 字符
- 中英文混排间距: ___
EOF

# logo-brief.md
cat > templates/brand-identity/logo-brief.md << 'EOF'
---
agent: creative-director
consumes:
  - from: brand-guardian
    deliverable: brand-guide
produces: logo-brief
format: markdown
acceptance:
  - 包含 Logo 类型/风格/使用场景
  - 有"不要做什么"的约束
  - 参考案例 2-3 个
handoff_to: ui-designer
---

# Logo 设计简报

## 基础信息
- 品牌名: ___
- 标语 (可选): ___
- 行业: ___

## Logo 类型
- [ ] 文字标 (Wordmark)
- [ ] 图形标 (Symbol/Icon)
- [ ] 组合标 (Combination)
- [ ] 徽章标 (Emblem)

## 风格方向
- 风格关键词: ___, ___, ___
- 参考案例:
  1. ___
  2. ___

## 使用场景
- 主要: App 图标 (___×___px)
- 次要: 网站导航栏
- 其他: 社交媒体头像、印刷品

## 约束
- 不要: ___
- 避免: ___

## 交付物
- [ ] 主 Logo (横版 + 竖版)
- [ ] 单色版本
- [ ] Favicon
- [ ] App 图标
- [ ] SVG + PNG (多种尺寸)
EOF

# content-project AGENT_FLOW.md
cat > templates/content-project/AGENT_FLOW.md << 'EOF'
---
agent: product-manager
consumes: []
produces: agent-flow-doc
format: markdown
acceptance:
  - 完整 Agent 接力链
  - 每阶段输入输出清晰
handoff_to: tech-writer
---

# AgentGraph 工作流 — 内容项目

## 接力链
```
product-manager      定义内容策略+目标受众
    ↓
tech-writer          撰写内容(技术文档/白皮书/博客)
    ↓
content-creator      内容优化+视觉增强
    ↓
seo-specialist       SEO 优化+关键词布局
    ↓
product-manager      审核发布
```
EOF

# content-strategy.md
cat > templates/content-project/content-strategy.md << 'EOF'
---
agent: product-manager
consumes: []
produces: content-strategy
format: markdown
acceptance:
  - 包含目标受众/内容类型/分发渠道
  - 有话题矩阵(≥6 个话题)
  - 有内容日历框架
handoff_to: tech-writer
---

# 内容策略

## 目标受众
- 主要受众: ___
- 次要受众: ___
- 他们的信息需求: ___

## 内容类型
| 类型 | 目的 | 频率 | 长度 |
|------|------|------|------|
| 博客 | SEO/获客 | 每周 2 篇 | 1500-2500 字 |
| 白皮书 | 转化 | 每月 1 篇 | 3000-5000 字 |
| 案例 | 信任 | 每月 2 篇 | 1000-1500 字 |
| 社媒 | 互动 | 每天 2 条 | 100-300 字 |

## 话题矩阵

| 话题 | 受众阶段 | 关键词 | 内容形式 |
|------|---------|--------|---------|
| ___ | 认知 | ___ | 博客 |
| ___ | 考虑 | ___ | 白皮书 |
| ___ | 决策 | ___ | 案例 |
| ___ | 留存 | ___ | 教程 |
| ___ | 传播 | ___ | 社媒 |
| ___ | ___ | ___ | ___ |

## 分发渠道
- 自有: 官网博客, 公众号, 邮件
- 付费: SEM, 信息流
- 赢得: SEO, 合作伙伴转载
EOF

# editorial-calendar.md
cat > templates/content-project/editorial-calendar.md << 'EOF'
---
agent: tech-writer
consumes:
  - from: product-manager
    deliverable: content-strategy
produces: editorial-calendar
format: markdown
acceptance:
  - 覆盖 4 周以上
  - 每条有: 话题/类型/关键词/负责人/截止日
handoff_to: content-creator
---

# 内容日历

## 本月

| 日期 | 话题 | 类型 | 目标关键词 | 作者 | 状态 |
|------|------|------|-----------|------|------|
| ___ | ___ | ___ | ___ | ___ | 待写 |
| ___ | ___ | ___ | ___ | ___ | 待审 |
| ___ | ___ | ___ | ___ | ___ | 已发布 |
EOF

# style-guide.md
cat > templates/content-project/style-guide.md << 'EOF'
---
agent: content-creator
consumes:
  - from: tech-writer
    deliverable: content-draft
produces: style-guide
format: markdown
acceptance:
  - 包含语气/用词/格式三大规范
  - 有"推荐写法 vs 避免写法"示例(≥5 组)
handoff_to: seo-specialist
---

# 写作风格指南

## 语气 (Tone)
- 我们是什么: ___ (如: 专业但不冷漠，亲切但不随意)
- 我们不是什么: ___

## 用词规范

| ✅ 推荐 | ❌ 避免 | 原因 |
|---------|---------|------|
| 使用 | 利用 | 更直接 |
| 可以 | 能够 | 更口语化 |
| ___ | ___ | ___ |
| ___ | ___ | ___ |
| ___ | ___ | ___ |

## 格式规范
- 段落: ≤ 3 句话
- 标题: 陈述句，不用问句
- 列表: 3-7 项
- 链接: 描述性锚文本，不用"点击这里"
- 图片: 必须有 alt 文本
EOF

# article-template.md
cat > templates/content-project/article-template.md << 'EOF'
---
agent: tech-writer
consumes:
  - from: product-manager
    deliverable: content-strategy
produces: article-draft
format: markdown
acceptance:
  - 标题含目标关键词
  - 导语 ≤ 3 句，抓人
  - 正文有 2+ 个小标题
  - 结尾有 CTA
handoff_to: content-creator
---

# [文章标题 — 含目标关键词]

> 导语: ___ (2-3 句，说清这篇文章解决什么问题)

## 背景

## 核心内容 1: ___

## 核心内容 2: ___

## 总结

## 下一步 (CTA)
- [ ] ___

---
**元数据**
- 目标关键词: ___
- 字数: ___
- 目标受众: ___
- 作者: ___
- 截止日: ___
EOF

echo "brand-identity: $(ls templates/brand-identity/ | wc -l) files"
echo "content-project: $(ls templates/content-project/ | wc -l) files"
```

- [ ] **Step 4: 验证第一批 4 个模板**

```bash
cd /mnt/e/agentguild
for tmpl in research-report strategy-consulting brand-identity content-project; do
  tmpdir=$(mktemp -d)
  ./guild init --template "$tmpl" "$tmpdir" && echo "[OK] $tmpl ($(find $tmpdir -type f | wc -l) files)" || echo "[FAIL] $tmpl"
  rm -rf "$tmpdir"
done
```
Expected: 4/4 `[OK]`

- [ ] **Step 5: Commit**

```bash
cd /mnt/e/agentguild
git add templates/research-report templates/strategy-consulting templates/brand-identity templates/content-project
git commit -m "feat: 第一批4个文档型模板脚手架(research/strategy/brand/content)

每个文件含 AI 友好的 YAML frontmatter + 验收标准
每个模板含 AGENT_FLOW.md Agent 接力链

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: 第二批 Part A — unity-game + unreal-game 工程模板

**Files:**
- Create: `templates/unity-game/AGENT_FLOW.md`, `Assets/Scenes/Main.unity`, `Assets/Scripts/Core/GameManager.cs`, `Assets/Scripts/Core/AgentFlowHint.cs`, `Packages/manifest.json`, `game-design-doc.md`, `build-checklist.md`
- Create: `templates/unreal-game/AGENT_FLOW.md`, `Source/`, `Content/`, `Config/DefaultEngine.ini`, `game-design-doc.md`, `build-checklist.md`

**Interfaces:**
- Produces: 2 个游戏引擎模板的脚手架

- [ ] **Step 1: 创建 unity-game 模板**

```bash
cd /mnt/e/agentguild

# AGENT_FLOW.md
cat > templates/unity-game/AGENT_FLOW.md << 'EOF'
---
agent: game-designer
consumes: []
produces: agent-flow-doc
format: markdown
acceptance:
  - 完整 Agent 接力链
  - 标注并行环节
handoff_to: unity-developer
---

# AgentGraph 工作流 — Unity 游戏

## 接力链
```
game-designer         GDD + 核心循环
    ↓
    ┌─────────────────┬──────────────────┬─────────────────┬──────────────────┐
    ↓                 ↓                  ↓                 ↓                  ↓
unity-developer   technical-artist   game-ui-designer  game-audio-engineer  monetization-designer
(代码+框架)       (美术+Shader)      (UI+UX)           (音效+BGM)          (变现设计)
    └─────────────────┴──────────────────┴─────────────────┴──────────────────┘
    ↓
game-qa-engineer      测试+bug报告
    ↓ (回路)
unity-developer       修复bug
    ↓
game-producer         发布管理
```
EOF

# GameManager.cs
mkdir -p templates/unity-game/Assets/Scripts/Core
cat > templates/unity-game/Assets/Scripts/Core/GameManager.cs << 'CSEOF'
// AgentGraph Unity Template — GameManager.cs
// Agent: unity-developer
// Consumes: GDD from game-designer
// Produces: core-gameplay-framework
// Handoff_to: game-qa-engineer

using UnityEngine;

/// <summary>
/// Core game manager — singleton entry point.
/// AgentGraph agents extend this skeleton to implement game-specific logic.
/// </summary>
public class GameManager : MonoBehaviour
{
    public static GameManager Instance { get; private set; }

    [Header("Game State")]
    public GameState CurrentState = GameState.Bootstrap;

    [Header("Agent Hooks — implement these per GDD")]
    public bool EnableAnalytics = true;
    public bool EnableIAP = false;
    public bool EnableAds = false;
    public bool EnableLeaderboard = false;

    private void Awake()
    {
        if (Instance != null && Instance != this)
        {
            Destroy(gameObject);
            return;
        }
        Instance = this;
        DontDestroyOnLoad(gameObject);
    }

    private void Start()
    {
        // AgentGraph: replace with game-specific bootstrap
        BootstrapGame();
    }

    private void BootstrapGame()
    {
        // AgentGraph: initialize subsystems
        // - SaveSystem.Load()
        // - AudioManager.Init()
        // - Analytics.Track("game_start")
        // - Tutorial.Show() if first run

        CurrentState = GameState.Running;
        Debug.Log("[AgentGraph] GameManager bootstrapped. Ready for game-specific logic.");
    }

    public void SetState(GameState newState)
    {
        CurrentState = newState;
        Debug.Log($"[AgentGraph] GameState → {newState}");
    }
}

public enum GameState
{
    Bootstrap,
    Loading,
    Running,
    Paused,
    GameOver,
    Victory
}
CSEOF

# AgentFlowHint.cs
cat > templates/unity-game/Assets/Scripts/Core/AgentFlowHint.cs << 'CSEOF'
// AgentGraph Unity Template — AgentFlowHint.cs
// Purpose: Provides inline context for AI agents working on this project.
// Not compiled in release builds.

#if UNITY_EDITOR
using UnityEngine;

/// <summary>
/// Agent context hints — read by AgentGraph agents before starting work.
/// Each region maps to a specific agent's responsibility.
/// </summary>
public static class AgentFlowHint
{
    // ── game-designer ────────────────────────────────────────
    // INPUT:  User's game idea (natural language)
    // OUTPUT: GDD.md (game-design-doc.md in template root)
    // ACCEPTANCE:
    //   - Core loop defined (player action → system response → reward)
    //   - Win/lose conditions explicit
    //   - Target platform capabilities considered

    // ── technical-artist ─────────────────────────────────────
    // INPUT:  GDD.md, art style direction
    // OUTPUT: Materials, Shaders, Prefabs in Assets/Prefabs/
    // ACCEPTANCE:
    //   - Consistent art style across all assets
    //   - Draw calls within mobile/desktop budget
    //   - All materials use project-standard shader

    // ── game-ui-designer ─────────────────────────────────────
    // INPUT:  GDD.md, art style
    // OUTPUT: UI Prefabs, Canvas hierarchy
    // ACCEPTANCE:
    //   - All interactive elements ≥ 44x44px (touch target)
    //   - Color contrast meets WCAG AA

    // ── game-audio-engineer ───────────────────────────────────
    // INPUT:  GDD.md, mood direction
    // OUTPUT: AudioClips in Assets/Resources/Audio/
    // ACCEPTANCE:
    //   - BGM loops seamlessly
    //   - SFX < 200ms latency from trigger

    // ── monetization-designer ─────────────────────────────────
    // INPUT:  GDD.md, player flow
    // OUTPUT: Monetization design doc
    // ACCEPTANCE:
    //   - IAP placement does not break core loop enjoyment
    //   - Ad frequency ≤ 1 per 3 minutes

    // ── game-qa-engineer ──────────────────────────────────────
    // INPUT:  Playable build
    // OUTPUT: Bug report + test coverage report
    // ACCEPTANCE:
    //   - All scenes load without errors
    //   - Core loop completable from start to end
    //   - Edge cases tested (rapid input, low memory, background/foreground)

    // ── game-producer ─────────────────────────────────────────
    // INPUT:  QA-passed build
    // OUTPUT: Release build + store listing
    // ACCEPTANCE:
    //   - All 5 gates passed
    //   - Build size within store limits
}
#endif
CSEOF

# Packages/manifest.json (minimal)
mkdir -p templates/unity-game/Packages
cat > templates/unity-game/Packages/manifest.json << 'EOF'
{
  "dependencies": {
    "com.unity.ugui": "1.0.0",
    "com.unity.textmeshpro": "3.0.0"
  }
}
EOF

# game-design-doc.md
cat > templates/unity-game/game-design-doc.md << 'EOF'
---
agent: game-designer
consumes: []
produces: game-design-document
format: markdown
acceptance:
  - 核心循环清晰(玩家行动→系统响应→奖励)
  - 胜败条件明确
  - 目标平台能力已考虑
handoff_to: unity-developer
---

# 游戏设计文档 (GDD)

## 游戏概述
- 游戏名: ___
- 类型: ___
- 平台: [PC/Mobile/Console/Web]
- 目标受众: ___
- 一句话: ___

## 核心循环
```
玩家行动 → ___ → ___
    ↑              ↓
    └── 奖励 ←──────┘
```

## 核心机制
1. ___
2. ___
3. ___

## 胜败条件
- 胜利: ___
- 失败: ___

## 玩家进度
- 短循环 (< 1 分钟): ___
- 中循环 (1 天): ___
- 长循环 (1 周+): ___

## 变现设计
- 主要方式: [IAP/广告/买断/订阅]
- 付费点: ___
- 不影响体验的边界: ___
EOF

# build-checklist.md
cat > templates/unity-game/build-checklist.md << 'EOF'
---
agent: game-producer
consumes:
  - from: game-qa-engineer
    deliverable: qa-report
produces: release-build
format: markdown
acceptance:
  - 所有 5 关质量门禁通过
  - 构建大小在商店限制内
handoff_to: null
---

# 构建发布清单

## 质量门禁
- [ ] Gate 1: 完整性 — 所有计划功能已实现
- [ ] Gate 2: 语法 — 无编译错误/警告
- [ ] Gate 3: 行为 — 核心循环可玩通
- [ ] Gate 4: 可玩性 — 帧率达标/无崩溃
- [ ] Gate 5: Agent 标准 — 所有 Agent 交接完成

## 平台检查
- [ ] iOS: 构建通过 + TestFlight 就绪
- [ ] Android: APK/AAB 构建通过 + 64位支持
- [ ] Web: WebGL 构建 ≤ ___MB
- [ ] PC: Standalone 构建通过

## 商店素材
- [ ] 图标 (1024×1024)
- [ ] 截图 (≥ 5 张)
- [ ] 宣传视频 (可选)
- [ ] 商店描述 (中文/英文)

## 最终签字
- [ ] game-producer: 发布批准
- [ ] 构建版本号: v___
EOF

# Create placeholder dirs
mkdir -p templates/unity-game/Assets/{Scenes,Prefabs,Resources}
touch templates/unity-game/Assets/Scenes/.gitkeep
touch templates/unity-game/Assets/Prefabs/.gitkeep
touch templates/unity-game/Assets/Resources/.gitkeep
mkdir -p templates/unity-game/ProjectSettings

echo "unity-game: $(find templates/unity-game -type f | wc -l) files"
```

- [ ] **Step 2: 创建 unreal-game 模板**

```bash
cd /mnt/e/agentguild

# AGENT_FLOW.md
cat > templates/unreal-game/AGENT_FLOW.md << 'EOF'
---
agent: game-designer
consumes: []
produces: agent-flow-doc
format: markdown
acceptance:
  - 完整 Agent 接力链
  - 标注并行环节
handoff_to: unreal-developer
---

# AgentGraph 工作流 — Unreal Engine 5 游戏

## 接力链
```
game-designer         GDD + 核心循环 + 世界设定
    ↓
    ┌─────────────────┬──────────────────┬─────────────────┬──────────────────┐
    ↓                 ↓                  ↓                 ↓                  ↓
unreal-developer   technical-artist   game-ui-designer  game-audio-engineer  (narrative-designer)
(C++/蓝图)         (材质/Niagara)     (UMG/UI)         (MetaSounds)         (剧情/对话)
    └─────────────────┴──────────────────┴─────────────────┴──────────────────┘
    ↓
game-qa-engineer      测试+性能分析
    ↓ (回路)
unreal-developer      修复
    ↓
game-producer         打包+发布
```

## 并行说明
- **unreal-developer**: 等待 GDD 完成后立即开始 Gameplay Ability System 搭建
- **technical-artist**: 与 GDD 并行 — 先确定美术风格方向，不需要等完整设计
- **game-audio-engineer**: 可与开发并行 — 音效触发逻辑后期集成
- **narrative-designer**: 仅在剧情驱动游戏时激活
EOF

# game-design-doc.md (UE5 specific)
cat > templates/unreal-game/game-design-doc.md << 'EOF'
---
agent: game-designer
consumes: []
produces: game-design-document
format: markdown
acceptance:
  - 核心循环清晰
  - UE5 特色能力已考虑(Nanite/Lumen/World Partition)
  - 目标硬件规格明确
handoff_to: unreal-developer
---

# 游戏设计文档 (GDD) — Unreal Engine 5

## 游戏概述
- 游戏名: ___
- 类型: ___
- 视角: [第一人称/第三人称/俯视/2D]
- 目标平台: [PC/PS5/Xbox Series]
- 目标帧率: [30/60/120] FPS
- 一句话: ___

## UE5 技术选型
- [ ] Nanite (虚拟几何)
- [ ] Lumen (动态全局光照)
- [ ] World Partition (开放世界)
- [ ] MetaSounds (音频)
- [ ] Niagara (粒子/VFX)
- [ ] Gameplay Ability System (技能系统)
- [ ] Enhanced Input (输入系统)

## 核心循环
```
玩家行动 → ___ → ___
    ↑              ↓
    └── 奖励 ←──────┘
```

## 世界设计
- 地图大小: ___
- 区域数量: ___
- 美术风格方向: ___
- 参考: ___

## 性能目标
| 平台 | 分辨率 | 帧率 | 显存 |
|------|--------|------|------|
| PC | ___ | ___ | ___ |
| PS5 | ___ | ___ | ___ |
EOF

# build-checklist.md
cat > templates/unreal-game/build-checklist.md << 'EOF'
---
agent: game-producer
consumes:
  - from: game-qa-engineer
    deliverable: qa-report
produces: release-build
format: markdown
acceptance:
  - 所有 5 关质量门禁通过
  - 包体大小在商店限制内
  - Shader 编译完成无遗漏
handoff_to: null
---

# 构建发布清单 — Unreal Engine 5

## 质量门禁
- [ ] Gate 1: 完整性
- [ ] Gate 2: 语法 (编译 0 Error)
- [ ] Gate 3: 行为 (核心循环可玩通)
- [ ] Gate 4: 可玩性 (帧率达标/无崩溃)
- [ ] Gate 5: Agent 标准

## UE5 特定检查
- [ ] Shader 编译完成 (无 PSO 遗漏)
- [ ] Cook 完成 (无缺失资产)
- [ ] 包体大小: ___ (目标 ≤ ___)
- [ ] 启动时间: ___ 秒 (目标 ≤ ___)

## 平台检查
- [ ] Windows: 打包通过
- [ ] PS5: 提交通过 (如适用)
- [ ] Xbox: 提交通过 (如适用)

## 最终签字
- [ ] game-producer: 发布批准
- [ ] 构建版本号: v___
EOF

# Config
mkdir -p templates/unreal-game/Source templates/unreal-game/Content templates/unreal-game/Config
cat > templates/unreal-game/Config/DefaultEngine.ini << 'EOF'
; AgentGraph Unreal Engine 5 Template — DefaultEngine.ini
; Agent: unreal-developer
; Consumes: GDD from game-designer
; Produces: project-configuration
; Handoff_to: game-producer

[/Script/EngineSettings.GameMapsSettings]
GameDefaultMap=/Game/Maps/Main.Main
EditorStartupMap=/Game/Maps/Main.Main
EOF

touch templates/unreal-game/Source/.gitkeep
touch templates/unreal-game/Content/.gitkeep

echo "unreal-game: $(find templates/unreal-game -type f | wc -l) files"
```

- [ ] **Step 3: 验证两个游戏模板**

```bash
cd /mnt/e/agentguild
for tmpl in unity-game unreal-game; do
  tmpdir=$(mktemp -d)
  ./guild init --template "$tmpl" "$tmpdir" && echo "[OK] $tmpl" || echo "[FAIL] $tmpl"
  rm -rf "$tmpdir"
done
```
Expected: 2/2 `[OK]`

- [ ] **Step 4: Commit**

```bash
cd /mnt/e/agentguild
git add templates/unity-game templates/unreal-game
git commit -m "feat: unity-game + unreal-game 工程模板脚手架

Unity: GameManager.cs + AgentFlowHint.cs + GDD模板 + 构建清单
Unreal: DefaultEngine.ini + UE5特有GDD + 构建清单

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: 第二批 Part B — visual-design + infra-project + ai-ml-project

**Files:**
- 见下方各步

- [ ] **Step 1: visual-design 模板**

```bash
cd /mnt/e/agentguild

cat > templates/visual-design/AGENT_FLOW.md << 'EOF'
---
agent: creative-director
consumes: []
produces: agent-flow-doc
format: markdown
acceptance:
  - 完整 Agent 接力链
handoff_to: ui-designer
---

# AgentGraph 工作流 — 视觉设计

## 接力链
```
creative-director    创意方向+视觉策略
    ↓
ui-designer          视觉设计执行(海报/物料/社媒图)
    ↓
brand-guardian       品牌一致性审核
    ↓
content-creator      文案配合+最终导出
    ↓
creative-director    终审交付
```
EOF

cat > templates/visual-design/poster-template.md << 'EOF'
---
agent: ui-designer
consumes:
  - from: creative-director
    deliverable: creative-brief
produces: poster-design
format: markdown
acceptance:
  - 包含尺寸/出血/色彩模式/分辨率
  - 有内容层级(主标题/副标题/正文/CTA)
  - 品牌元素已标注
handoff_to: brand-guardian
---

# 海报设计简报

## 基础信息
- 项目名: ___
- 尺寸: ___ × ___ mm (+ 3mm 出血)
- 色彩模式: [CMYK/专色]
- 分辨率: 300 DPI

## 内容层级
1. 主标题 (Hero): ___
2. 副标题: ___
3. 正文: ___
4. CTA: ___

## 品牌元素
- Logo: [位置: ___]
- 品牌色: ___
- 字体: ___

## 参考
1. ___
2. ___
EOF

cat > templates/visual-design/print-spec.md << 'EOF'
---
agent: ui-designer
consumes: []
produces: print-specification
format: markdown
acceptance:
  - 包含尺寸/出血/安全区/色彩模式
  - 包含文件格式+命名规范
handoff_to: brand-guardian
---

# 印刷规格

## 通用规格
- 出血: 3mm (标准)
- 安全区: 距离边缘 ≥ 5mm
- 分辨率: ≥ 300 DPI
- 色彩模式: CMYK (印刷) / RGB (屏幕)

## 文件格式
- 交付: AI/EPS/PDF (矢量优先)
- 预览: JPG/PNG

## 命名规范
`[项目名]_[物料类型]_[尺寸]_[版本].[扩展名]`
例如: `brand_poster_A3_v2.pdf`
EOF

cat > templates/visual-design/social-media-template.md << 'EOF'
---
agent: ui-designer
consumes:
  - from: creative-director
    deliverable: creative-brief
produces: social-media-assets
format: markdown
acceptance:
  - 覆盖主要社媒平台尺寸
  - 每个尺寸有安全区标注
handoff_to: content-creator
---

# 社媒图片规格

| 平台 | 类型 | 尺寸 (px) | 比例 |
|------|------|-----------|------|
| 公众号 | 封面 | 900×383 | 2.35:1 |
| 公众号 | 次条 | 200×200 | 1:1 |
| 小红书 | 封面 | 1080×1440 | 3:4 |
| 抖音 | 封面 | 1080×1920 | 9:16 |
| 朋友圈 | 海报 | 1080×1920 | 9:16 |
| LinkedIn | 封面 | 1128×191 | 5.9:1 |
EOF

cat > templates/visual-design/asset-checklist.md << 'EOF'
---
agent: creative-director
consumes:
  - from: ui-designer
    deliverable: design-assets
produces: asset-delivery
format: markdown
acceptance:
  - 所有文件格式正确
  - 命名规范一致
handoff_to: null
---

# 交付物清单

| 物料 | 尺寸 | 格式 | 状态 |
|------|------|------|------|
| 海报 | ___ | PDF | [ ] |
| 社媒图 | ___ | PNG | [ ] |
| 印刷源文件 | ___ | AI | [ ] |

- [ ] 品牌色一致性检查
- [ ] 字体嵌入/转曲检查
- [ ] 图片分辨率 ≥ 300DPI
EOF

echo "visual-design: $(ls templates/visual-design/ | wc -l) files"
```

- [ ] **Step 2: infra-project 模板**

```bash
cd /mnt/e/agentguild

cat > templates/infra-project/AGENT_FLOW.md << 'EOF'
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
EOF

mkdir -p templates/infra-project/docker templates/infra-project/terraform templates/infra-project/.github/workflows

cat > templates/infra-project/docker/Dockerfile.template << 'EOF'
# AgentGraph Infrastructure Template
# Agent: devops-engineer
# Consumes: service architecture from backend-architect
# Produces: docker-image
# Handoff_to: qa-engineer

FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --production
COPY . .

FROM node:20-alpine
WORKDIR /app
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1
USER node
CMD ["node", "dist/main.js"]
EOF

cat > templates/infra-project/docker/docker-compose.template.yml << 'EOF'
# AgentGraph Infrastructure Template
version: "3.8"
services:
  app:
    build: .
    ports:
      - "${PORT:-3000}:3000"
    environment:
      - NODE_ENV=production
    depends_on:
      db:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "--spider", "http://localhost:3000/health"]
      interval: 30s
      timeout: 3s
      retries: 3

  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: ${DB_NAME}
      POSTGRES_USER: ${DB_USER}
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DB_USER}"]
      interval: 10s
      timeout: 3s
      retries: 5

volumes:
  pgdata:
EOF

cat > templates/infra-project/terraform/main.tf.template << 'EOF'
# AgentGraph Infrastructure Template — Terraform
# Agent: devops-engineer
# Produces: cloud-infrastructure
# Handoff_to: security-engineer

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

# VPC + Networking
# Security groups
# Compute (ECS/EKS/EC2)
# Database (RDS)
# CDN (CloudFront)
# DNS (Route53)
EOF

cat > templates/infra-project/.github/workflows/deploy.yml.template << 'EOF'
# AgentGraph CI/CD Template
name: Deploy
on:
  push:
    branches: [main]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm ci
      - run: npm test
  build-and-push:
    needs: test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build Docker image
        run: docker build -t app:${{ github.sha }} .
      - name: Push to registry
        run: |
          # Configure registry push here
          echo "Push complete"
  deploy:
    needs: build-and-push
    runs-on: ubuntu-latest
    steps:
      - name: Deploy
        run: |
          # Deploy to production here
          echo "Deploy complete"
EOF

cat > templates/infra-project/architecture-decision-record.md << 'EOF'
---
agent: backend-architect
consumes:
  - from: devops-engineer
    deliverable: ci-cd-pipeline
produces: architecture-decision
format: markdown
acceptance:
  - 包含背景/决策/后果三部分
  - 标注考虑的替代方案
handoff_to: security-engineer
---

# ADR: [标题]

## 背景
___

## 决策
我们决定 ___

## 考虑的替代方案
1. ___ — 不选因为 ___
2. ___ — 不选因为 ___

## 后果
- 正面: ___
- 负面: ___
- 缓解: ___
EOF

echo "infra-project: $(find templates/infra-project -type f | wc -l) files"
```

- [ ] **Step 3: ai-ml-project 模板**

```bash
cd /mnt/e/agentguild

cat > templates/ai-ml-project/AGENT_FLOW.md << 'EOF'
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
EOF

mkdir -p templates/ai-ml-project/src templates/ai-ml-project/data templates/ai-ml-project/configs

cat > templates/ai-ml-project/src/train.py.template << 'EOF'
"""
AgentGraph AI/ML Template — train.py
Agent: ai-engineer
Consumes: labeled data from data/ directory
Produces: trained-model
Handoff_to: backend-architect
"""
import argparse
import json
import os
from pathlib import Path

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default="configs/model-config.yaml")
    parser.add_argument("--data-dir", default="data/")
    parser.add_argument("--output-dir", default="models/")
    args = parser.parse_args()

    # TODO: AgentGraph AI engineer — implement training logic here
    # 1. Load config
    # 2. Load and preprocess data
    # 3. Initialize model
    # 4. Train with validation
    # 5. Save model + metrics

    print("[AgentGraph] Training pipeline initialized.")
    print(f"  Config: {args.config}")
    print(f"  Data: {args.data_dir}")
    print(f"  Output: {args.output_dir}")

if __name__ == "__main__":
    main()
EOF

cat > templates/ai-ml-project/src/inference.py.template << 'EOF'
"""
AgentGraph AI/ML Template — inference.py
Agent: backend-architect
Consumes: trained model from models/
Produces: inference-api
Handoff_to: qa-engineer
"""
from pathlib import Path

def load_model(model_path: str):
    """Load trained model from disk."""
    # TODO: Implement model loading
    pass

def predict(model, input_data):
    """Run inference on input."""
    # TODO: Implement inference
    pass

if __name__ == "__main__":
    print("[AgentGraph] Inference service ready.")
EOF

cat > templates/ai-ml-project/data/README.md << 'EOF'
---
agent: ai-engineer
consumes: []
produces: data-readme
format: markdown
acceptance:
  - 说明数据来源和格式
  - 标注数据质量和偏置
handoff_to: data-analyst
---

# 数据目录

## 数据来源
- 来源: ___
- 采集时间: ___
- 数据量: ___

## 数据格式
- 训练集: `train.*` (___% )
- 验证集: `val.*` (___% )
- 测试集: `test.*` (___% )

## 数据质量
- 缺失值: ___% 
- 类别平衡: ___
- 已知偏置: ___
EOF

cat > templates/ai-ml-project/configs/model-config.yaml.template << 'EOF'
# AgentGraph AI/ML Template — Model Config
# Agent: ai-engineer
# Produces: model-configuration

model:
  type: ""                    # e.g., "bert-base", "gpt2", "resnet50"
  pretrained: true
  num_labels: 2

training:
  batch_size: 32
  learning_rate: 2e-5
  epochs: 3
  warmup_steps: 500
  weight_decay: 0.01
  max_grad_norm: 1.0

data:
  max_seq_length: 512
  train_split: 0.8
  shuffle: true
  seed: 42

output:
  save_steps: 500
  eval_steps: 500
  logging_steps: 100
  metric: "accuracy"
EOF

cat > templates/ai-ml-project/requirements.txt.template << 'EOF'
# AgentGraph AI/ML Template — requirements.txt
# Agent: ai-engineer
# Produces: python-dependencies

torch>=2.0.0
transformers>=4.30.0
datasets>=2.12.0
scikit-learn>=1.3.0
pandas>=2.0.0
numpy>=1.24.0
pyyaml>=6.0
tqdm>=4.65.0
wandb>=0.15.0
fastapi>=0.100.0
uvicorn>=0.22.0
EOF

cat > templates/ai-ml-project/model-card.md << 'EOF'
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
EOF

echo "ai-ml-project: $(find templates/ai-ml-project -type f | wc -l) files"
```

- [ ] **Step 4: 验证所有第二批模板**

```bash
cd /mnt/e/agentguild
for tmpl in visual-design infra-project ai-ml-project unity-game unreal-game; do
  tmpdir=$(mktemp -d)
  ./guild init --template "$tmpl" "$tmpdir" && echo "[OK] $tmpl ($(find $tmpdir -type f | wc -l) files)" || echo "[FAIL] $tmpl"
  rm -rf "$tmpdir"
done
```
Expected: 5/5 `[OK]`

- [ ] **Step 5: Commit**

```bash
cd /mnt/e/agentguild
git add templates/visual-design templates/infra-project templates/ai-ml-project
git commit -m "feat: visual-design + infra-project + ai-ml-project 模板脚手架

visual-design: 海报/印刷/社媒规格 + 交付清单
infra-project: Docker/Terraform/CI-CD 模板
ai-ml-project: train/inference 脚本骨架 + Model Card

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 5: 自测扩展 + 验证

**Files:**
- Modify: `scripts/self-test.sh`

- [ ] **Step 1: 添加模板完整性测试 (Test 11)**

在 `scripts/self-test.sh` 的 `test_plan_output` 之后添加：

```bash
# ═══════════════════════════════════════════════════════════════════════
# Test 11: template completeness
# ═══════════════════════════════════════════════════════════════════════
test_template_completeness() {
  echo ""
  echo "── Test 11: template completeness ──"

  local tmpl_dir="$REPO_ROOT/templates"
  local all_ok=true

  # All 18 templates must have template.json + README.md + AGENT_FLOW.md
  for tmpl in "$tmpl_dir"/*/; do
    local name; name=$(basename "$tmpl")
    local template_json="$tmpl/template.json"
    local readme="$tmpl/README.md"
    local agent_flow="$tmpl/AGENT_FLOW.md"

    if [[ ! -f "$template_json" ]]; then
      fail "template $name: missing template.json"
      all_ok=false
    fi
    if [[ ! -f "$readme" ]]; then
      fail "template $name: missing README.md"
      all_ok=false
    fi
    if [[ ! -f "$agent_flow" ]]; then
      fail "template $name: missing AGENT_FLOW.md"
      all_ok=false
    fi

    # Verify template.json is valid JSON
    if [[ -f "$template_json" ]]; then
      node -e "JSON.parse(require('fs').readFileSync('$template_json','utf8'))" 2>/dev/null || {
        fail "template $name: template.json is invalid JSON"
        all_ok=false
      }
    fi
  done

  if $all_ok; then
    pass "template completeness: all 18 templates have template.json + README.md + AGENT_FLOW.md"
  fi
}
```

在 `test_plan_output || true` 之后添加：
```bash
test_template_completeness || true
```

- [ ] **Step 2: 运行完整自测**

```bash
cd /mnt/e/agentguild && bash scripts/self-test.sh
```
Expected: 18 passed, 0 failed / 18 total

- [ ] **Step 3: Commit**

```bash
cd /mnt/e/agentguild
git add scripts/self-test.sh
git commit -m "test: 模板完整性自测 — 18个模板的template.json+README+AGENT_FLOW验证

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 6: 文档更新

**Files:**
- Modify: `ai-manifest.json` (更新 template 列表)
- Modify: `README_zh-CN.md` (更新模板数量描述)

- [ ] **Step 1: 更新文档**

```bash
cd /mnt/e/agentguild

# Update ai-manifest.json templates list if stale
# Verify: node -e "JSON.parse(require('fs').readFileSync('ai-manifest.json','utf8'))" && echo "OK"

# Update README if needed
```

- [ ] **Step 2: 最终自测**

```bash
cd /mnt/e/agentguild && bash scripts/self-test.sh
```
Expected: 全部通过

- [ ] **Step 3: Commit**

```bash
cd /mnt/e/agentguild
git add ai-manifest.json README_zh-CN.md
git commit -m "docs: v0.4 模板脚手架文档同步

Co-Authored-By: Claude <noreply@anthropic.com>"
```
