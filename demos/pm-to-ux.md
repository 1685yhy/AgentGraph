# Demo 2: PM → UX Researcher — 用户研究需求交接

## 场景描述

产品经理（PM）需要针对教师备课场景展开用户研究，将研究需求交接给 UX 研究员（UX Researcher）。检查发现缺少明确的目标用户定义（用户群体和招募标准），PM 补充后重新 handoff 通过，UX 研究员接收并开始设计研究方案。

## 前置条件

- 项目根目录 `~/agentguild`，`guild` CLI 可用
- `product-manager` 和 `ux-researcher` 已在 `guild.config.json` 中注册
- `contracts/guild-contracts.yml` 中已有 `ux-researcher` 的契约定义

## 步骤

### 1. PM 准备研究需求文档

PM 写明了研究目标和背景，但缺少目标用户群体的具体定义。

```bash
cd ~/agentguild

mkdir -p /tmp/demo-research

cat > /tmp/demo-research/研究背景.md << 'EOF'
## 研究背景

教师备课效率提升模块即将进入设计阶段，我们需要深入了解教师当前的备课流程，
以便产品功能设计能够精准解决痛点。

## 研究目标

1. 了解教师备课的全流程环节及每个环节的耗时分布
2. 识别备课过程中最大的痛点（频率×影响程度）
3. 收集教师对"智能推荐"功能的期望和使用意愿
4. 验证一键备课方案的可行性
EOF

cat > /tmp/demo-research/研究范围.md << 'EOF'
## 研究范围

### 覆盖学科
数学、语文、英语（初中阶段）

### 地理范围
北京、上海、深圳三个城市

### 研究类型
定性研究为主，辅以定量问卷验证

### 时间计划
- 招募期：1 周
- 执行期：2 周
- 分析期：1 周
EOF
```

### 2. PM 发起交接（第一次 — 不完整）

```bash
./guild handoff \
  --from product-manager \
  --to ux-researcher \
  --path /tmp/demo-research \
  --message "教师备课场景用户研究需求"
```

**预期输出：**

```
创建交接 #3: product-manager → ux-researcher
  状态: incomplete
  完整度: 0/1 项已提供
  [!!] 缺失 1 项:
       - 明确的研究目标，表述为需要做出的决策，而非需要被确认的假设。目标用户群体和参与者的行为招募标准。
  记录: ~/agentguild/handoffs/2026-07-23-product-manager-to-ux-researcher.json
```

检查发现缺少**目标用户群体定义**和**参与者的行为招募标准**。现有文档虽然写了"教师"，但没有明确用户画像分层、样本量要求和招募筛选条件。

### 3. 检查具体缺失项

```bash
./guild check --handoff 3
```

**预期输出：**

```
交接 #3: product-manager → ux-researcher
状态: incomplete
时间: 2026-07-23T19:35:00+08:00
完整度: 0/1 项
缺失项:
  - 明确的研究目标，表述为需要做出的决策，而非需要被确认的假设。目标用户群体和参与者的行为招募标准。
```

### 4. PM 补充目标用户定义

```bash
cat > /tmp/demo-research/目标用户定义.md << 'EOF'
## 明确的研究目标与用户定义

### 研究目标（以决策形式表述）
- 决策 1：智能推荐算法应该优先优化"搜索耗时"还是"内容匹配度"？
  → 需要测量教师在各环节的平均耗时，对比用户对推荐准确度的容忍阈值
- 决策 2：一键备课功能是否值得独立成一个核心功能模块？
  → 需要验证教师对"完全自动生成"vs"半自动推荐"的偏好分布
- 决策 3：备课协作功能的最低可行范围是什么？
  → 需要确认教师之间协作备课的真实场景频率和痛点强度

### 目标用户群体
| 用户分层 | 比例 | 关键特征 |
|---------|------|---------|
| 核心教师 | 60% | 教龄 3-10 年，每周备课 10+ 课时，已形成固定备课模式 |
| 新教师 | 25% | 教龄 < 3 年，备课耗时长，对模板依赖度高 |
| 骨干教师 | 15% | 教龄 10+ 年，负责年级备课统筹，有协作需求 |

### 招募标准（行为导向，非人口统计）
- 每周至少使用电脑备课 5 次（排除不活跃用户）
- 过去一个月至少尝试过一种在线备课工具（确保有对比基线）
- 同时覆盖"独立备课型"和"协作备课型"两类行为模式
- 排除本校各学科备课组长（避免意见领袖偏差）

### 招募数量
- 深度访谈：每个用户分层 5-8 人，共计 18-24 人
- 可用性测试：8-10 人
- 定量问卷：200+ 样本（覆盖 3 个城市）
EOF
```

### 5. PM 重新发起交接（第二次 — 通过）

```bash
./guild handoff \
  --from product-manager \
  --to ux-researcher \
  --path /tmp/demo-research \
  --message "教师备课场景用户研究需求 v1.1（含目标用户定义）"
```

**预期输出：**

```
创建交接 #4: product-manager → ux-researcher
  状态: ready
  完整度: 1/1 项已提供
  记录: ~/agentguild/handoffs/2026-07-23-product-manager-to-ux-researcher.json
```

这次所有必需项已满足，状态为 `ready`。

### 6. UX 研究员接收交接

```bash
./guild accept --handoff 4 --as ux-researcher
```

**预期输出：**

```
接收交接 #4 ...
交接 #4 已接收 — ux-researcher 开始工作
```

### 7. 查看当前所有交接状态

```bash
./guild list
```

**预期输出：**

```
当前交接状态:

  ⚠️ #1: product-manager → backend-architect (incomplete) — 2026-07-23T19:30:00
  ✔️ #2: product-manager → backend-architect (accepted) — 2026-07-23T19:31:00
  ⚠️ #3: product-manager → ux-researcher (incomplete) — 2026-07-23T19:35:00
  ✔️ #4: product-manager → ux-researcher (accepted) — 2026-07-23T19:36:00
```

也可以用过滤参数只看特定代理的交接：

```bash
./guild status --agent ux-researcher
```

**预期输出：**

```
当前交接状态:

  ⚠️ #3: product-manager → ux-researcher (incomplete) — 2026-07-23T19:35:00
  ✔️ #4: product-manager → ux-researcher (accepted) — 2026-07-23T19:36:00
```

## 关键点

- **决策导向的研究目标**：契约要求研究目标以"需要做出的决策"而非"需要被确认的假设"形式表述。PM 补充时将笼统目标拆分为 3 个具体决策问题，大幅提升可执行性。
- **行为招募标准**：契约的深层意图是避免基于人口统计的刻板印象。PM 定义了基于实际行为（备课频次、工具使用习惯）的招募标准，而非简单按年龄/性别分层。
- **用户分层**：按教龄和使用模式将"教师"拆分为三个有行为差异的细分群体，每种群体有自己的招募配额。
- **agent 名字缩写支持**：CLI 支持别名解析。`./guild accept --handoff 4 --as ux` 也可以工作（匹配 slug `ux-researcher` 的前缀）。
