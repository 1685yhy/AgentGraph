# 演示：前端工程师 → QA（Evidence Collector）交接

## 场景描述

前端工程师完成了一个 React 数据表格组件的开发，需要交付给 QA（Evidence Collector）进行质量验证。QA 需要无障碍审计报告和测试覆盖率数据才能开始工作。

## 前置条件

- AgentGuild Phase 1 已安装
- Handoff Engine (Phase 2a) 已部署
- 组件代码已提交

## 步骤

### 1. 准备交付物

```bash
mkdir -p /tmp/demo-component
```

前端工程师准备了以下文件：

```bash
cat > /tmp/demo-component/组件代码.md << 'EOF'
# DataTable 组件

React 虚拟化数据表格组件，支持：
- 虚拟滚动（10万行数据流畅渲染）
- 排序、筛选、多选
- 键盘导航
EOF

cat > /tmp/demo-component/组件文档.md << 'EOF'
# DataTable 使用文档

## Props
| 属性 | 类型 | 必填 | 说明 |
|------|------|------|------|
| data | T[] | 是 | 数据源 |
| columns | Column[] | 是 | 列定义 |
| onRowClick | (row: T) => void | 否 | 行点击回调 |
EOF
```

### 2. 创建交接

```bash
cd /mnt/e/agentguild
./guild handoff \
  --from frontend-engineer \
  --to evidence-collector \
  --path /tmp/demo-component \
  --message "DataTable 组件 v1.0，请进行质量验证"
```

**预期输出：**

```
创建交接 #3: frontend-engineer → evidence-collector
  状态: incomplete
  完整度: 2/4 项已提供
  [!!] 缺失 2 项:
       - 无障碍审计报告（键盘导航、屏幕阅读器兼容性）
       - 测试覆盖率报告（单元测试 > 80%，集成测试覆盖关键路径）
  记录: handoffs/2026-07-23-frontend-engineer-to-evidence-collector.json
```

### 3. 检查缺失项

```bash
./guild check --handoff 3
```

**预期输出：**

```
交接 #3: frontend-engineer → evidence-collector
状态: incomplete
时间: 2026-07-23T19:50:00+08:00
完整度: 2/4 项
缺失项:
  - 无障碍审计报告
  - 测试覆盖率报告
```

### 4. 补充缺失内容

QA 要求提供缺失的验证材料。前端工程师运行审计和测试：

```bash
cat > /tmp/demo-component/无障碍审计.md << 'EOF'
# DataTable 无障碍审计报告

## 键盘导航
- [x] Tab: 聚焦到表格
- [x] ↑↓: 行间移动
- [x] Space: 选中/取消行
- [x] Enter: 触发行点击

## 屏幕阅读器
- [x] NVDA: 正确朗读行号、列名、排序状态
- [x] VoiceOver: 正确朗读行号、列名、排序状态

## ARIA 标注
- [x] role="grid"
- [x] aria-label 每列
- [x] aria-sort 排序状态
EOF

cat > /tmp/demo-component/测试覆盖率.md << 'EOF'
# DataTable 测试覆盖率报告

## 单元测试
- 组件渲染: 12 个测试
- 排序逻辑: 8 个测试
- 筛选逻辑: 6 个测试
- 键盘导航: 10 个测试
- 覆盖率: 87%

## 集成测试
- 数据加载 → 渲染: 3 个测试
- 排序 → 筛选联动: 2 个测试
- 选择 → 批量操作: 2 个测试
EOF
```

### 5. 重新交接

```bash
./guild handoff \
  --from frontend-engineer \
  --to evidence-collector \
  --path /tmp/demo-component \
  --message "DataTable v1.0 完整交付（含审计和测试报告）"
```

**预期输出：**

```
创建交接 #4: frontend-engineer → evidence-collector
  状态: ready
  完整度: 4/4 项已提供
  记录: handoffs/2026-07-23-frontend-engineer-to-evidence-collector-v2.json
```

### 6. QA 接收

```bash
./guild accept --handoff 4 --as evidence-collector
```

**预期输出：**

```
交接 #4 已接收 — evidence-collector 开始工作
```

## 关键点

1. **QA 需要的不只是代码**——还需要审计报告和测试覆盖率——这是"协作契约"里写明的需求
2. **第一次交接被标记为 incomplete**——自动检查发现了缺失项，避免了 QA 拿到不完整交付物
3. **补全后重新交接通过**——前端补充了材料，第二次 handoff 完整度 4/4
4. **QA 显式接收**——`guild accept` 标记交接已确认，可以追溯责任链
