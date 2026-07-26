# 🎭 AgentGraph

<p align="center">
  <img src="https://img.shields.io/github/stars/1685yhy/AgentGraph?style=for-the-badge&color=3B82F6" alt="GitHub Stars">
  <img src="https://img.shields.io/github/license/1685yhy/AgentGraph?style=for-the-badge&color=EC4899" alt="MIT License">
  <img src="https://img.shields.io/badge/PRs-welcome-brightgreen?style=for-the-badge&color=22C55E" alt="PRs Welcome">
  <img src="https://img.shields.io/badge/agents-40-3B82F6?style=for-the-badge" alt="40 Agents">
  <img src="https://img.shields.io/badge/Bash_Python3-Bash_3.2++Python3-D946EF?style=for-the-badge" alt="Bash+Python3">
</p>

<p align="center">
  <h3 align="center">塑造 AI 队友，而非模板</h3>
</p>

<p align="center">
  <strong>40 个有真实人格的精品 AI Agent + 业界首个真正可用的 Agent 协作引擎</strong><br>
  交接检查 · 流水线编排 · 决策追溯 · 冲突检测 · 图执行引擎 — 不是"你该这么协作"的文档，是让协作自动发生的软件
</p>

<p align="center">
  <a href="#-快速开始">Quick Start</a> ·
  <a href="#-agent-名册">40 Agents</a> ·
  <a href="#-协作引擎">协作引擎</a> ·
  <a href="#-图引擎">图引擎</a> ·
  <a href="#-跟-agency-agents-比">vs agency-agents</a> ·
  <a href="#-支持的工具">Tools</a> ·
  <a href="README.md">English</a>
</p>

---

## 这到底是什么？

**AgentGraph 不是一个 Agent 模板库。它是一个 AI 团队的协作操作系统。**

两件事：
1. **40 个精品 Agent** — 每个都有挑衅性观点、会跟人争执、知道自己盲区、明确决策边界。不是一个模板换词 300 次。
2. **一套协作引擎** — `guild` CLI 让 Agent 之间真的能传接球、跑流水线、记录决策、检测冲突、按图执行工作流。不是 Markdown 文档写"你应该这么协作"。

你已经有 Claude Code / Cursor / Copilot 了。装上 AgentGraph，你就有了一支能配合的 AI 团队。

---

## 为什么你需要这个

用 AI 写代码已经不够了。真正的问题发生在 AI 和 AI 之间。

**PM Agent 写了 PRD 给后端 Agent → 后端照着做了 → 上线后前端发现 API 格式不对 → 谁的问题？**

agency-agents 的答案是"Phase 4 才发现，回去重做"。

AgentGraph 的答案是：**后端动手之前，系统就告诉他"前端依赖这个 API，你的决策会影响他"。如果双方做了矛盾的决策，系统自动报警。每次交接自动检查完整性，缺东西当场就拦。**

这就是 Agent 协作和"把 Agent 放一起然后祈祷"的区别。

---

## 快速开始

```bash
# 1. 克隆
git clone https://github.com/1685yhy/AgentGraph.git
cd AgentGraph

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
| 📱 | **Mobile Developer** | 跨平台不是捷径，是推迟原生开发的时间点 |
| 🗄️ | **Database Specialist** | ORM 是最危险的抽象——N+1 才是常客 |
| 🔍 | **Code Reviewer** | LGTM 不是审查，是橡皮图章 |

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
| 🔍 | **SEO Specialist** | SEO 不是游戏 Google，是成为最佳答案 |

### 安全

| | Agent | 一句话 |
|---|-------|--------|
| 🔒 | **Security Engineer** | 合规通过不等于安全——攻击者不在乎你的证书 |

### 项目管理

| | Agent | 一句话 |
|---|-------|--------|
| 📐 | **Project Manager** | 敏捷已经变成了它本该取代的东西 |

### 销售

| | Agent | 一句话 |
|---|-------|--------|
| 🎯 | **Sales Engineer** | PoC 是销售工程中最被滥用的工具 |
| 💰 | **Deal Strategist** | 折扣是最缺乏创意的成交方式 |

### 支持

| | Agent | 一句话 |
|---|-------|--------|
| 💬 | **Customer Support** | 工单不是打扰，是免费的用户研究 |

### 财务

| | Agent | 一句话 |
|---|-------|--------|
| 💹 | **Financial Analyst** | 单位经济学比增长率重要——增长快不等于健康 |

### 游戏开发

| | Agent | 一句话 |
|---|-------|--------|
| 🎮 | **Game Designer** | 大多数游戏设计文档是虚构的——它们描述的是理想体验而非可构建系统 |
| 🗺️ | **Level Designer** | 好的关卡通过环境暗示来教学，而不是对话框——Portal不需要教程 |
| 📜 | **Narrative Designer** | 环境叙事不是"在地上放笔记"——每次选择都存入或提取信任 |
| 💻 | **Game Programmer** | 面向对象编程是发生在游戏开发中最糟糕的事情——ECS不是趋势，是修正 |
| 🖥️ | **Game UI Designer** | 游戏UI和应用UI是不同的学科——能移除的界面元素就不该存在 |
| 🎨 | **Technical Artist** | 照片写实主义是无话可说的游戏的拐杖——独特视觉身份比写实更持久 |
| 🎵 | **Game Audio Engineer** | 大多数游戏配乐过度——沉默是游戏音频中最被低估的工具 |
| 🧪 | **Game QA Engineer** | 游戏QA不是软件QA——有趣不是规格，自动化测试只能发现30% |
| 🎬 | **Game Producer** | Crunch不是激情的标志——而是生产失败的标志 |
| 💰 | **Monetization Designer** | 最赚钱的变现不是最激进的——而是最对齐的 |
| 🎯 | **Unity Developer** | Asset Store既是最大的优势也是最大的陷阱——最好的项目几乎不使用它 |
| 🔵 | **Unreal Developer** | Blueprint不是给设计师的编程工具——它就是编程，有编程的所有复杂性 |

---

## 协作引擎

这是 AgentGraph 区别于所有其他 Agent 项目的核心。

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

12 个 CLI 命令，仅需 Bash 3.2+ + Python3 内置模块。完整用法见 [使用指南](docs/使用指南.md)。

---

## 图引擎

除了流水线式的交接，AgentGraph 还提供了基于有向图的执行引擎，支持循环、并行和条件分支。

### 概念

- **Node（节点）**：一个 Agent 执行一个动作。每个节点有 agent、action、timeout、needs、delivers 等属性。
- **Edge（边）**：节点之间的依赖关系和流转条件。支持 `completed`/`failed` 条件触发。
- **State（状态）**：整个图的共享进度，以 JSON 格式持久化到 `/tmp/guild-graph-<name>-state.json`，支持断点恢复。

### 示例

```yaml
# graphs/game-mvp.yml
name: game-mvp
description: 游戏 MVP 开发流程
nodes:
  design:
    agent: game-designer
    action: execute
  prototype:
    agent: game-programmer
    action: execute
    needs: [design]
  art:
    agent: technical-artist
    action: execute
  integrate:
    agent: game-producer
    action: execute
    needs: [prototype, art]
edges:
  - {from: design, to: prototype}
  - {from: prototype, to: integrate, when: completed}
  - {from: art, to: integrate, when: completed}
```

### 运行

```bash
$ ./guild graph run --graph graphs/game-mvp.yml --path ./my-game/
```

输出示例：

```
=============================
  Graph Engine: game-mvp
=============================
  -- iteration 1: ready nodes --
  > start: design
  > start: art
  ...
=============================
  图执行报告
=============================
  节点统计: 总计=4 完成=4 ...
[OK] 图执行全部完成
```

### 特性

- **循环**：通过边条件触发回路，支持重试（最多 3 次）
- **并行**：同一层级的无依赖节点自动并行执行
- **条件边**：支持 `when: completed` / `when: failed` 等条件
- **断点恢复**：`./guild graph resume <name>` 从上次中断处继续
- **Dry-Run 模拟**：`--dry-run` 参数预览完整执行计划
- **Handoff 集成**：每个节点完成后自动创建交接记录，在 `guild status` 中可见

---

## 跟 agency-agents 比

| | agency-agents | **AgentGraph** |
|---|---|---|
| Agent 深度 | 一个模板换词 300 次 | 每个有挑衅性观点、冲突偏好、盲区 |
| Agent 质量 | 参差不齐 | 20A + 5A- + 3B+，lint 强制校验 |
| 协作 | 零 — 人手动复制粘贴 | **handoff → run → decide → context 四层引擎** |
| 冲突检测 | 无 | 自动检测 + 影响范围分析 + 追溯 |
| 流水线 | Markdown 文档 | `guild run` 一键执行 |
| 决策追溯 | 无 | ADR 模式，每次交接可追溯 |
| 图执行 | 无 | **guild graph run，支持循环/并行/条件边** |
| 分发 | 16 工具 | 4 核心工具（按需扩展） |
| 中文 | 翻译 | **原生中文全链路** |
| 依赖 | Bash+Python3 | **Bash 3.2+ + Python3 内置模块** |

**AgentGraph 不是 agency-agents 的 fork。** 它是同一个问题（"AI 怎么组队干活"）的下一代答案。agency-agents 证明了"Agent 定义可以模板化"，AgentGraph 证明了**协作可以自动化**。

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
AgentGraph/
├── agents/          40 个 Agent（工程/产品/设计/测试/市场/安全/项目管理/销售/支持/财务/游戏开发）
│   ├── engineering/            # 工程部（7个）
│   ├── product/                # 产品部（4个）
│   ├── design/                 # 设计部（4个）
│   ├── testing/                # 测试部（3个）
│   ├── marketing/              # 市场部（4个）
│   ├── security/               # 安全部（1个）
│   ├── project-management/     # 项目管理部（1个）
│   ├── sales/                  # 销售部（2个）
│   ├── support/                # 支持部（1个）
│   ├── finance/                # 财务部（1个）
│   └── game-development/       # 游戏开发部（10个）
├── scripts/         8 个脚本（lint/convert/install/nexus/graph-engine/lib/test-runner/agent-prompt）
├── contracts/       协作契约 — 从 Agent 第 13 段自动提取
├── pipelines/       流水线定义（YAML）
├── graphs/          图定义（YAML）— 循环、并行、条件分支
├── context/         决策记录 — ADR 模式
├── handoffs/        交接记录（图引擎自动集成）
├── integrations/    工具集成输出（claude-code/cursor/copilot/windsurf）
├── demos/           交接演练场景
├── docs/            5 份中文使用指南 + 模板规范
├── website/         项目官网（单页 HTML）
├── guild            → scripts/nexus.sh（主命令）
└── guild.config.json  40 Agent + 4 工具的中央注册表
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
