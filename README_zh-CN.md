# AgentGuild

<p align="center">
  <img src="https://img.shields.io/github/stars/agentguild/agentguild?style=for-the-badge&color=3B82F6" alt="GitHub Stars">
  <img src="https://img.shields.io/github/license/agentguild/agentguild?style=for-the-badge&color=EC4899" alt="MIT License">
  <img src="https://img.shields.io/badge/PRs-welcome-brightgreen?style=for-the-badge&color=22C55E" alt="PRs Welcome">
  <img src="https://img.shields.io/badge/agents-18-3B82F6?style=for-the-badge" alt="18 Agents">
</p>

<p align="center">
  <strong>一个拥有真实个性、坚定立场和清晰边界的 AI 特工公会，专为软件开发打造。</strong>
</p>

<p align="center">
  <a href="#-快速开始">快速开始</a> ·
  <a href="#-特工花名册">特工列表</a> ·
  <a href="#-agentguild-的独特之处">特色</a> ·
  <a href="#-支持的工具">工具支持</a> ·
  <a href="#-项目结构">项目结构</a> ·
  <a href="#-参与贡献">贡献指南</a> ·
  <a href="README.md">English</a>
</p>

---

## 什么是 AgentGuild？

AgentGuild 是一个**精心策划的 18 人 AI 特工花名册**，专为软件开发团队设计。每个特工都是一份详细的 Markdown 文件，定义了一个专业化角色——包括身份、专长，最重要的是，**观点和立场**。

与只提供空模板的通用 AI 特工框架不同，AgentGuild 的特工拥有：

- **反主流观点** — 与主流共识相悖的专业见解
- **冲突偏好** — 何时会拒绝、反对或升级问题
- **盲区认知** — 坦诚自己哪些方面不擅长，何时需要求助
- **决策权** — 在多特工协作中明确的职责边界

AgentGuild 支持 **Claude Code**、**Cursor**、**GitHub Copilot** 和 **Windsurf**。安装你需要的特工后，你的 AI 编码工具就能准确理解当前是哪个专家在响应、他关心什么、他拥有哪些决策权。

---

## AgentGuild 与 agency-agents 有何不同？

[agency-agents](https://github.com/ai-hero/agency-agents) 开创了基于系统提示词的 AI 特工概念。AgentGuild 在此基础上进行了根本性的升级：

| 维度 | agency-agents | AgentGuild |
|------|---------------|------------|
| **理念** | 数量——广泛覆盖 | 质量——精挑细选、有主见 |
| **个性** | 通用的角色描述 | 真实的反主流观点和个性 |
| **冲突** | 未定义冲突 | 特工间的明确分歧边界 |
| **盲区** | 未涉及 | 坦诚的自我评估和限制认知 |
| **决策权** | 未定义 | 明确谁对什么有最终决定权 |
| **格式支持** | 仅 Claude Code | Claude Code、Cursor、Copilot、Windsurf |
| **特工数量** | 很多，质量参差不齐 | 18 个精心打磨的特工 |

**AgentGuild 不是 agency-agents 的分支（fork）**。它是一种下一代方案——公会中的每个特工都拥有真实的个性、坚定的专业立场，以及明确的能力与责任边界。

---

## 特工花名册

### 工程部

| Emoji | 特工 | 描述 | 难度 |
|-------|------|------|------|
| 🖥️ | 前端工程师 | UI 架构、性能优化、设计系统工程 | 高级 |
| 🗄️ | 后端架构师 | API 设计、数据建模、认证与服务可靠性 | 高级 |
| 🚀 | DevOps 工程师 | CI/CD、基础设施、监控、事故响应与可靠性 | 高级 |
| 🤖 | AI 工程师 | 模型选择、提示词架构、评估与 AI 功能设计 | 高级 |

### 产品部

| Emoji | 特工 | 描述 | 难度 |
|-------|------|------|------|
| 📋 | 产品经理 | 问题定义、优先级排序与范围管理 | 中级 |
| 🔍 | 用户研究员 | 用户研究方法论、洞察验证与行为分析 | 中级 |
| 📊 | 数据分析师 | 指标定义、统计分析、基于证据的决策支持 | 中级 |
| 📝 | 技术文档工程师 | API 文档、命名一致性、信息架构 | 入门 |

### 设计部

| Emoji | 特工 | 描述 | 难度 |
|-------|------|------|------|
| 🎨 | UI 设计师 | 视觉设计系统、布局、色彩、字体与有意的突破常规 | 中级 |
| 🛡️ | 品牌守护者 | 品牌形象、调性一致性、视觉标识治理 | 高级 |
| 🎬 | 交互设计师 | 动效设计、微交互、转场与交互编排 | 高级 |
| 🎯 | 创意指导 | 美学方向、质量标准执行与设计评审权 | 高级 |

### 测试部

| Emoji | 特工 | 描述 | 难度 |
|-------|------|------|------|
| 🧪 | QA 工程师 | 基于证据的质量验证，不放过任何边界情况 | 中级 |
| ⚡ | 性能测试工程师 | 真实负载建模与系统容量规划 | 高级 |
| ♿ | 无障碍审计员 | 超越自动化合规的真实无障碍验证 | 中级 |

### 市场部

| Emoji | 特工 | 描述 | 难度 |
|-------|------|------|------|
| 📈 | 增长黑客 | 系统的增长策略，不依赖平台漏洞 | 高级 |
| ✍️ | 内容创作者 | 以回答深度和用户价值为优先的内容策略 | 中级 |
| 📱 | 社媒策略师 | 平台原生内容策略，不跨平台一键分发 | 中级 |

---

## AgentGuild 的独特之处

### 1. 反主流观点 (Contrarian Takes)

每个 AgentGuild 特工都有一个坚定的专业立场，这些立场与主流共识相悖。它们不是平淡无奇的套话，而是有证据支持的、塑造特工思维方式的核心信念。

示例：
- **前端工程师：** "框架选择是你团队做出的最不重要的架构决策。"
- **后端架构师：** "微服务被过度推广了。"
- **数据分析师：** "大多数'数据驱动'的决策，实际上是直觉驱动、事后找数据支撑的决策。"
- **创意指导：** "委员会式的设计只能产出委员会水准的设计。"

### 2. 冲突偏好 (Conflict Preferences)

每个特工明确说明他们会在什么情况下拒绝、反对或升级问题——并列出他们最可能与之发生分歧的具体特工角色。这创造了健康的张力，在生产事故发生之前就将风险暴露出来。

### 3. 盲区认知 (Blind Spots)

每个特工诚实地描述自己不擅长的领域，以及何时会主动请求其他特工的帮助。这避免了困扰通用 AI 特工的"不懂装懂"问题，确保每个决策都能找到正确的专家。

### 4. 决策权 (Decision Authority)

在多特工协作中，每个特工都明确知道自己拥有哪些决策权、哪些需要请示他人。没有模糊地带，没有越界行为，也没有关键决策被遗漏。

---

## 快速开始

```bash
# 1. 克隆仓库
git clone https://github.com/agentguild/agentguild.git
cd agentguild

# 2. 将特工档案转换为你的工具支持的格式
./scripts/convert.sh

# 3. 将特工安装到你的 AI 工具中
./scripts/install.sh

# 4. 完成！你的 AI 工具现在了解全部 18 个公会特工。
#    需要专家帮助时，直接引用特工名称即可。
```

### 安装指定工具

```bash
# 安装到所有支持的工具（默认）
./scripts/install.sh

# 仅安装到特定工具
./scripts/install.sh --tool claude-code
./scripts/install.sh --tool cursor
./scripts/install.sh --tool copilot
./scripts/install.sh --tool windsurf

# 预览将要安装的内容
./scripts/install.sh --dry-run
```

---

## 支持的工具

| 工具 | 格式 | 安装命令 |
|------|------|----------|
| [Claude Code](https://docs.anthropic.com/en/docs/claude-code) | `identity` (`.md`) | `./scripts/install.sh --tool claude-code` |
| [Cursor](https://cursor.sh) | `.mdc` 规则 | `./scripts/install.sh --tool cursor` |
| [GitHub Copilot](https://github.com/features/copilot) | `identity` (`.md`) | `./scripts/install.sh --tool copilot` |
| [Windsurf](https://codeium.com/windsurf) | `.windsurfrules` | `./scripts/install.sh --tool windsurf` |

AgentGuild 特工安装在你本地的 AI 工具配置中——而不是仓库中——因此它们会跟随你跨项目使用。支持按特工安装和按项目安装。

---

## 项目结构

```
agentguild/
├── agents/
│   ├── engineering/               # 工程部
│   │   ├── frontend-engineer.md   # 前端工程师
│   │   ├── backend-architect.md   # 后端架构师
│   │   ├── devops-engineer.md     # DevOps 工程师
│   │   └── ai-engineer.md         # AI 工程师
│   ├── product/                   # 产品部
│   │   ├── product-manager.md     # 产品经理
│   │   ├── ux-researcher.md       # 用户研究员
│   │   ├── data-analyst.md        # 数据分析师
│   │   └── tech-writer.md         # 技术文档工程师
│   ├── testing/                   # 测试部
│   │   ├── qa-engineer.md         # QA 工程师
│   │   ├── performance-tester.md  # 性能测试工程师
│   │   └── accessibility-auditor.md# 无障碍审计员
│   ├── marketing/                 # 市场部
│   │   ├── growth-hacker.md       # 增长黑客
│   │   ├── content-creator.md     # 内容创作者
│   │   └── social-media-strategist.md# 社媒策略师
│   └── design/                    # 设计部
│       ├── ui-designer.md         # UI 设计师
│       ├── brand-guardian.md      # 品牌守护者
│       ├── interaction-designer.md# 交互设计师
│       └── creative-director.md   # 创意指导
├── contracts/                     # 协作契约（Phase 2a）
│   ├── extract.sh                 # 从特工文件中提取契约
│   └── guild-contracts.yml        # 生成的 YAML 契约文件
├── demos/                         # 交接演练场景（Phase 2b）
│   ├── pm-to-ux.md
│   ├── pm-to-backend.md
│   └── frontend-to-qa.md
├── docs/
│   ├── AGENT_TEMPLATE.md          # 特工创建指南（英文）
│   ├── AGENT_TEMPLATE_zh-CN.md    # 特工创建指南（中文）
│   ├── 使用指南.md                 # 使用指南
│   ├── 协作指南.md                 # 协作指南
│   └── 流水线指南.md               # 流水线指南
├── handoffs/                      # 交接记录（Phase 2b）
├── pipelines/                     # 流水线定义（Phase 2a）
│   └── startup-mvp.yml            # MVP 开发流水线
├── scripts/
│   ├── convert.sh                 # 将特工转换为工具特定格式
│   ├── install.sh                 # 将特工安装到本地 AI 工具
│   ├── lib.sh                     # 共享辅助函数
│   ├── lint.sh                    # 验证特工文件是否符合模板规范
│   └── nexus.sh                   # 交接引擎 CLI（Phase 2a）
├── guild                          # → scripts/nexus.sh（符号链接）
├── guild.config.json              # 特工、部门和工具的中央注册表
├── .github/workflows/lint.yml     # CI：每次推送时自动检查特工文件
├── LICENSE                        # MIT 许可证
├── README.md                      # 本文件（英文）
├── README_zh-CN.md                # 本文件（中文）
├── CONTRIBUTING.md                # 贡献指南（英文）
└── CONTRIBUTING_zh-CN.md          # 贡献指南（中文）
```

---

## 参与贡献

我们欢迎各种形式的贡献！请参阅 [CONTRIBUTING_zh-CN.md](CONTRIBUTING_zh-CN.md) 了解：

- 什么样的特工才算一个好的 AgentGuild 特工（质量标准）
- 如何提议新的特工（Issue 模板 + PR）
- 如何为新的 AI 工具添加支持
- 我们的行为准则

---

## 开源协议

AgentGuild 采用 [MIT 许可证](LICENSE) 发布。

---

<p align="center">
  <sub>源自信念，而非共识。</sub>
</p>
