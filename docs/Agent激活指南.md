# Agent 激活指南 — Inbox 感知工作流

## 什么是 Agent 收件箱？

AgentGuild 的每个 Agent 都有一个**收件箱**（inbox），存储在 `context/inbox/<agent-slug>.json`。收件箱自动接收以下类型的通知：

- **交接通知**（handoff_incoming）：其他 Agent 将交付物交给你时
- **决策通知**（decision_relevant）：其他 Agent 做出了影响你工作的决策时
- **冲突通知**（conflict_active）：你与其他 Agent 在同一主题上存在矛盾决策时

## 激活 Agent 的标准流程

当你要激活一个 Agent 开始工作时，请按照以下流程检查其收件箱：

### 方法 1：使用 agent-prompt 脚本

```bash
./scripts/agent-prompt.sh <agent-slug>
```

示例输出：

```
你是 Backend Architect。

在开始工作前，检查以下待办:

  🔵 1. 📨 [product-manager] PM 创建了交接 #5，存在缺失项待补充
      → 要求 PM 补充缺失项后重新 handoff

  🔵 2. ⚠️ [frontend-engineer] 你与 frontend-engineer 在 API响应格式 上存在矛盾决策
      → 基于决策权重协商解决

完成待办后开始新任务。
```

### 方法 2：使用 guild inbox 查看收件箱

```bash
# 查看单个 Agent 的收件箱
guild inbox --agent backend-architect

# 仅查看未读消息
guild inbox --agent backend-architect --unread

# 查看所有有未读消息的收件箱
guild inbox
```

### 方法 3：标记消息为已读

```bash
# 标记所有消息为已读
guild read --agent backend-architect --all

# 仅标记未读消息
guild read --agent backend-architect
```

## 在 Claude Code 中使用

在 Claude Code 中与 AgentGuild 的 Agent 协作时：

```
@Backend Architect, 先检查你的 guild inbox，然后开始工作
```

这会自动激活 Backend Architect，并让它在开始新工作前处理待办事项。

如果 Agent 有未处理的交接：

```
@Frontend Engineer, 检查收件箱，然后接受 handoff #5 开始工作
```

如果 Agent 有未解决的冲突：

```
@Backend Architect, 检查收件箱中的冲突，运行 guild resolve --topic "API响应格式"
```

## 工作流示例

### 场景 1：PM 将 PRD 交给后端架构师

```bash
# PM 创建交接
./guild handoff --from pm --to backend --path /tmp/prd

# Backend Architect 开始工作前
./scripts/agent-prompt.sh backend-architect
# → 显示收件箱中有一条交接通知

# 检查交接详情
./guild check --handoff <id>

# 接收交接并开始工作
./guild accept --handoff <id> --as backend-architect
```

### 场景 2：决策影响通知

```bash
# Security Engineer 记录认证方案决策
./guild decide --agent security-engineer --type api-design \
  --topic "认证方案" \
  --summary "使用 JWT + refresh token" \
  --rationale "安全性和用户体验的平衡" \
  --constraints "需要前端配合实现 token 刷新"

# Backend Architect 收到通知，确认 API 设计兼容
./guild inbox --agent backend-architect
./guild read --agent backend-architect --all
```

### 场景 3：检测并解决冲突

```bash
# 运行上下文检查
./guild context check
# → 发现冲突自动通知双方

# 运行冲突解决
./guild resolve --topic "教师数据API响应格式"
# → 系统根据决策权重建议由 backend-architect 最终拍板

# Backend Architect 记录最终决策
./guild decide --agent backend-architect --type api-design \
  --topic "教师数据API响应格式" \
  --summary "统一使用 {code: 0, data: {...}, message: ''}" \
  --authority backend-architect
```

## 最佳实践

1. **每次开始工作前检查收件箱**：养成习惯，先处理待办再开始新任务。
2. **及时标记已读**：处理完消息后立即标注为已读，保持收件箱干净。
3. **不要在收件箱中积压冲突**：冲突越早解决，返工成本越低。
4. **使用全自动流水线**：`./guild run --pipeline <name> --path <dir> --yes` 完全自动化执行。
