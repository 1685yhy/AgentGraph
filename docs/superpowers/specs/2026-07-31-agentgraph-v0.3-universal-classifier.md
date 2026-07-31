# AgentGraph v0.3 — 通用分类器与执行计划系统

**日期**: 2026-07-31
**版本**: v0.3.0
**状态**: 设计完成，待实现

---

## 1. 目标

用户用自然语言描述需求，AgentGraph 自动：
1. 识别这是什么类型的工作（分类器）
2. 匹配合适的 Agent 团队
3. 推荐 Graph 执行流程
4. 生成一页纸可确认的执行计划

**一句话：用户是老板，说人话就行，系统自动搞定后面一切。**

---

## 2. 战略定位

v0.3 是 AgentGraph "万能虚拟公司"路线图的第一步：

| 版本 | 内容 | 作用 |
|------|------|------|
| **v0.3** | 通用分类器 + 品类扩充 | 地基 — 之后所有品类都能被自动识别 |
| v0.4 | 补齐缺失品类（研究/设计/内容/大游戏/AI） | 品类全了，"万能"才有意义 |
| v0.5 | 多框架适配层（LangChain/CrewAI/AutoGPT） | B路线 — 让任意AI框架都能用 |
| v0.6+ | 自建运行时 | A路线 — AgentGraph自己跑 |

---

## 3. 扩展后的产品分类体系

从 9 种扩展到 18 种，分成 6 大类：

### 3.1 构建类（已有，保留）
- `wechat-game` — 微信/抖音小游戏
- `miniapp` — 微信小程序
- `web-app` — React全栈Web应用
- `dashboard` — 数据看板/BI
- `api-service` — 后端API服务
- `landing-page` — 落地页/营销站
- `corp-site` — 企业官网
- `admin-system` — 后台管理系统
- `mobile-app` — 移动App (iOS/Android)

### 3.2 研究策略类（新增）
- `research-report` — 用户调研、竞品分析、市场研究
- `strategy-consulting` — 产品策略、GTM策略、商业策划

### 3.3 设计品牌类（新增）
- `brand-identity` — 品牌VI、视觉系统、品牌手册
- `visual-design` — 海报、印刷品、营销物料

### 3.4 内容类（新增）
- `content-project` — 技术文档、营销文案、白皮书

### 3.5 大型游戏类（新增）
- `unity-game` — Unity 3D/2D 游戏
- `unreal-game` — Unreal Engine 5 项目

### 3.6 基础设施+AI（新增）
- `infra-project` — CI/CD、云架构、DevOps
- `ai-ml-project` — RAG、模型训练、AI集成

---

## 4. 通用分类器

### 4.1 设计原则

- **不依赖 LLM** — AgentGraph 本身是给 LLM 用的，分类器不能产生循环依赖
- **关键词 + 规则 + 能力映射** — 确定性的、可测试的
- **模糊时不瞎猜** — 置信度低时反问澄清，而不是随机选一个

### 4.2 分类流程

```
用户输入自然语言
    │
    ▼
1. 意图识别（动词分析）
   "做/开发/搭建/创建" → 构建类
   "分析/调研/研究/评估" → 研究策略类
   "设计/品牌/VI/Logo" → 设计品牌类
   "写/整理/文档/文案" → 内容类
    │
    ▼
2. 领域词匹配（名词分析）
   "小程序/微信" → miniapp
   "游戏/关卡/玩家" → 规模判断
   "后台/管理/CRUD/权限" → admin-system
   "App/iOS/Android" → mobile-app
   "数据/看板/报表/图表" → dashboard
   "品牌/Logo/VI/视觉" → brand-identity
   "Unity/C#/3D" → unity-game
   "Unreal/UE5/蓝图" → unreal-game
   "Python/训练/模型/RAG" → ai-ml-project
   "Docker/K8s/CI/CD" → infra-project
   "调研/竞品/用户研究" → research-report
   "策略/GTM/商业" → strategy-consulting
   "海报/印刷/物料" → visual-design
   "文档/文案/白皮书" → content-project
    │
    ▼
3. 技术栈词匹配
   "React/Vue/Next" → web-app
   "FastAPI/Express/Nest" → api-service
   "Taro/uni-app" → miniapp
   "Flutter/React Native" → mobile-app
    │
    ▼
4. 置信度计算
   每个匹配项加权计分 → 排序 → 取最高
   置信度 < 0.5 → 反问澄清
   多个类型接近 → 列出选项让用户选
    │
    ▼
5. 输出: { product_type, confidence, alternatives[] }
```

### 4.3 CLI

```bash
# 纯分类
guild classify "帮我做一个供应商后台管理系统"
# → JSON: { type: "admin-system", confidence: 0.92, alternatives: [...] }

# 分类 + 生成执行计划
guild plan "帮我做塔罗小程序"
# → 交互式执行计划

# JSON输出（AI框架可消费）
guild plan --json "帮我做塔罗小程序"
```

### 4.4 模糊需求处理

当置信度 < 0.5 或多个类型分数接近时：

```
🤔 "社交产品"有很多可能性：
  1. 微信小程序 — 最轻量，适合MVP
  2. 移动App — iOS+Android，功能更全
  3. Web应用 — 浏览器访问，最通用

  能多说一点吗？比如用户在什么场景下用？
```

---

## 5. 执行计划生成

### 5.1 计划结构

```yaml
plan:
  summary: "一句话概括"
  product_type: miniapp
  confidence: 0.92

team:
  lead: product-manager
  members:
    - agent: ux-researcher
      phase: 发现
      delivers: [用户画像, 竞品分析]
    - agent: ui-designer
      phase: 设计
      needs: [ux-researcher]
      delivers: [设计系统, 页面稿]
    # ...

flow:
  graph: feature-dev
  parallel_groups:
    - [ux-researcher, backend-architect]
    - [ui-designer]
    - [mobile-developer]

milestones:
  - [1] 需求定义完成
  - [2] 设计规范完成
  - [3] 开发完成
  - [4] 测试通过
  - [5] 交付

gates: "1 2 3 4"
estimated_iterations: 3-5

risks:
  - "风险描述 + 缓解建议"

next_step: "guild init --template miniapp ./my-project"
```

### 5.2 生成逻辑

1. **产品类型** → `capabilities.json` 查表 → agents, modules, gates, metrics
2. **Graph 匹配** → 构建类用 feature-dev（有回路），研究类用线性流水线（无回路），游戏类用 game-mvp（并行美术+程序）
3. **里程碑编排** → 从 Graph 的 nodes/edges 推导关键路径，标记可并行阶段
4. **风险推断** → 从产品类型的已知坑位生成

### 5.3 CLI

```bash
guild plan "做一个小程序"
# → 人类可读的执行计划，底部有 "确认启动? (y/n)"

guild plan --json "..."  # → JSON，AI框架直接消费
guild plan --yes "..."   # → 跳过确认，直接初始化
```

---

## 6. 架构改动

### 6.1 新架构

```
用户说人话
    │
    ▼
┌─────────────────────────────┐
│  guild classify (分类器)     │  ← v0.3 新增
│  自然语言 → 产品类型         │
└──────────┬──────────────────┘
           │
           ▼
┌─────────────────────────────┐
│  guild plan (计划器)         │  ← v0.3 新增
│  类型 → Agent团队+流程+里程碑│
└──────────┬──────────────────┘
           │
           ▼
┌─────────────────────────────┐
│  guild init (初始化)         │  ← 已有
└──────────┬──────────────────┘
           ▼
┌─────────────────────────────┐
│  guild graph run (执行)      │  ← 已有
└──────────┬──────────────────┘
           ▼
┌─────────────────────────────┐
│  guild gate (质量门禁)       │  ← 已有
└──────────┬──────────────────┘
           ▼
        交付物 ✅
```

### 6.2 文件改动清单

| 文件 | 改动 | 说明 |
|------|------|------|
| `capabilities.json` | 扩展 | 9→18种产品类型，新增9种定义 |
| `scripts/lib.sh` | 新增函数 | classify_engine(), generate_plan() |
| `scripts/nexus.sh` | 新增命令 | `classify`, `plan` 子命令 |
| `scripts/self-test.sh` | 扩展 | 新类型分类测试 + plan 输出验证 |
| `ai-manifest.json` | 更新 | 新增命令的AI可发现定义 |
| `templates/*/` | 新增9个 | 新类型的模板骨架 |
| `graphs/` | 新增2个 | research-report, unity-game 图定义 |

---

## 7. 实现任务

| # | 任务 | 优先级 | 依赖 |
|---|------|--------|------|
| 1 | 扩展 capabilities.json (9→18类型) | P0 | - |
| 2 | 分类器引擎 classify-engine.sh | P0 | 1 |
| 3 | `guild classify` + `guild plan` CLI | P0 | 2 |
| 4 | 新模板骨架 (9个) | P1 | 1 |
| 5 | 新 Graph 定义 (research-report, unity-game, unreal-game) | P1 | 1 |
| 6 | `guild plan` 交互式确认流程 | P1 | 3 |
| 7 | 自测扩展 + `guild status` bug修复 | P1 | 3 |
| 8 | 文档更新 | P2 | 全部 |

---

## 8. 成功标准

- [ ] `guild classify` 对18种类型各3个变体描述（共54个用例）准确率 > 95%
- [ ] `guild plan` 输出包含: product_type, team, flow, milestones, gates, risks
- [ ] 模糊输入（如"社交产品"）触发反问而非猜测
- [ ] `guild plan --json` 输出合法 JSON，AI框架可直接消费
- [ ] 自测14/15 → 全部通过（修复 guild status bug）
- [ ] 新自测覆盖分类器和计划器的核心路径
