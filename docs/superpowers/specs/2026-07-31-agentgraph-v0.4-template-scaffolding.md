# AgentGraph v0.4 — 模板脚手架填充 + AI 友好度升级

**日期**: 2026-07-31
**版本**: v0.4.0
**状态**: 设计完成，待实现

---

## 1. 目标

将 v0.3 新增的 9 个空模板壳填充为可直接使用的项目脚手架，同时建立 AI Agent 友好的元数据规范，确保 AI 打开任何模板文件都能立即知道：产出什么、什么格式、什么标准、交给谁。

---

## 2. 分批策略

### 第一批（文档/策略型，轻量）
`research-report` | `strategy-consulting` | `brand-identity` | `content-project`

### 第二批（工程/代码型，重量）
`unity-game` | `unreal-game` | `visual-design` | `infra-project` | `ai-ml-project`

---

## 3. AI 友好元数据规范

每个模板文件头部必须包含 YAML frontmatter：

```yaml
---
agent: ux-researcher           # 谁负责产出
consumes:                       # 上游交付物
  - from: product-manager
    deliverable: research-brief
produces: user-personas         # 产出物名称
format: markdown                 # 输出格式
acceptance:                      # 验收标准
  - 至少 3 个用户画像
  - 每个画像包含: 人口统计/行为模式/痛点/目标
  - 数据来源标注
handoff_to: data-analyst        # 交给谁
---
```

### 设计原则
- AI 打开文件 → 读 frontmatter → 知道全部上下文，不需要额外解释
- `acceptance` 是硬标准，AI 输出必须逐条满足
- `handoff_to` 让 Agent 知道产出后自动推送给谁

---

## 4. 第一批模板文件结构

### 4.1 research-report（研究报告）
```
templates/research-report/
├── template.json
├── README.md
├── AGENT_FLOW.md            ← Agent 接力链
├── report-outline.md         ← 报告大纲模板
├── methodology-guide.md      ← 调研方法指南
├── personas-template.md      ← 用户画像模板
├── findings-template.md      ← 调研发现+建议模板
└── survey-template.md        ← 问卷设计模板
```

AGENT_FLOW: `product-manager → ux-researcher → data-analyst → tech-writer → product-manager(审核)`

### 4.2 strategy-consulting（策略咨询）
```
templates/strategy-consulting/
├── template.json
├── README.md
├── AGENT_FLOW.md
├── strategy-brief.md         ← 策略摘要模板
├── bmc-canvas.md             ← 商业模式画布
├── gtm-checklist.md          ← GTM上市清单
├── exec-summary.md           ← 高管汇报摘要
└── swot-analysis.md          ← SWOT分析模板
```

AGENT_FLOW: `product-manager → ux-researcher → data-analyst → growth-hacker → financial-analyst → content-creator`

### 4.3 brand-identity（品牌设计）
```
templates/brand-identity/
├── template.json
├── README.md
├── AGENT_FLOW.md
├── brand-guide.md            ← 品牌手册大纲
├── color-palette.md          ← 色彩系统模板
├── typography-spec.md        ← 字体规范模板
└── logo-brief.md             ← Logo设计简报
```

AGENT_FLOW: `brand-guardian → creative-director → ui-designer → content-creator → brand-guardian(审核)`

### 4.4 content-project（内容项目）
```
templates/content-project/
├── template.json
├── README.md
├── AGENT_FLOW.md
├── content-strategy.md       ← 内容策略
├── editorial-calendar.md     ← 内容日历
├── style-guide.md            ← 写作风格指南
└── article-template.md       ← 文章/白皮书模板
```

AGENT_FLOW: `product-manager → tech-writer → content-creator → seo-specialist → product-manager(审核)`

---

## 5. 第二批模板文件结构

### 5.1 unity-game（Unity游戏）
```
templates/unity-game/
├── template.json
├── README.md
├── AGENT_FLOW.md
├── Assets/
│   ├── Scenes/Main.unity
│   ├── Scripts/Core/GameManager.cs
│   ├── Scripts/Core/AgentFlowHint.cs
│   ├── Prefabs/
│   └── Resources/
├── Packages/manifest.json
├── ProjectSettings/
├── game-design-doc.md        ← GDD模板
└── build-checklist.md        ← 构建发布清单
```

AGENT_FLOW: `game-designer → [unity-developer|technical-artist|game-ui-designer|game-audio-engineer] → monetization-designer → game-qa-engineer → game-producer`

### 5.2 unreal-game（Unreal 游戏）
```
templates/unreal-game/
├── template.json
├── README.md
├── AGENT_FLOW.md
├── Source/
├── Content/
├── Config/DefaultEngine.ini
├── game-design-doc.md
└── build-checklist.md
```

AGENT_FLOW: `game-designer → [unreal-developer|technical-artist|game-ui-designer|game-audio-engineer] → game-qa-engineer → game-producer`

### 5.3 visual-design（视觉设计）
```
templates/visual-design/
├── template.json
├── README.md
├── AGENT_FLOW.md
├── poster-template.md        ← 海报简报
├── print-spec.md             ← 印刷规格
├── social-media-template.md  ← 社媒图片规格
└── asset-checklist.md        ← 交付物清单
```

AGENT_FLOW: `creative-director → ui-designer → brand-guardian → content-creator → creative-director(审核)`

### 5.4 infra-project（基础设施）
```
templates/infra-project/
├── template.json
├── README.md
├── AGENT_FLOW.md
├── docker/Dockerfile.template
├── docker/docker-compose.template.yml
├── terraform/main.tf.template
├── .github/workflows/deploy.yml.template
└── architecture-decision-record.md
```

AGENT_FLOW: `devops-engineer → [backend-architect|security-engineer] → qa-engineer → devops-engineer(验收)`

### 5.5 ai-ml-project（AI/ML项目）
```
templates/ai-ml-project/
├── template.json
├── README.md
├── AGENT_FLOW.md
├── src/train.py.template
├── src/inference.py.template
├── data/README.md
├── configs/model-config.yaml.template
├── requirements.txt.template
└── model-card.md
```

AGENT_FLOW: `ai-engineer → backend-architect → data-analyst → qa-engineer → devops-engineer → ai-engineer(验收)`

---

## 6. 实现任务

| # | 任务 | 说明 |
|---|------|------|
| 1 | 元数据规范落地 | 所有模板文件添加 YAML frontmatter (agent/consumes/produces/acceptance/handoff_to) |
| 2 | 第一批 4 个模板 | research-report, strategy-consulting, brand-identity, content-project 脚手架填充 |
| 3 | 第二批 5 个模板 | unity-game, unreal-game, visual-design, infra-project, ai-ml-project 脚手架填充 |
| 4 | AGENT_FLOW.md 生成 | 每个模板的 Agent 接力链文档 |
| 5 | 自测扩展 | 验证 guild init 所有 18 个模板 + 元数据 frontmatter 解析 |
| 6 | 文档更新 | ai-manifest.json + README 同步 |

---

## 7. 成功标准

- [ ] 所有 18 个模板都有完整脚手架（非空壳）
- [ ] 每个模板文件都有 YAML frontmatter 元数据
- [ ] 每个模板都有 AGENT_FLOW.md
- [ ] `guild init --template <name>` 对所有 18 种类型可用
- [ ] 自测通过，无回归
