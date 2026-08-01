# AgentGraph v0.6a — 自建运行时引擎（文件系统 Event Bus）

**日期**: 2026-08-01
**版本**: v0.6.0-alpha
**状态**: 设计完成，待实现

---

## 1. 目标

AgentGraph 自主运转：用户提需求 → 自动调度 Agent → LLM 执行 → Graph 流转 → Gate 检查 → 交付产物。不依赖外部 AI 框架。

---

## 2. 核心组件

### 2.1 Agent Runner（新）
- 输入：Agent slug + 任务描述 + 上游交付物
- 流程：读取 agent .md → 组装 prompt → 调 LLM API → 保存输出 → 创建 handoff → 退出
- CLI：`guild run-agent <slug> "<task>" [--upstream <handoff-id>]`
- 返回：dispatch_id, output_path, handoff_id

### 2.2 Event Bus — 文件系统模式（新）
- 监听 `handoffs/` 目录的新文件（inotifywait / polling fallback）
- 检测到新 handoff → 解析 from/to/status → 如果 status=completed → 唤醒下游 Agent
- CLI：`guild watch [--once]`（--once 只等下一个事件，用于测试）

### 2.3 Graph Executor（改造）
- 基于现有 `graph-engine.sh`，改为事件驱动
- 解析 Graph YAML → 计算初始可执行节点（needs 为空）
- 启动初始 Agent → 等待 handoff 完成事件 → 解锁下游节点
- 支持回路的 fix→retest 循环
- CLI：`guild run --graph <name> --task "<description>"`

### 2.4 LLM Backend（新）
- 可插拔的 LLM API 适配
- 通过环境变量配置：`AG_LLM_PROVIDER`、`AG_LLM_API_KEY`、`AG_LLM_MODEL`
- 初始支持：openai / anthropic / deepseek
- 纯 Node.js 实现（内嵌在 runtime 中）

### 2.5 Memory Store（增强）
- 已有基础：`context/memory/<agent>/`
- 新增：每个 Agent 执行后自动存 prompt + response + timestamp
- 下次同 Agent 被调用时自动注入最近 3 次记忆作为上下文

---

## 3. 执行流程

```
guild run --graph feature-dev --task "做塔罗小程序"
    │
    ├─ 1. classify_task → miniapp
    ├─ 2. generate_plan → 7 agents, gates: 1 2 3 4
    ├─ 3. 解析 Graph YAML → 依赖图
    │
    ├─ 4. 初始节点: product-manager (needs: [])
    │      └─ guild run-agent product-manager "PRD: 塔罗小程序"
    │           └─ LLM API → 保存 PRD → handoff #N (status: completed)
    │
    ├─ 5. Event Bus 检测到 handoff #N
    │      ├─ ux-researcher (needs: [product-manager]) → 唤醒
    │      └─ backend-architect (needs: [product-manager]) → 并行唤醒
    │
    ├─ 6. ux-researcher 完成 → handoff → 唤醒 ui-designer
    │    backend-architect 完成 → handoff → ...（继续并行）
    │
    ├─ 7. 所有节点 completed → 最终 Gate 检查
    │
    └─ 8. 交付: 所有产物在 project/ 目录
```

---

## 4. LLM Backend 接口

```javascript
// scripts/llm-backend.js
async function callLLM({ provider, model, apiKey, systemPrompt, userPrompt, temperature }) {
  // provider: 'openai' | 'anthropic' | 'deepseek'
  // Returns: { text, usage: { input_tokens, output_tokens }, model }
}

// Provider config (env vars):
// AG_LLM_PROVIDER=anthropic   (default)
// AG_LLM_API_KEY=sk-...
// AG_LLM_MODEL=claude-sonnet-5-20251001
// AG_LLM_BASE_URL=https://api.deepseek.com/v1  (optional, for compatible APIs)
```

---

## 5. 文件结构

```
scripts/
├── runtime/
│   ├── agent-runner.sh      ← Agent 执行入口
│   ├── event-bus.sh         ← 文件系统事件监听
│   ├── llm-backend.js       ← LLM API 适配
│   └── run.sh               ← 顶层入口 (guild run)
├── graph-engine.sh          ← 改造：支持事件驱动执行
└── nexus.sh                 ← 新增 guild run / run-agent / watch 路由
```

---

## 6. 实现任务

| # | 任务 | 说明 |
|---|------|------|
| 1 | LLM Backend | `scripts/runtime/llm-backend.js`，支持 openai/anthropic/deepseek |
| 2 | Agent Runner | `scripts/runtime/agent-runner.sh`，组装 prompt → 调 LLM → 保存 |
| 3 | Event Bus | `scripts/runtime/event-bus.sh`，inotifywait + polling fallback |
| 4 | Graph Executor 改造 | 扩展现有 graph-engine.sh，事件驱动执行 |
| 5 | Memory 增强 | 自动注入最近记忆到 Agent prompt |
| 6 | CLI 集成 + 自测 | guild run/run-agent/watch 命令，端到端测试 |

---

## 7. 成功标准

- [ ] `guild run-agent product-manager "写PRD"` 能调通 LLM 并保存结果
- [ ] `guild watch --once` 能检测到 handoff 文件变化
- [ ] `guild run --graph feature-dev --task "简单网页"` 跑通完整 5 Agent 链条
- [ ] LLM Backend 支持 3 种 provider，切换只需改环境变量
- [ ] 自测 18/18 无回归
