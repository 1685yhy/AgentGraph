# Agent 协作系统详解

## 概述

AgentGraph 的 Agent 协作系统是一套让 AI Agent 之间**自主发现工作、自动接收通知、自动解决冲突**的协作框架。它解决了多 Agent 协作中最核心的问题：**Agent 不知道有什么工作在等着它们**。

在传统工作流中，人类是唯一的协调者——人类告诉每个 Agent 该做什么、什么时候做、是否需要调整。当 Agent 数量增多时，这种模式成为瓶颈。Agent 协作系统将协调工作从人类转移到系统层面，让 Agent 能够：

1. **发现待办工作**：通过收件箱（inbox）查看等待自己处理的任务
2. **接收变更通知**：当其他 Agent 做出影响自己的决策时自动收到通知
3. **自动解决冲突**：当多个 Agent 做出矛盾决策时，系统基于决策权重自动建议解决方案

## 系统架构

### 核心组件

```
AgentGraph/
├── context/
│   └── inbox/              # Agent 收件箱目录
│       ├── backend-architect.json
│       ├── frontend-engineer.json
│       └── ...             # 每个 Agent 一个收件箱文件
├── scripts/
│   ├── nexus.sh            # 核心引擎（handoff / decide / inbox / read / resolve）
│   ├── lib.sh              # 共享函数库（含 add_inbox_item）
│   └── agent-prompt.sh     # Agent 激活提示生成器
├── docs/
│   ├── Agent激活指南.md     # 用户操作指南
│   └── Agent协作系统详解.md  # 本文件 — 架构说明
```

### 收件箱数据结构

每个 Agent 的收件箱是一个 JSON 文件，结构如下：

```json
{
  "agent": "backend-architect",
  "updated": "2026-07-24T06:00:00Z",
  "unread": 3,
  "items": [
    {
      "id": "msg-001",
      "type": "handoff_incoming",
      "from": "product-manager",
      "timestamp": "2026-07-24T05:30:00Z",
      "summary": "PM 的 PRD 已传给你，但缺少性能目标和数据模型草案",
      "action": "要求 PM 补充缺失项后重新 handoff",
      "meta": "handoff_id=5",
      "read": false
    }
  ]
}
```

### 通知类型

| 类型 | 触发条件 | 通知内容 |
|------|----------|----------|
| `handoff_incoming` | 其他 Agent 创建交接给你 | 交接编号、发送方、完整性状态 |
| `decision_relevant` | 其他 Agent 做出了影响你的决策 | 决策主题、决策者、决策摘要 |
| `conflict_active` | 检测到你与其他 Agent 存在矛盾决策 | 冲突主题、冲突方、建议行动 |

## 自动化通知机制

### 何时触发通知

系统在三个关键操作后自动写收件箱：

1. **创建交接时**（`guild handoff`）
   - 动作：`add_inbox_item()` 写入接收方的收件箱
   - 类型：`handoff_incoming`
   - 自动检测交付物完整性（ready / incomplete）

2. **记录决策时**（`guild decide`）
   - 动作：遍历受影响的 Agent 列表，逐个写入收件箱
   - 类型：`decision_relevant`
   - 影响分析基于 `contracts/guild-contracts.yml` 中的依赖关系

3. **冲突检测时**（`guild context check` + handoff 上下文检查）
   - 动作：检测到同一主题上多个 Agent 有矛盾决策
   - 类型：`conflict_active`
   - 自动通知所有冲突方

### 实现原理

核心函数 `add_inbox_item()` 定义在 `scripts/lib.sh` 中：

```bash
add_inbox_item() {
  local agent="$1" type="$2" from="$3" meta="$4" summary="$5" action="$6"
  local inbox_file="$REPO_ROOT/context/inbox/${agent}.json"
  # 如果文件存在则追加，否则创建
  # 自动递增 unread 计数
  # 生成唯一 msg_id
}
```

## 新命令详解

### `guild inbox` — 查看收件箱

```bash
# 查看 Agent 的完整收件箱
guild inbox --agent backend-architect

# 仅查看未读消息
guild inbox --agent backend-architect --unread

# 查看所有有未读消息的 Agent
guild inbox
```

### `guild read` — 标记已读

```bash
# 标记所有消息为已读
guild read --agent backend-architect --all

# 仅标记未读消息
guild read --agent backend-architect
```

### `guild resolve` — 冲突解决

```bash
# 对特定主题进行冲突仲裁
guild resolve --topic "教师数据API响应格式"
```

系统自动：
1. 查找该主题上的所有决策
2. 列出参与冲突的 Agent
3. 基于主题关键词判断应由谁拥有最终决策权：
   - `api` / `database` / `model` / `endpoint` → **backend-architect**
   - `ui` / `design` / `interface` / `layout` → **ui-designer**
   - `game` / `mechanic` / `gameplay` → **game-designer**
   - `scope` / `feature` / `priority` / `prd` → **product-manager**
   - `security` / `auth` / `permission` → **security-engineer**

## 流水线全自动模式

`guild run --pipeline <name> --path <dir> --yes` 实现了完全无人值守的流水线执行：

- 移除所有 `read -r` 交互提示
- 跳过阶段间的手动确认
- 自动处理缺失项检查（跳过而非等待）
- 执行完毕后输出所有收件箱通知摘要

与标准模式对比：

| 特性 | 标准模式 | `--yes` 全自动 |
|------|----------|----------------|
| 阶段完成确认 | 等待按 Enter | 自动继续 |
| 缺失项处理 | 等待补充 | 跳过继续 |
| 最终报告 | 无 | 显示收件箱摘要 |

## 非技术读者理解指南

### 这个系统解决了什么问题？

想象一个软件团队有 30 个成员（Agent）。在传统方式下，项目经理（人类）需要：
- 告诉每个人什么时候该做什么
- 通知所有人谁做了什么决定
- 发现并调解矛盾

这个系统把这三件事自动化了：

1. **交接自动通知** → 就像有人把文件放在你桌上时，你的收件箱自动亮红灯
2. **决策自动通知** → 就像你的同事改了一个你正在用的工具，系统自动发邮件告诉你
3. **冲突自动检测** → 就像两个人画了不同的设计图，系统自动发现并建议谁该拍板

### 它为什么重要？

- **不需要人盯着**：之前项目经理（人类）需要全程盯着每个 Agent 的工作状态
- **Agent 可以自主工作**：每个 Agent 开始工作前自己检查收件箱，像人类上班先看邮件
- **冲突提前发现**：不需要等人发现了才处理，系统在决策记录时就检测到矛盾
- **决策有据可查**：每个决策都有记录，每个冲突都有历史，不会出现"不记得谁定的"

### 用户如何使用？

1. **开始工作前**：运行 `./scripts/agent-prompt.sh backend-architect` 或 `guild inbox --agent backend-architect`
2. **处理待办**：接收交接、确认决策、解决冲突
3. **标记完成**：运行 `guild read --agent backend-architect --all` 清零未读
4. **开始新任务**：收件箱清空后开始新的工作

## 技术集成

### 添加新的通知源

如果需要从其他操作触发收件箱通知，只需调用：

```bash
add_inbox_item "$target_agent" "custom_type" "$source_agent" \
  "key=value" \
  "描述文字" \
  "建议操作"
```

### 扩展决策权重

`cmd_resolve` 中的关键词匹配规则可以扩展。在 `case "$topic"` 语句中添加新的模式即可支持更多决策领域。

### 与外部系统集成

收件箱 JSON 文件可以被任何外部工具读取：
- CI/CD 系统可以在流水线中检查特定 Agent 的收件箱状态
- 监控工具可以跟踪未读消息数量变化
- Web 界面可以直接渲染收件箱 JSON
