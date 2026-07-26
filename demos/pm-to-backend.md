# Demo 1: PM → Backend Architect — PRD 交接与完整性检查

## 场景描述

产品经理（PM）完成了教师备课效率提升模块的 PRD，需要交接给后端架构师（Backend Architect）。交接时 Handoff Engine 自动进行完整性检查，发现缺少性能指标定义。PM 补充后重新交接通过，后端架构师接收并开始工作。

## 前置条件

- 项目根目录 `~/agentguild`，`guild` CLI 可用
- `product-manager` 和 `backend-architect` 已在 `guild.config.json` 中注册
- `contracts/guild-contracts.yml` 中已有 `backend-architect` 的契约定义

## 步骤

### 1. PM 准备 PRD 文档

PM 先写出问题陈述和用户故事，但遗漏了性能指标。

```bash
cd ~/agentguild

mkdir -p /tmp/demo-prd

cat > /tmp/demo-prd/问题陈述.md << 'EOF'
## 问题陈述

当前教师备课平均耗时 45 分钟/课时，大量时间花在重复性资源查找和 PPT 制作上。
教师需要跨多个平台搜索课件、习题和视频素材，缺乏一站式备课工具。

## 影响范围

- 涉及科目：数学、语文、英语（主科优先）
- 教师人数：约 2000 人
- 周备课频次：每人约 10 课时/周
EOF

cat > /tmp/demo-prd/用户故事.md << 'EOF'
## 用户故事

### US-001: 智能资源推荐
作为一名数学教师，我希望系统根据我的教学进度自动推荐相关课件和习题，
以便我不用花时间在多个平台搜索资源。

### US-002: 一键备课
作为一名语文教师，我希望选择一个知识点后系统自动生成完整的教案框架，
以便我只需微调即可完成备课。

### US-003: 备课协作
作为一名年级组长，我希望查看组内教师的备课进度并共享优质教案，
以便统一教学质量和进度。
EOF
```

### 2. PM 发起交接（第一次 — 不完整）

```bash
./guild handoff \
  --from product-manager \
  --to backend-architect \
  --path /tmp/demo-prd \
  --message "教师备课效率提升模块 PRD v1.0"
```

**预期输出：**

```
创建交接 #1: product-manager → backend-architect
  状态: incomplete
  完整度: 0/1 项已提供
  [!!] 缺失 1 项:
       - 带有清晰数据模型含义（实体、关系、基数、生命周期）的产品需求。预期流量模式（峰值 RPS、数据量、增长率）。
  记录: ~/agentguild/handoffs/2026-07-23-product-manager-to-backend-architect.json
```

交接状态为 `incomplete`——缺少后端架构师所需的**性能指标**和**流量模式**定义。

### 3. PM 检查哪些项目不完整

```bash
./guild check --handoff 1
```

**预期输出：**

```
交接 #1: product-manager → backend-architect
状态: incomplete
时间: 2026-07-23T19:30:00+08:00
完整度: 0/1 项
缺失项:
  - 带有清晰数据模型含义（实体、关系、基数、生命周期）的产品需求。预期流量模式（峰值 RPS、数据量、增长率）。
```

### 4. PM 补充性能指标文件

```bash
cat > /tmp/demo-prd/性能目标.md << 'EOF'
## 性能目标

本系统需要满足以下性能指标，数据模型需带有清晰数据模型含义：

### 流量预估
- 日活用户（DAU）：500 人同时在线
- 峰值 QPS：1000 req/s
- 单次备课请求数据量：约 50KB

### 延迟要求
- P99 响应时间：< 200ms
- P50 响应时间：< 50ms

### 数据模型
- 实体：教师、班级、课时、课件、习题集
- 关系：教师→班级（多对多）、课时→课件（一对多）
- 基数：平均每个教师 4 个班级，每个班级 20 课时/周
- 生命周期：备课数据保留 3 年，归档后可恢复

### 增长率
- 月活用户增长率：预期 15%/月（前 6 个月）
- 数据量增长：约 2GB/月
EOF
```

### 5. PM 重新发起交接（第二次 — 通过）

```bash
./guild handoff \
  --from product-manager \
  --to backend-architect \
  --path /tmp/demo-prd \
  --message "教师备课效率提升模块 PRD v1.1（含性能指标）"
```

**预期输出：**

```
创建交接 #2: product-manager → backend-architect
  状态: ready
  完整度: 1/1 项已提供
  记录: ~/agentguild/handoffs/2026-07-23-product-manager-to-backend-architect.json
```

状态为 `ready`——所有必需项已满足。

### 6. 后端架构师接收交接

```bash
./guild accept --handoff 2 --as backend-architect
```

**预期输出：**

```
接收交接 #2 ...
交接 #2 已接收 — backend-architect 开始工作
```

### 7. 验证交接状态

```bash
./guild status
```

**预期输出：**

```
当前交接状态:

  ⚠️ #1: product-manager → backend-architect (incomplete) — 2026-07-23T19:30:00
  ✔️ #2: product-manager → backend-architect (accepted) — 2026-07-23T19:31:00
```

## 关键点

- **完整度检查自动触发**：PM 发出 handoff 时，Engine 自动扫描目录文件并与契约中的需求对比，无需手动触发检查。
- **中文内容匹配**：扫描器通过文件名称模糊匹配和内容关键字搜索（取需求名前 8 个字符）来判定文件是否满足要求。`性能目标.md` 中包含了需求名的关键片段"带有清晰数据模型含义"，因此被正确识别。
- **版本化交接**：每次 handoff 生成独立记录，补全后重新 handoff 不会覆盖原记录，方便追溯历史。
- **状态流转**：`incomplete` → `ready` → `accepted`，每个状态明确可查。
