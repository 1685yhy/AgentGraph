# AgentGraph v0.5 — 多框架 MCP 适配层

**日期**: 2026-08-01
**版本**: v0.5.0
**状态**: 设计完成，待实现

---

## 1. 目标

将 AgentGraph 的完整能力封装为 MCP (Model Context Protocol) Tools，让任意支持 MCP 的 AI 框架（LangChain/CrewAI/AutoGPT/MetaGPT 等）都能调用 40 Agent + Graph 引擎 + 质量门禁。

**两种使用模式：**
- **完整公司模式**：外部框架扔需求 → AgentGraph 内部跑完全流程 → 返回交付物
- **Agent 超市模式**：外部框架按需调用单个 Agent 或查询能力

---

## 2. MCP Tool 清单（15 个）

### 发现类
| Tool | 说明 | 输入 | 输出 |
|------|------|------|------|
| `list_agents` | 列出全部 Agent | — | `[{slug, name, emoji, division, delivers}]` |
| `get_agent` | 获取单个 Agent 完整 prompt | `agent: string` | `{slug, name, prompt, delivers, requires}` |
| `get_capability` | 查询产品类型能力 | `type: string (18种)` | `{label, agents[], modules[], gates, metrics}` |
| `list_templates` | 列出可用模板 | — | `[{name, label, description, agent_count}]` |
| `list_gates` | 列出 5 关质量门禁 | — | `[{id, name, description, checks}]` |

### 规划类
| Tool | 说明 | 输入 | 输出 |
|------|------|------|------|
| `classify_task` | 自然语言 → 产品类型 | `task: string` | `{type, label, confidence, alternatives[], template}` |
| `generate_plan` | 生成完整执行计划 | `task: string` | `{summary, product_type, team, flow, gates, risks}` |

### 执行类
| Tool | 说明 | 输入 | 输出 |
|------|------|------|------|
| `dispatch_agent` | 派发单个 Agent | `agent, task` | `{dispatch_id, agent, task, status, prompt}` |
| `create_handoff` | Agent A → Agent B 交接 | `from, to, path, artifacts[]` | `{handoff_id, status, checklist}` |
| `run_graph` | 执行 Graph 流程 | `graph: string, task: string, path?: string` | `{status, nodes: {completed[], failed[]}}` |
| `init_project` | 初始化项目骨架 | `template: string, directory: string` | `{status, directory, template}` |

### 检查类
| Tool | 说明 | 输入 | 输出 |
|------|------|------|------|
| `check_handoff` | 检查交接完整性 | `handoff_id: number` | `{complete, checklist: {provided, missing[]}}` |
| `list_handoffs` | 列出所有交接 | `status?: string` | `[{id, from, to, status, artifacts_count}]` |
| `run_gate` | 运行质量门禁 | `handoff_id, gate?: string` | `{passed: bool, gate, results[]}` |

### 健康类
| Tool | 说明 | 输入 | 输出 |
|------|------|------|------|
| `system_health` | 系统健康检查 | — | `{status, agent_count, handoff_count, issues[]}` |

---

## 3. 实现方案

### 3.1 文件改动

只改一个文件：`scripts/mcp-server.js`

- **保留**：MCPServer 类、MCP 协议处理、HTTP 模式、stdio 模式
- **扩展**：TOOLS 注册表（14→15+ 个，重构 JSON schema）
- **重构**：IMPL 从纯 `execSync` 文本透传 → 分级路由

### 3.2 智能路由策略

```javascript
// Level 1: 纯文本透传 — 够用，不改
const PASSTHROUGH = ['list_agents', 'list_templates', 'list_gates'];

// Level 2: JSON 解析 — CLI 有 --json 或 AG_AI_MODE 模式
const JSON_PARSE = ['classify_task', 'generate_plan', 'get_capability',
                     'get_agent', 'run_gate', 'check_handoff',
                     'dispatch_agent', 'create_handoff', 'run_graph',
                     'init_project', 'list_handoffs'];

// Level 3: 组合调用 — 多个 CLI 命令组合
const COMPOSITE = ['system_health']; // doctor + self-test --quick
```

### 3.3 不引入新依赖

- 继续使用 Node.js 内置模块（`child_process`, `fs`, `readline`, `http`）
- 所有 IMPL 底层仍通过 `execSync(guild ...)` 调用，不重写 CLI 逻辑
- JSON 解析用 `JSON.parse()`（Node 内置）

### 3.4 向后兼容

- 现有 14 个 Tool 全部保留，行为不变
- 新的 Tool schema 使用更严格的 JSON Schema 定义
- `capability.types` enum 更新为 18 种

---

## 4. 架构

```
┌─────────────────────────────────────────────┐
│  外部 AI 框架                                  │
│  (LangChain / CrewAI / AutoGPT / MetaGPT)    │
└──────────────────┬──────────────────────────┘
                   │ MCP Protocol (stdio / HTTP)
                   ▼
┌─────────────────────────────────────────────┐
│  mcp-server.js (v0.5)                        │
│                                              │
│  TOOLS (15)                                  │
│  ├─ 发现: list_agents, get_agent, ...        │
│  ├─ 规划: classify_task, generate_plan       │
│  ├─ 执行: dispatch_agent, run_graph, ...     │
│  ├─ 检查: check_handoff, run_gate, ...       │
│  └─ 健康: system_health                      │
│                                              │
│  IMPL (智能路由)                              │
│  ├─ Level 1: execSync → 文本透传             │
│  ├─ Level 2: execSync → JSON.parse           │
│  └─ Level 3: 组合 execSync → 聚合            │
└──────────────────┬──────────────────────────┘
                   │ execSync
                   ▼
┌─────────────────────────────────────────────┐
│  guild CLI (nexus.sh)                        │
│  classify / plan / dispatch / handoff / ...  │
└─────────────────────────────────────────────┘
```

---

## 5. 实现任务

| # | 任务 | 说明 |
|---|------|------|
| 1 | 更新现有 Tool schemas | capability types 9→18, plan 改用 JSON 模式 |
| 2 | 新增发现类 Tools | list_agents(重构), get_agent, get_capability, list_templates, list_gates |
| 3 | 新增规划类 Tools | classify_task(JSON解析), generate_plan(JSON解析) |
| 4 | 新增执行类 Tools | create_handoff, run_graph, dispatch_agent(重构JSON输出) |
| 5 | 新增检查+健康类 Tools | check_handoff, list_handoffs, run_gate(重构), system_health |
| 6 | 自测 + 文档 | MCP server 功能测试, 18/18 self-test 无回归 |

---

## 6. 成功标准

- [ ] 15 个 MCP Tool 全部可用
- [ ] `classify_task("做供应商后台")` → `{type:"admin-system",confidence:0.8}`
- [ ] `generate_plan("做塔罗小程序")` → `{summary,team,flow,gates,risks}` 
- [ ] `system_health()` → `{status:"healthy",agent_count:40,...}`
- [ ] 外部框架通过 MCP 协议调通完整流程
- [ ] `bash scripts/self-test.sh` 18/18 通过
- [ ] 现有 14 个 Tool 行为不变
