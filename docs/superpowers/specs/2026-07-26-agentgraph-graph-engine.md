# AgentGraph Graph Engine 设计

## 核心概念

从线性管道转向有向图。三个原语：

```
Node（节点）= Agent 执行一个动作
Edge（边）= 依赖关系 + 流转条件  
State（状态）= 整个图的共享进度
```

## 图定义格式（YAML）

```yaml
# graphs/feature-dev.yml
name: 功能开发
description: 单个功能的图式开发流程
nodes:
  define:
    agent: product-manager
    action: deliver
    delivers: [prd, user_stories]
    
  design:
    agent: ui-designer
    action: deliver
    needs: [define]
    delivers: [design_spec]
    
  build-frontend:
    agent: frontend-engineer
    needs: [define, design]
    delivers: [frontend_code]
    
  build-backend:
    agent: backend-architect
    needs: [define, design]
    delivers: [backend_code]
    
  test:
    agent: qa-engineer
    action: verify
    needs: [build-frontend, build-backend]
    
  approve:
    agent: creative-director
    needs: [test]
    when: { test: passed }
    
  fix:
    agent: frontend-engineer
    needs: [test]
    when: { test: failed }
    # fix完成后自动回路到test

edges:
  - from: test
    to: fix
    when: { test: failed }
    label: "测试不通过 → 打回修复"
    
  - from: fix  
    to: test
    label: "修复后重新测试（回路）"
    
  - from: test
    to: approve
    when: { test: passed }
    label: "测试通过 → 批准上线"
```

## CLI

```bash
guild graph run --graph <name> --path <dir> [--dry-run] [--yes]
guild graph status --graph <name>
guild graph show --graph <name>     # 可视化图结构
```

## 图引擎逻辑

```
1. 解析图定义 → 构建邻接表
2. 拓扑排序找到所有可执行节点（依赖已满足）
3. 可并行节点同时执行（bash 后台进程）
4. 每个节点执行后：
   a. 更新节点状态（running → completed|failed）
   b. 检查出边条件
   c. 如果有回路 → 重置目标节点 → 重新执行
5. 循环直到所有节点 completed 或 blocked
6. 输出图执行报告
```

## 跟现有系统的关系

- `guild handoff` → 变成节点间的自动动作，不再手动触发
- `guild verify` → 变成节点的 `action: verify`，自动运行
- `guild decide` → 图执行过程中的决策记录
- `guild pipeline` → 被 graph 取代（pipeline 是退化图）
- `guild status` → 扩展到显示图状态

## 交付

- `scripts/graph-engine.sh` — 图引擎
- `graphs/feature-dev.yml` — 功能开发图
- `graphs/game-mvp.yml` — 游戏开发图
- `graphs/iterate.yml` — 迭代图（含回路）
- `scripts/nexus.sh` 扩展 — `guild graph` 命令
- `docs/图引擎指南.md`
