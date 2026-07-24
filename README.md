# 🎭 AgentGuild

<p align="center">
  <img src="https://img.shields.io/github/stars/1685yhy/agentguild?style=for-the-badge&color=3B82F6" alt="GitHub Stars">
  <img src="https://img.shields.io/github/license/1685yhy/agentguild?style=for-the-badge&color=EC4899" alt="MIT License">
  <img src="https://img.shields.io/badge/PRs-welcome-brightgreen?style=for-the-badge&color=22C55E" alt="PRs Welcome">
  <img src="https://img.shields.io/badge/agents-18-3B82F6?style=for-the-badge" alt="18 Agents">
  <img src="https://img.shields.io/badge/zero_dependencies-Bash_3.2+-D946EF?style=for-the-badge" alt="Zero Dependencies">
</p>

<p align="center">
  <h3 align="center">塑造 AI 队友，而非模板</h3>
</p>

<p align="center">
  <strong>18 个有真实人格的精品 AI Agent + 业界首个真正可用的 Agent 协作引擎</strong><br>
  交接检查 · 流水线编排 · 决策追溯 · 冲突检测 — 不是"你该这么协作"的文档，是让协作自动发生的软件
</p>

<p align="center">
  <a href="#-quick-start">Quick Start</a> ·
  <a href="#-agent-roster">18 Agents</a> ·
  <a href="#-the-collaboration-engine">协作引擎</a> ·
  <a href="#-how-this-compares-to-agency-agents">vs agency-agents</a> ·
  <a href="#-supported-tools">Tools</a> ·
  <a href="README_zh-CN.md">中文</a>
</p>

---

## 这到底是什么？

**AgentGuild 不是一个 Agent 模板库。它是一个 AI 团队的协作操作系统。**

两件事：
1. **18 个精品 Agent** — 每个都有挑衅性观点、会跟人争执、知道自己盲区、明确决策边界。不是一个模板换词 300 次。
2. **一套协作引擎** — `guild` CLI 让 Agent 之间真的能传接球、跑流水线、记录决策、检测冲突。不是 Markdown 文档写"你应该这么协作"。

你已经有 Claude Code / Cursor / Copilot 了。装上 AgentGuild，你就有了一支能配合的 AI 团队。

---

## 为什么你需要这个

用 AI 写代码已经不够了。真正的问题发生在 AI 和 AI 之间。

**PM Agent 写了 PRD 给后端 Agent → 后端照着做了 → 上线后前端发现 API 格式不对 → 谁的问题？**

agency-agents 的答案是"Phase 4 才发现，回去重做"。

AgentGuild 的答案是：**后端动手之前，系统就告诉他"前端依赖这个 API，你的决策会影响他"。如果双方做了矛盾的决策，系统自动报警。每次交接自动检查完整性，缺东西当场就拦。**

这就是 Agent 协作和"把 Agent 放一起然后祈祷"的区别。

---

## 快速开始

```bash
# 1. 克隆
git clone https://github.com/1685yhy/agentguild.git
cd agentguild

# 2. 安装 Agent 到你的 AI 工具
./scripts/convert.sh
./scripts/install.sh --tool claude-code

# 3. 开始用
# 在 Claude Code 里说："激活产品经理模式，帮我写一份 PRD"

# 4. 试试协作引擎
./guild handoff --from 产品经理 --to 后端架构师 --path ./prd/
./guild run --pipeline feature-dev --path ./project/ --yes
```

---

## Agent 名册

### 工程

| | Agent | 一句话 |
|---|-------|--------|
| 🖥️ | **Frontend Engineer** | 框架选型是最不重要的事。先把 CI 修好 |
| 🗄️ | **Backend Architect** | 微服务被严重滥用了。50 人以下团队用单体 |
| 🚀 | **DevOps Engineer** | 超过 10 分钟的 CI 流水线就是坏掉的 |
| 🤖 | **AI Engineer** | 最好的 AI 功能是你没做的那一个 |

### 产品

| | Agent | 一句话 |
|---|-------|--------|
| 📋 | **Product Manager** | 大多数 MVP 既不 minimal 也不 viable |
| 🔍 | **UX Researcher** | 糟糕的用户访谈不如不做 |
| 📊 | **Data Analyst** | "数据驱动"通常是直觉驱动然后找数据背书 |
| 📝 | **Tech Writer** | 代码写完再补的文档永远是错的 |

### 设计

| | Agent | 一句话 |
|---|-------|--------|
| 🎨 | **UI Designer** | 一致性被高估了。故意打破规则才是水平 |
| 🛡️ | **Brand Guardian** | 换 logo 解决不了产品烂的问题 |
| 🎬 | **Interaction Designer** | 用户注意到你的动画说明大概率是坏了 |
| 🎯 | **Creative Director** | 委员会设计谁也不得罪也谁都不喜欢 |

### 测试

| | Agent | 一句话 |
|---|-------|--------|
| 🧪 | **QA Engineer** | 不是找 bug，是证明质量存在 |
| ⚡ | **Performance Tester** | 没有前提条件的性能数字就是谎言 |
| ♿ | **Accessibility Auditor** | 无障碍不是检查清单。自动化只能发现 30% |

### 市场

| | Agent | 一句话 |
|---|-------|--------|
| 📈 | **Growth Hacker** | 增长不是 hack，是可复现的系统性实验 |
| ✍️ | **Content Creator** | SEO 优化的垃圾依然是垃圾 |
| 📱 | **Social Media Strategist** | 各平台发一样的内容不是策略，是懒 |

---

## 协作引擎

这是 AgentGuild 区别于所有其他 Agent 项目的核心。

### `guild handoff` — Agent 之间传接球

PM 写完 PRD 传给后端。系统自动检查：后端需要的东西齐全吗？缺了什么？

```bash
$ guild handoff --from pm --to backend --path ./prd/
  创建交接 #1: product-manager → backend-architect
  状态: incomplete
  完整度: 1/3 项已提供
  [!!] 缺失 2 项:
       - 性能目标（QPS、延迟 SLO、并发数）
       - 数据模型草案
```

### `guild run` — 一键跑完全流程

4 个阶段、6 组 Agent 配对、自动交接——**一个命令**。

```bash
$ guild run --pipeline feature-dev --path ./project/ --yes
  ━━━ 阶段: 需求定义 → 设计 ━━━
  ━━━ 阶段: 设计 → 实现 ━━━
  ━━━ 阶段: 实现 → 测试 ━━━
  ━━━ 阶段: 测试 → 审查 ━━━
  流水线完成: feature-dev
```

### `guild decide` + `guild context` — 决策系统

后端做了一个 API 格式决策。前端做了一个矛盾的。系统自动检测。

```bash
$ guild decide --agent backend --type api-design \
  --topic "API响应格式" --summary "统一包裹 {code, data, message}"

$ guild decide --agent frontend --type api-design \
  --topic "API响应格式" --summary "直接返回，不要包裹层"

$ guild context check
  ⚠️ 冲突: API响应格式 — backend vs frontend
```

### `guild status` — 所有交接一目了然

```bash
$ guild status
  ⚠️ #1: pm → backend (incomplete)
  ✅ #2: pm → ux (ready)
  ✔️ #3: frontend → qa (accepted)
```

9 个 CLI 命令，零外部依赖，纯 Bash 实现。完整用法见 [使用指南](docs/使用指南.md)。

---

## 跟 agency-agents 比

| | agency-agents | **AgentGuild** |
|---|---|---|
| Agent 深度 | 一个模板换词 300 次 | 每个有挑衅性观点、冲突偏好、盲区 |
| Agent 质量 | 参差不齐 | 15A + 3A-，lint 强制校验 |
| 协作 | 零 — 人手动复制粘贴 | **handoff → run → decide → context 四层引擎** |
| 冲突检测 | 无 | 自动检测 + 影响范围分析 + 追溯 |
| 流水线 | Markdown 文档 | `guild run` 一键执行 |
| 决策追溯 | 无 | ADR 模式，每次交接可追溯 |
| 分发 | 16 工具 | 4 核心工具（按需扩展） |
| 中文 | 翻译 | **原生中文全链路** |
| 依赖 | Bash+Python | **纯 Bash 3.2+，真正零依赖** |

**AgentGuild 不是 agency-agents 的 fork。** 它是同一个问题（"AI 怎么组队干活"）的下一代答案。agency-agents 证明了"Agent 定义可以模板化"，AgentGuild 证明了**协作可以自动化**。

---

## 支持的工具

| 工具 | 安装 |
|------|------|
| **Claude Code** | `./scripts/install.sh --tool claude-code` |
| **Cursor** | `./scripts/install.sh --tool cursor` |
| **GitHub Copilot** | `./scripts/install.sh --tool copilot` |
| **Windsurf** | `./scripts/install.sh --tool windsurf` |

---

## 项目结构

```
agentguild/
├── agents/          18 个 Agent（工程/产品/设计/测试/市场）
├── scripts/         5 个脚本（lint/convert/install/nexus/lib）
├── contracts/       协作契约 — 从 Agent 第 13 段自动提取
├── pipelines/       流水线定义（YAML）
├── context/         决策记录 — ADR 模式
├── handoffs/        交接记录
├── docs/            5 份中文使用指南 + 模板规范
├── website/         项目官网（单页 HTML）
├── guild            → scripts/nexus.sh（主命令）
└── guild.config.json  18 Agent + 4 工具的中央注册表
```

---

## 每个 Agent 包含什么

不是"你是一个专家"一句话。每个 Agent 13 段：

| # | 段落 | 说明 |
|---|------|------|
| 3 | **挑衅性观点** | 一个跟主流共识相反、但有证据支撑的职业立场 |
| 4 | **铁律** | 不可妥协的原则 |
| 10 | **冲突偏好** | 会在什么情况下说不？会跟谁起争执？ |
| 11 | **盲区声明** | 明确知道自己不擅长什么，主动请求外援 |
| 12 | **决策权重** | 在哪些决策上有最终话语权 |
| 13 | **协作契约** | 承诺交付什么 + 需要从上游收到什么 |

---

## 贡献

欢迎！见 [CONTRIBUTING.md](CONTRIBUTING.md)。一个好的 Agent 需要：真正挑衅的观点（不是废话）+ 诚实且具体的盲区 + 点名其他角色的冲突偏好。

---

## 许可

MIT — 随便用，改，分发。

---

<p align="center">
  <sub>Built with conviction, not consensus. 源自信念，而非共识。</sub>
</p>
