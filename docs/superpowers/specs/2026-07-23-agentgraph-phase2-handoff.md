# AgentGraph Phase 2a — Handoff Engine 设计文档

**版本**: v1.0  
**日期**: 2026-07-23  
**状态**: 设计已确认，待进入实施规划  
**依赖**: Phase 1（Guild Core）已完成

---

## 一、项目概述

### 1.1 一句话定位

Handoff Engine 是 AgentGraph 的协作基础设施——把 Agent 之间"我产出什么、你需要什么"的约定从 Markdown 文字变成自动检查逻辑。

### 1.2 解决什么问题

Phase 1 的 Agent 有协作契约（第 13 段），但它是给人读的文档。实际操作中：
- PM 写完 PRD 给后端，不知道后端需要什么——漏了性能指标、漏了 API 草案
- 后端收到不全的输入就开工——做出来的东西跟 PM 想的不一样
- 交接过程没有记录——出问题了不知道是谁的输入有问题

Handoff Engine 解决的就是"Agent A 和 Agent B 之间传接球"的质量问题。

### 1.3 MVP 范围

**做**：CLI 工具 `guild handoff/check/status/accept`，从 Agent 的协作契约中自动提取结构化依赖，校验交接完整性。

**不做**：自动化触发（Phase 2b）、Web 面板（Phase 2c）、跨会话状态持久化。

---

## 二、架构设计

### 2.1 整体架构

```
Agent 源文件（第13段：协作契约）
        │
        ▼
  contracts/extract.sh  ──→  contracts/guild-contracts.yml
        │                         │
        │                         ▼
        │              nexus.sh  handoff 命令
        │                         │
        │              ┌──────────┼──────────┐
        │              ▼          ▼          ▼
        │           check      status     accept
        │              │
        │              ▼
        └──────  handoffs/*.json（交接记录）
```

### 2.2 数据模型

**协作契约 YAML** (`contracts/guild-contracts.yml`)：

```yaml
product-manager:
  delivers:
    - name: problem_statement
      description: 问题陈述（含目标用户、成功指标）
      format: markdown
    - name: user_stories
      description: 用户故事（含验收条件）
      format: markdown
    - name: scope_decisions
      description: 明确的"做什么"和"不做什么"
      format: text
  requires:
    - from: ux-researcher
      items:
        - name: user_insights
          description: 用户研究洞察
        - name: personas
          description: 用户画像
    - from: data-analyst
      items:
        - name: baseline_metrics
          description: 当前基线指标

backend-architect:
  delivers:
    - name: api_spec
      description: API 规范（OpenAPI 3.0）
      format: yaml
    - name: db_schema
      description: 数据库 schema（含迁移脚本）
      format: sql
    - name: auth_flow
      description: 认证授权流程图
      format: markdown
  requires:
    - from: product-manager
      items:
        - name: problem_statement
          description: 问题陈述
          required: true
        - name: performance_targets
          description: 性能目标（QPS、延迟 SLO、并发数）
          required: true
        - name: data_model_draft
          description: 数据模型草案
          required: false
    - from: frontend-engineer
      items:
        - name: api_requirements
          description: 前端对 API 的具体需求
          required: false
```

**交接记录 JSON** (`handoffs/YYYY-MM-DD-<from>-to-<to>.json`)：

```json
{
  "id": 1,
  "from": "product-manager",
  "to": "backend-architect",
  "timestamp": "2026-07-23T15:30:00Z",
  "artifacts": [
    {"name": "problem_statement", "file": "prd/problem-statement.md", "status": "provided"},
    {"name": "performance_targets", "file": null, "status": "missing"},
    {"name": "data_model_draft", "file": null, "status": "missing"}
  ],
  "checklist": {
    "required_total": 3,
    "required_provided": 1,
    "required_missing": 2
  },
  "status": "incomplete",
  "accepted_by": null
}
```

### 2.3 命令接口

```
guild handoff  --from <agent> --to <agent> --path <dir> [--message <msg>]
guild check    --handoff <id>
guild status   [--agent <name>] [--status incomplete|ready|accepted]
guild accept   --handoff <id> --as <agent>
```

### 2.4 工作流程

```
PM 产出 PRD
  │
  ├─→ guild handoff --from pm --to backend --path ./prd/
  │     │
  │     ├─ 扫描 --path 下的文件
  │     ├─ 对照 backend-architect 的 requires 清单
  │     ├─ 自动匹配文件名 → 需求项
  │     ├─ 标记缺失项
  │     └─ 写入 handoffs/*.json
  │
  ├─→ guild check --handoff 1
  │     │
  │     ├─ required_total: 3
  │     ├─ required_provided: 1
  │     ├─ required_missing: 2
  │     └─ 输出："缺少：性能目标、数据模型草案"
  │
  ├─ PM 补全缺失内容
  │
  ├─→ guild handoff --from pm --to backend --path ./prd-v2/
  │     └─ 完整性检查通过
  │
  └─→ guild accept --handoff 1 --as backend-architect
        └─ 标记为已接收，状态变为 "accepted"
```

---

## 三、技术方案

### 3.1 技术选型

| 组件 | 选择 | 理由 |
|------|------|------|
| 契约提取 | Bash + awk/yq 语法 | 跟 Phase 1 一致，零新依赖 |
| 交接 CLI | Bash 脚本 (`scripts/nexus.sh`) | 零依赖，纯函数式 |
| 契约存储 | YAML | 人可读，Agent 文件保持一致 |
| 交接记录 | JSON 文件 (`handoffs/`) | 文件即数据库，git 可追踪 |
| 文件匹配 | 文件名正则 + 内容关键词 | 简单直接，无需 AI |

### 3.2 文件结构

```
AgentGraph/
├── contracts/
│   ├── extract.sh               ← 从 Agent 提取契约 → YAML
│   └── guild-contracts.yml      ← 结构化契约（可手动编辑）
├── handoffs/                    ← 交接记录（.gitkeep 提交）
│   └── .gitkeep
├── scripts/
│   ├── lib.sh                   ← 已有（扩展：contract 相关函数）
│   └── nexus.sh                 ← CLI 入口
└── docs/
    └── 协作指南.md               ← 使用文档
```

### 3.3 关键算法

**交接完整性检查**：
1. 读取 `guild-contracts.yml` 中接收方（to）的 `requires` 列表
2. 扫描 `--path` 目录下的文件
3. 文件名匹配：`problem_statement` → 匹配 `*problem*statement*.md`
4. 内容关键词：如果文件名匹配不到，搜索文件内容中的关键词
5. 输出：provided / missing 清单

### 3.4 与 Phase 1 的关系

- Agent 文件 **不需要修改**——协作契约（第 13 段）已在 Phase 1 写入
- guild.config.json **可能需要扩展**——增加 contract schema 定义
- 脚本目录 **并存**——nexus.sh 和现有脚本不冲突

---

## 四、交付物清单

| 编号 | 交付物 | 说明 |
|------|--------|------|
| D1 | `contracts/extract.sh` | 从 12 个 Agent 提取协作契约 → YAML |
| D2 | `contracts/guild-contracts.yml` | 12 个 Agent 的结构化契约（extract.sh 生成） |
| D3 | `scripts/nexus.sh` | CLI 工具：handoff / check / status / accept |
| D4 | `handoffs/.gitkeep` | 交接记录目录 |
| D5 | `docs/协作指南.md` | 中文使用文档 |
| D6 | 3 个演示场景文档 | PM→后端 / PM→UX / 前端→QA 的端到端示例 |

---

## 五、成功标准

| 指标 | 目标 |
|------|------|
| 契约覆盖率 | 12/12 Agent 的契约被成功提取 |
| 交接检查准确率 | 手动制造 5 个"缺失场景"，全部被 check 检出 |
| 零依赖 | 不引入任何新外部依赖 |
| bash -n 通过 | nexus.sh 和 extract.sh 语法检查通过 |
| 使用文档 | 一个非技术人员照着文档操作能完成一次 handoff |

---

## 六、自检清单

- [x] 范围明确：只做 Handoff Engine，不做编排器和面板
- [x] 架构清晰：契约提取 + CLI 工具 + 交接记录
- [x] 与 Phase 1 无冲突：不修改 Agent 文件，不修改现有脚本
- [x] 技术栈一致：Bash + YAML + JSON，零新依赖
- [x] 没有 TBD/TODO/模糊占位符
- [x] 交付物可验证：每个 D1-D6 都有明确产出
- [x] 成功标准有数字：覆盖率 100%、检出率 100%

---

**下一步**：进入实施规划（writing-plans），将 Handoff Engine 拆解为可执行的开发任务。
