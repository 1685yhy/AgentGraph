# 🎭 AgentGraph — AI 团队协作操作系统

<p align="center">
  <img src="https://img.shields.io/github/stars/1685yhy/AgentGraph?style=for-the-badge&color=3B82F6" alt="GitHub Stars">
  <img src="https://img.shields.io/github/license/1685yhy/AgentGraph?style=for-the-badge&color=EC4899" alt="MIT License">
  <img src="https://img.shields.io/badge/PRs-welcome-brightgreen?style=for-the-badge&color=22C55E" alt="PRs Welcome">
  <img src="https://img.shields.io/badge/agents-40-3B82F6?style=for-the-badge" alt="40 Agents">
  <img src="https://img.shields.io/badge/Bash_Python3-Bash_3.2++Python3-D946EF?style=for-the-badge" alt="Bash+Python3">
</p>

<p align="center">
  <a href="#agentgraph-是什么">是什么</a> ·
  <a href="#快速开始-5分钟上手">快速开始</a> ·
  <a href="#核心概念">核心概念</a> ·
  <a href="#完整命令参考">命令参考</a> ·
  <a href="#典型工作流">工作流</a> ·
  <a href="#门禁系统">门禁系统</a> ·
  <a href="#故障排查">故障排查</a> ·
  <a href="README.md">English</a>
</p>

---

## AgentGraph 是什么

**AgentGraph 是一个让 40 个 AI Agent 像真人团队一样协作的系统。**

它不是"把一堆 AI 放一起然后祈祷"的工具。它的核心是两个东西：

1. **40 个有真实人格的 AI Agent** — 每个都有自己的立场、铁律、盲区和专业领域。不是模板换名字。
2. **Graph 协作引擎** — Agent 之间通过标准化的"交接"传递工作，系统自动检查完整性、检测决策冲突、按流程编排、生成变更日志。

> 一句话：你写 PRD，AgentGraph 帮你完成从需求到上线的全流程，每个步骤自动检查质量。

除了 40 个 Agent 与 Graph 引擎，AgentGraph 已长出一条完整的自建能力链：**分类器 → 模板 → MCP 适配 → 自建运行时**。自然语言任务先由 18 种产品类型分类器识别方向，再从 18 个项目模板初始化工程骨架；MCP 服务器把 23 个工具暴露给任意 AI 宿主（Claude Code / Cursor 等）；最后自建运行时接入真实 LLM 后端（Anthropic / OpenAI / DeepSeek），驱动 Agent 走完「分类 → 计划 → 执行 → 审查 → 修复」的完整交付链——从需求到可玩原型、可交付页面，全程真实 API 调用、自动审查、修复闭环。

---

## 快速开始（5 分钟上手）

### 1. 安装

```bash
# 克隆项目
git clone https://github.com/1685yhy/AgentGraph.git
cd AgentGraph

# 转换 Agent 配置到各 AI 工具格式
bash scripts/convert.sh

# 安装到 Claude Code（你的 AI 编辑器）
bash scripts/install.sh --tool claude-code

# 或者安装到所有已检测到的工具
bash scripts/install.sh
```

安装后，你的 Claude Code 里就有了 40 个可用的 Agent 角色。

### 2. 你的第一个交接

交接（Handoff）是 AgentGraph 最核心的操作 — 一个 Agent 把工作交付给下一个。

```bash
# 创建一个目录，放你的 PRD 文档
mkdir -p /tmp/my-project
echo "# 我的项目 PRD 文档" > /tmp/my-project/prd.md

# PM 把工作交接给前端工程师
./guild handoff --from product-manager --to frontend-engineer --path /tmp/my-project
```

输出示例：

```
创建交接 #1: product-manager → frontend-engineer
  状态: incomplete
  完整度: 1/3 项已提供
  [!!] 缺失 2 项:
       - 设计规范或原型链接
       - 验收条件
```

系统会告诉你缺了什么。补充完整后重新运行。

### 3. 验证交付物质量

```bash
# 验证交接 #1 对应的目录文件质量
./guild verify --handoff 1
```

### 4. 运行质量门禁

```bash
# 对交接 #1 运行全部 5 项质量门禁
./guild gate --handoff 1
```

通过门禁后，接收方才能运行 `accept` 正式接手工作。

### 5. 查看所有交接状态

```bash
./guild status
```

---

## 核心概念

### Agent（智能体）

AgentGraph 内置 40 个 AI Agent，分布在 11 个部门：

| 部门 | Agent 数 | 包含 |
|------|---------|------|
| 工程 | 7 | 前端工程师、后端架构师、DevOps、AI工程师、移动端开发、DBA、代码审查 |
| 产品 | 4 | 产品经理、UX研究员、数据分析师、技术写作 |
| 设计 | 4 | UI设计师、品牌守护者、交互设计师、创意总监 |
| 测试 | 3 | QA工程师、性能测试、无障碍审计 |
| 市场 | 4 | 增长黑客、内容创作、社媒策略、SEO |
| 安全 | 1 | 安全工程师 |
| 项目管理 | 1 | 项目经理 |
| 销售 | 2 | 销售工程师、交易策略师 |
| 支持 | 1 | 客户支持 |
| 财务 | 1 | 财务分析师 |
| 游戏开发 | 10 | 游戏设计师、关卡设计、叙事设计、游戏程序、Unity、Unreal、技术美术、游戏UI、游戏音频、变现设计、游戏QA、游戏制作人 |

每个 Agent 有 13 段定义，包括：挑衅性观点、铁律、冲突偏好、盲区声明、决策权重、协作契约。

### Handoff（交接）

一个 Agent 把交付物传给另一个 Agent 的过程。交接时系统自动：

- 检查接收方需要的交付物是否齐全
- 验证文件质量（语法、编码、结构）
- 检测相关决策和潜在冲突
- 通知接收方去检查收件箱

### Graph（图引擎）

基于有向图的执行引擎，支持：

- **顺序执行** — A 做完 B 才能做
- **并行执行** — 无依赖的任务同时进行
- **条件分支** — 测试通过 vs 不通过走不同路径
- **循环回路** — 不通过可以打回修复再测
- **断点恢复** — 执行中断后可以 resume

### Gate（质量门禁）

5 道关卡，全部通过才能正式接收交接近：

1. completeness — 必需件齐全
2. syntax — 语法正确
3. behavior — 行为测试通过
4. playability — 可玩性/可用性检查
5. agent-standards — 对应 Agent 的成功标准

### Feedback（反馈闭环）

在交接中发现 bug 或改进点时，记录反馈并关联到交接。修复后标记已修复。

---

## 完整命令参考

所有命令通过 `./guild`（或 `bash scripts/nexus.sh`）执行。

| 命令 | 说明 | 示例 |
|------|------|------|
| `guild classify` | 自然语言 → 产品类型 + 置信度（18种类型） | `guild classify --json '做一个供应商后台管理系统'` |
| `guild plan` | 生成完整执行计划（类型+团队+流程+里程碑+风险） | `guild plan --json '帮我做塔罗小程序'` |
| `guild templates` | 列出 18 个可用项目模板（文档型 + 工程型） | `guild templates` |
| `guild init` | 从模板初始化项目（自动配置 Agent 团队） | `guild init --template admin-system ./my-project` |
| `guild handoff` | 创建交接（Agent A → Agent B） | `guild handoff --from pm --to backend --path ./prd/` |
| `guild check` | 检查交接完整性 | `guild check --handoff 1` |
| `guild status` | 查看所有交接状态 | `guild status` |
| `guild status --agent <name>` | 查看某个 Agent 相关的交接 | `guild status --agent frontend-engineer` |
| `guild status --status <status>` | 按状态筛选 | `guild status --status incomplete` |
| `guild accept` | 接收交接（自动运行门禁） | `guild accept --handoff 1 --as frontend-engineer` |
| `guild verify` | 验证交付物质量 | `guild verify --handoff 1` |
| `guild verify --type html --file ./index.html` | 按类型验证单个文件 | `guild verify --type html --file ./index.html` |
| `guild verify --path ./my-dir` | 验证整个目录 | `guild verify --path ./my-project/` |
| `guild test` | 运行行为测试（超越静态分析） | `guild test --handoff 1` |
| `guild test --file ./game.html` | 对单个文件跑行为测试 | `guild test --file ./game.html` |
| `guild test --generate --from-agent game-designer --file ./game.html` | 自动生成测试 | `guild test --generate --from-agent game-designer --file ./game.html` |
| `guild feedback` | 记录 bug 或改进反馈 | `guild feedback --handoff 1 --type bug --summary "按钮点击无响应"` |
| `guild feedback --list` | 列出所有反馈 | `guild feedback --list` |
| `guild feedback --fix fb-001 --handoff 2` | 标记反馈已修复 | `guild feedback --fix fb-001 --handoff 2` |
| `guild changelog` | 生成变更日志 | `guild changelog` |
| `guild changelog --since v0.1.0` | 从指定版本起生成日志 | `guild changelog --since v0.1.0` |
| `guild list` | 列出交接记录 | `guild list` |
| `guild list --contracts` | 列出 Agent 间的协作契约 | `guild list --contracts` |
| `guild decide` | 记录决策（ADR 模式） | `guild decide --agent backend --type api-design --topic "API格式" --summary "统一包裹"` |
| `guild context show` | 查看决策图谱 | `guild context show` |
| `guild context check` | 检查决策冲突 | `guild context check` |
| `guild run` | 运行时执行图（真实 LLM 驱动完整交付链） | `guild run --graph feature-dev --task "做一个供应商后台管理系统"` |
| `guild run --graph <name> --task "<描述>" --yes` | 全自动模式（跳过确认直接执行） | `guild run --graph game-mvp --task "做一个贪吃蛇小游戏" --yes` |
| `guild run-agent` | 单个 Agent 运行时执行（真实 LLM 调用） | `guild run-agent game-designer "设计一个核心循环" --upstream 1` |
| `guild watch` | 监听项目目录变化，自动触发执行 | `guild watch --timeout 120` |
| `guild graph run` | 执行图 | `guild graph run --graph game-mvp --path ./my-game/` |
| `guild graph status` | 查看图执行状态 | `guild graph status` |
| `guild graph show <name>` | 显示图结构 | `guild graph show game-mvp` |
| `guild graph list` | 列出可用图定义 | `guild graph list` |
| `guild graph resume` | 恢复断点处继续执行图 | `guild graph resume --graph game-mvp --path ./my-game/` |
| `guild inbox` | 查看所有 Agent 收件箱概况 | `guild inbox` |
| `guild inbox --agent <name>` | 查看某个 Agent 的收件箱 | `guild inbox --agent frontend-engineer` |
| `guild inbox --agent <name> --unread` | 只看未读消息 | `guild inbox --agent backend-architect --unread` |
| `guild read --agent <name>` | 标记收件箱全部已读 | `guild read --agent frontend-engineer` |
| `guild resolve --topic <topic>` | 基于决策权重解决冲突 | `guild resolve --topic "API响应格式"` |
| `guild gate` | 运行质量门禁 | `guild gate --handoff 1` |
| `guild gate --handoff 1 --gate 1` | 只运行指定的某一关 | `guild gate --handoff 1 --gate completeness` |
| `guild gate --list` | 列出所有质量门禁 | `guild gate --list` |

> **缩写支持**：Agent 名字支持缩写、部分匹配、大小写不敏感。比如 `pm` 自动匹配 `product-manager`，`backend` 匹配 `backend-architect`。

---

## 典型工作流

### 场景 A：从 PRD 到上线（用 Graph 驱动）

适合完整功能开发流程，从需求定义到发布。

```bash
# 1. 准备好项目目录
mkdir -p /tmp/feature-x
# 在里面放你的 PRD 文档、设计稿等

# 2. 用 graph 引擎驱动全流程
./guild graph run --graph feature-dev --path /tmp/feature-x

# 3. 图引擎会自动执行：
#    define (PM) → design (UI设计师)
#                → build-frontend + build-backend (并行)
#                                              → test (QA)
#                                                ├─ 通过 → approve (创意总监)
#                                                └─ 不通过 → fix → 重新测试
```

内置的 `feature-dev` 图定义（`graphs/feature-dev.yml`）包含：

| 节点 | Agent | 做什么 |
|------|-------|--------|
| define | product-manager | 产出 PRD 和用户故事 |
| design | ui-designer | 产出设计规范 |
| build-frontend | frontend-engineer | 产出前端代码 |
| build-backend | backend-architect | 产出后端代码 |
| test | qa-engineer | 验证，通过继续，不通过打回 |
| fix | frontend-engineer | 修复 bug |
| approve | creative-director | 最终批准 |

### 场景 B：Bug 修复迭代（用 Feedback 闭环）

适合持续迭代、收集反馈、修复验证的循环。

```bash
# 1. PM 发起 handoff，前端接收
./guild handoff --from pm --to frontend --path /tmp/feature-x
./guild accept --handoff 1 --as frontend-engineer

# 2. QA 测试后记录 bug 反馈
./guild feedback --handoff 1 --type bug \
  --severity high \
  --summary "提交按钮在移动端点击无响应" \
  --repro "在 iOS Safari 上点击提交按钮，无任何反应"

# 3. 修复后创建新的交接
./guild handoff --from frontend --to qa --path /tmp/feature-x

# 4. 将反馈标记为已修复
./guild feedback --fix fb-001 --handoff 2

# 5. 查看变更日志
./guild changelog
```

也可以用内置的 `iterate` 图自动完成迭代循环：

```bash
./guild graph run --graph iterate --path /tmp/my-project
```

`graphs/iterate.yml` 流程：collect（客服收集反馈）→ prioritize（PM排序）→ fix（修复）→ verify（QA验证）→ 通过则 deploy（上线），不通过则 retry（打回重试）。

### 场景 C：游戏 MVP 开发（用 Game-MVP Graph）

适合从概念到可玩原型的游戏开发。

```bash
# 1. 准备好项目目录
mkdir -p /tmp/my-game

# 2. 运行游戏 MVP 图
./guild graph run --graph game-mvp --path /tmp/my-game

# 图引擎会执行以下节点：
# concept (游戏设计师) → art (技术美术, 并行)
#                      → code (游戏程序, 并行)
#                      → ui (游戏UI设计师, 并行)
#                      → audio (游戏音频, 并行)
#                      → integration (游戏程序, 合并)
#                      → qa (游戏QA)
#                        ├─ 通过 → ship (游戏制作人)
#                        └─ 不通过 → fix → 重新 QA
```

也可以让运行时（真实 LLM）自动驱动整个图：

```bash
./guild run --graph game-mvp --task "做一个贪吃蛇小游戏" --yes
```

运行时接入真实 LLM 后端，按图自动执行：concept（游戏设计师）→ art/code/ui/audio（技术美术/游戏程序/游戏UI/音频，并行）→ integration（游戏程序合并）→ qa（游戏QA 验证）→ 不通过则 fix 修复重测，通过则 ship 发布。每个节点真实调用 LLM 产出交付物并自动审查。

---

## 门禁系统

质量门禁（Quality Gates）是 AgentGraph 的核心质量保障。每次 `guild accept` 会自动运行全部 5 关。

### 5 关详解

| # | 门禁名称 | 检查内容 | 失败示例 |
|---|---------|---------|---------|
| 1 | **completeness**（完整性） | 接收方需要的所有交付物是否都提供了 | 后端架构师需要 API 合同，但目录里没有 |
| 2 | **syntax**（语法） | 文件语法是否正确（HTML/JS/JSON/YAML/Shell按类型检查） | HTML 缺少 `</script>` 闭合标签 |
| 3 | **behavior**（行为） | 事件绑定、守卫、错误处理等行为模式是否存在 | HTML 没有绑定任何事件处理 |
| 4 | **playability**（可玩性） | 教程引导、音效初始化、核心功能可达性、移动端适配 | 缺少 viewport meta 标签 |
| 5 | **agent-standards**（Agent标准） | 按接收方 Agent 定义的 success metrics 逐条验证 | 游戏QA要求所有文字有中文翻译，但HTML全是英文 |

### 手动运行

```bash
# 全部 5 关
./guild gate --handoff 1

# 只看某一关
./guild gate --handoff 1 --gate completeness
./guild gate --handoff 1 --gate syntax

# 罗列门禁清单
./guild gate --list
```

### 门禁与接收的关系

```
handoff（创建交接）
  ↓
verify（可选：手动验证质量）
  ↓
gate（必须通过全部 5 关）
  ↓
accept（接收方正式接手工作）
```

如果门禁不通过，`accept` 会拒绝执行。

---

## 故障排查

### 常见问题

**Q: `./guild` 提示 command not found**

不是可执行文件，是一个符号链接指向 `scripts/nexus.sh`。运行方式：

```bash
bash scripts/nexus.sh handoff --from pm --to backend --path ./
# 或
./guild handoff --from pm --to backend --path ./
```

确保 `./guild` 有执行权限。

**Q: handoff 创建失败：Unknown agent**

Agent 名字支持缩写，但不支持任意名称。试试标准英文 slug：

```bash
# 查看所有可用 Agent
cat guild.config.json | grep -A1 '"slug"'

# 支持缩写：pm → product-manager, backend → backend-architect
# 支持部分匹配：front → frontend-engineer
```

**Q: "缺失 xx 项" — 到底缺了什么？**

```bash
# 查看详细内容
./guild check --handoff 1
```

输出的 artifacts 列表里 `status: missing` 的就是缺的。

**Q: 怎么看当前所有的交接记录？**

```bash
./guild status
# 或者看更详细的
./guild list
```

**Q: gate 怎么都过不了？**

不要手动绕过门禁。先看具体哪一关没通过：

```bash
./guild gate --handoff 1 --gate completeness  # 缺文件？
./guild gate --handoff 1 --gate syntax        # 语法错？
```

修复后创建新的 handoff，再次运行 gate。

**Q: 运行 graph 时中断了，怎么继续？**

```bash
# 从上次中断处继续
./guild graph resume --graph game-mvp --path /tmp/my-game/
# 或者查看当前进度
./guild graph status --graph game-mvp
```

**Q: 怎么知道哪个 Agent 在哪个领域有最终话语权？**

```bash
# 查看决策图谱
./guild context show

# 解决冲突时会自动分析决策权重
./guild resolve --topic "API格式"
```

---

## 项目结构

```
AgentGraph/
├── agents/                    40 个 Agent 定义文件（Markdown）
│   ├── engineering/           工程部（7个）
│   ├── product/               产品部（4个）
│   ├── design/                设计部（4个）
│   ├── testing/               测试部（3个）
│   ├── marketing/             市场部（4个）
│   ├── security/              安全部（1个）
│   ├── project-management/    项目部（1个）
│   ├── sales/                 销售部（2个）
│   ├── support/               支持部（1个）
│   ├── finance/               财务部（1个）
│   └── game-development/      游戏开发部（10个）
├── scripts/                   核心脚本
│   ├── nexus.sh               主 CLI 入口
│   ├── runtime/               自建运行时引擎（v0.6a）
│   │   ├── run.sh             运行时编排（guild run）
│   │   ├── agent-runner.sh    单 Agent 执行器（真实 LLM）
│   │   ├── llm-backend.js     LLM 后端适配（Anthropic/OpenAI/DeepSeek）
│   │   └── event-bus.sh       事件总线（guild watch）
│   ├── mcp-server.js          MCP 服务器（23 个工具）
│   ├── graph-generator.sh     分类器 + 计划生成（18 种产品类型）
│   ├── graph-engine.sh        图执行引擎
│   ├── modules/               模块化命令实现
│   ├── test-runner.sh         行为测试引擎
│   ├── runtime-test.sh        浏览器运行时测试
│   ├── self-test.sh           系统自测
│   ├── ci-test.sh             CI 自测
│   ├── lib.sh                 共享函数库
│   ├── lint.sh                Agent 质量检查
│   ├── convert.sh             格式转换（agent.md → 工具格式）
│   ├── install.sh             安装到 AI 工具
│   └── agent-prompt.sh        Agent 提示工具
├── contracts/                 协作契约定义
│   └── guild-contracts.yml    所有 Agent 的产出/需求矩阵
├── pipelines/                 流水线定义（YAML）
│   ├── feature-dev.yml        功能开发流水线
│   ├── game-mvp.yml           游戏 MVP 流水线
│   ├── iterate.yml            产品迭代流水线
│   └── startup-mvp.yml        创业 MVP 流水线
├── graphs/                    图定义（YAML，共 5 个）
│   ├── feature-dev.yml        功能开发图
│   ├── game-mvp.yml           游戏 MVP 图
│   ├── iterate.yml            产品迭代图
│   ├── research-report.yml    研究报告图
│   └── unity-game.yml         Unity 游戏图
├── context/                   决策系统
│   ├── decisions/             决策记录（ADR 格式 JSON）
│   ├── inbox/                 Agent 收件箱
│   ├── feedback/              反馈记录
│   └── index.json             决策图谱索引
├── handoffs/                  交接记录（自动生成 JSON）
├── integrations/              工具格式输出（自动生成）
│   ├── claude-code/
│   ├── cursor/
│   ├── copilot/
│   └── windsurf/
├── demos/                     交接演练场景（Markdown）
├── docs/                      文档
│   ├── 使用指南.md             完整 CLI 使用手册
│   ├── 协作指南.md             Agent 协作详细说明
│   ├── 流水线指南.md           流水线使用说明
│   ├── 决策系统指南.md          决策/冲突系统说明
│   ├── 迭代指南.md             迭代工作流说明
│   └── AGENT_TEMPLATE.md      Agent 模板规范
├── website/                   项目官网
├── guild → scripts/nexus.sh   CLI 入口
└── guild.config.json          40 Agent + 4 工具注册表
```

---

## 支持的工具

| 工具 | 安装命令 |
|------|---------|
| **Claude Code** | `bash scripts/install.sh --tool claude-code` |
| **Cursor** | `bash scripts/install.sh --tool cursor` |
| **GitHub Copilot** | `bash scripts/install.sh --tool copilot` |
| **Windsurf** | `bash scripts/install.sh --tool windsurf` |

安装前先运行 `bash scripts/convert.sh` 生成工具格式文件。

---

## 版本历程

- **v0.3 — 分类器**：自然语言分类器上线，可识别 18 种产品类型
- **v0.4 — 模板**：18 个项目模板脚手架（文档型 + 工程型），一条命令初始化工程
- **v0.5 — MCP**：MCP 适配层上线，23 个 AgentGraph 工具暴露给任意 AI 宿主
- **v0.6a — 运行时引擎**：自建运行时（llm-backend / agent-runner / event-bus / run），接入真实 LLM

---

## 许可

MIT — 随便用，改，分发。

<p align="center">
  <sub>Built with conviction, not consensus. 源自信念，而非共识。</sub>
</p>
