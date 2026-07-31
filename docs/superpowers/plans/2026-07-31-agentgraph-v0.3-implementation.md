# AgentGraph v0.3 — 通用分类器与执行计划系统 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用户自然语言描述需求 → 自动识别产品类型 → 输出完整执行计划（团队+流程+里程碑+风险）

**Architecture:** 扩展 `graph-generator.sh` 的分类器（18种产品类型），新增 `guild classify` 命令做纯分类 + JSON 输出，改进 `guild plan` 输出结构化执行计划。分类逻辑基于关键词+规则，不依赖 LLM。

**Tech Stack:** Bash 3.2+, Node.js (JSON处理), YAML (图定义)

**Spec:** `docs/superpowers/specs/2026-07-31-agentgraph-v0.3-universal-classifier.md`

## Global Constraints

- Bash 3.2+ 兼容，无 python3 硬依赖（设计文档中的降级目标：python3 调用保持 ≤7 处）
- 所有新功能必须在 `guild self-test` 中有对应测试
- `guild status` bug 必须在本版本修复（目前 14/15 通过）
- JSON 模式（`--json` 或 `AG_AI_MODE=1`）输出合法 JSON，AI 框架可直接消费
- 模糊分类（置信度 < 0.5）必须反问用户而非猜测

---

### Task 1: 扩展 capabilities.json — 9→18 种产品类型

**Files:**
- Modify: `capabilities.json`

**Interfaces:**
- Produces: `capabilities.json` 中 `product_types` 对象新增 9 种类型定义，每种包含 `label`, `template`, `description`, `agents`, `modules`, `gates`, `metrics`

- [ ] **Step 1: 在 capabilities.json 的 product_types 中新增 9 种类型**

在 `"mobile-app"` 条目之后、闭合 `}` 之前，插入以下 9 种类型定义。用 Edit 工具在 `capabilities.json` 中定位 `"mobile-app"` 的最后一行，在其后的 `}` 和 `},` 之间插入：

```json
    "research-report": {
      "label": "研究报告",
      "template": "research-report",
      "description": "用户调研、竞品分析、市场研究报告",
      "agents": ["product-manager","ux-researcher","data-analyst","tech-writer"],
      "modules": ["analytics"],
      "gates": "1 2",
      "metrics": ["report_completeness","insight_quality","recommendation_actionability"]
    },
    "strategy-consulting": {
      "label": "策略咨询",
      "template": "strategy-consulting",
      "description": "产品策略、GTM策略、商业策划书",
      "agents": ["product-manager","ux-researcher","data-analyst","growth-hacker","financial-analyst","content-creator"],
      "modules": ["analytics"],
      "gates": "1 2",
      "metrics": ["strategy_clarity","market_evidence","feasibility_score"]
    },
    "brand-identity": {
      "label": "品牌设计",
      "template": "brand-identity",
      "description": "品牌VI、视觉系统、品牌手册",
      "agents": ["brand-guardian","creative-director","ui-designer","content-creator"],
      "modules": ["ui-kit","i18n"],
      "gates": "1 2 4",
      "metrics": ["brand_consistency","visual_quality","guideline_completeness"]
    },
    "visual-design": {
      "label": "视觉设计",
      "template": "visual-design",
      "description": "海报、印刷品、营销视觉物料",
      "agents": ["creative-director","ui-designer","brand-guardian","content-creator"],
      "modules": ["ui-kit"],
      "gates": "1 2 4",
      "metrics": ["visual_quality","brand_alignment","production_readiness"]
    },
    "content-project": {
      "label": "内容项目",
      "template": "content-project",
      "description": "技术文档、营销文案、白皮书",
      "agents": ["tech-writer","content-creator","product-manager","seo-specialist"],
      "modules": ["seo","analytics","i18n"],
      "gates": "1 2",
      "metrics": ["content_quality","seo_score","readability"]
    },
    "unity-game": {
      "label": "Unity游戏",
      "template": "unity-game",
      "description": "Unity 3D/2D游戏，C#开发",
      "agents": ["game-designer","unity-developer","technical-artist","game-ui-designer","game-audio-engineer","game-qa-engineer","game-producer","monetization-designer"],
      "modules": ["game-patterns","save-system","tutorial","perf-monitor","analytics","iap","ui-kit","vfx","ab-test","social"],
      "gates": "1 2 3 4 5",
      "metrics": ["dau","session_length","retention_d1","retention_d7","fps","crash_rate"]
    },
    "unreal-game": {
      "label": "Unreal游戏",
      "template": "unreal-game",
      "description": "Unreal Engine 5项目，C++/蓝图",
      "agents": ["game-designer","unreal-developer","technical-artist","game-ui-designer","game-audio-engineer","game-qa-engineer","game-producer"],
      "modules": ["game-patterns","save-system","tutorial","perf-monitor","analytics","ui-kit","vfx","ab-test"],
      "gates": "1 2 3 4 5",
      "metrics": ["dau","session_length","retention_d1","retention_d7","fps","crash_rate"]
    },
    "infra-project": {
      "label": "基础设施",
      "template": "infra-project",
      "description": "CI/CD、云架构、DevOps基础设施",
      "agents": ["devops-engineer","backend-architect","security-engineer","qa-engineer"],
      "modules": ["auth-jwt","rate-limit","logging","health-check"],
      "gates": "1 2 3",
      "metrics": ["uptime","deploy_frequency","mttr","p99_latency"]
    },
    "ai-ml-project": {
      "label": "AI/ML项目",
      "template": "ai-ml-project",
      "description": "RAG系统、模型训练、AI集成",
      "agents": ["ai-engineer","backend-architect","data-analyst","qa-engineer","devops-engineer"],
      "modules": ["analytics","perf-monitor","logging"],
      "gates": "1 2 3",
      "metrics": ["accuracy","latency","throughput","model_size"]
    }
```

- [ ] **Step 2: 同步更新 capabilities.json 的 agents 映射**

在 `capabilities.json` 的 `"agents"` 对象中，为以下新增 agent 的 `product_types` 数组追加新的产品类型。用 Edit 逐个定位 agent slug，在已有的 `product_types` 数组末尾添加新条目：

- `"ui-designer"`: 追加 `"brand-identity","visual-design"`
- `"brand-guardian"`: 已有 `["corp-site","landing-page"]`，追加 `"brand-identity","visual-design"`
- `"creative-director"`: 已有 `["corp-site","landing-page","mobile-app"]`，追加 `"brand-identity","visual-design"`
- `"ux-researcher"`: 已有 `["miniapp","web-app","dashboard","admin-system","mobile-app"]`，追加 `"research-report","strategy-consulting"`
- `"data-analyst"`: 已有 `["dashboard","web-app"]`，追加 `"research-report","strategy-consulting","ai-ml-project"`
- `"tech-writer"`: 已有 `["api-service","web-app"]`，追加 `"research-report","content-project"`
- `"growth-hacker"`: 已有 `["landing-page","miniapp","mobile-app"]`，追加 `"strategy-consulting"`
- `"financial-analyst"`: 没有 `product_types` 字段，新增 `"product_types":["strategy-consulting"]`
- `"content-creator"`: 已有 `["landing-page","corp-site"]`，追加 `"strategy-consulting","brand-identity","visual-design","content-project"`
- `"seo-specialist"`: 已有 `["landing-page","corp-site","web-app"]`，追加 `"content-project"`
- `"devops-engineer"`: 已有 `["api-service","web-app","admin-system","mobile-app"]`，追加 `"infra-project","ai-ml-project"`
- `"ai-engineer"`: 已有 `["web-app","dashboard","mobile-app"]`，追加 `"ai-ml-project"`
- `"unity-developer"`: 没有 `product_types` 字段，新增 `"product_types":["unity-game"]`
- `"unreal-developer"`: 没有 `product_types` 字段，新增 `"product_types":["unreal-game"]`
- `"monetization-designer"`: 已有 `["wechat-game"]`，追加 `"unity-game"`

- [ ] **Step 3: 验证 JSON 合法性**

```bash
cd /mnt/e/agentguild && node -e "JSON.parse(require('fs').readFileSync('capabilities.json','utf8')); console.log('OK')"
```
Expected: `OK`

- [ ] **Step 4: 验证新类型可被查询**

```bash
cd /mnt/e/agentguild && ./guild capability research-report && ./guild capability unity-game
```
Expected: 两种类型都显示 Agent 列表和模块信息

- [ ] **Step 5: Commit**

```bash
cd /mnt/e/agentguild
git add capabilities.json
git commit -m "feat: capabilities 9→18种产品类型 (新增研究/策略/品牌/视觉/内容/Unity/Unreal/基础设施/AI)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: 扩展 graph-generator.sh 分类器 — 18 种类型全覆盖

**Files:**
- Modify: `scripts/graph-generator.sh:27-99`

**Interfaces:**
- Consumes: Task 1 的 `capabilities.json`（18 种类型定义）
- Produces: 扩展后的 `TYPE_AGENTS` 数组（18 种），`classify_task_fallback()` 支持全部 18 种类型的关键词，`select_gates()` 支持全部门禁策略

- [ ] **Step 1: 扩展 TYPE_AGENTS 数组**

在 `scripts/graph-generator.sh` 中，定位 `TYPE_AGENTS["marketing"]=` 那一行（约第 61 行），在其后添加 9 种新类型的 Agent 链：

```bash
# research-report: 研究报告
TYPE_AGENTS["research-report"]="product-manager ux-researcher data-analyst tech-writer"

# strategy-consulting: 策略咨询
TYPE_AGENTS["strategy-consulting"]="product-manager ux-researcher data-analyst growth-hacker financial-analyst content-creator"

# brand-identity: 品牌设计
TYPE_AGENTS["brand-identity"]="brand-guardian creative-director ui-designer content-creator"

# visual-design: 视觉设计
TYPE_AGENTS["visual-design"]="creative-director ui-designer brand-guardian content-creator"

# content-project: 内容项目
TYPE_AGENTS["content-project"]="product-manager tech-writer content-creator seo-specialist"

# unity-game: Unity 3D/2D 游戏
TYPE_AGENTS["unity-game"]="game-designer unity-developer technical-artist game-ui-designer game-audio-engineer monetization-designer game-qa-engineer game-producer"

# unreal-game: Unreal Engine 5 项目
TYPE_AGENTS["unreal-game"]="game-designer unreal-developer technical-artist game-ui-designer game-audio-engineer game-qa-engineer game-producer"

# infra-project: DevOps/基础设施
TYPE_AGENTS["infra-project"]="devops-engineer backend-architect security-engineer qa-engineer"

# ai-ml-project: AI/ML 项目
TYPE_AGENTS["ai-ml-project"]="ai-engineer backend-architect data-analyst qa-engineer devops-engineer"
```

- [ ] **Step 2: 扩展 classify_task_fallback 的关键词映射**

在 `classify_task_fallback()` 函数中（约第 78-99 行），定位 `for pair in` 循环体，扩展关键词列表。替换整个 `for pair in \ ... done` 块：

```bash
  for pair in \
    "research-report:调研 用户研究 竞品 访谈 可用性测试 焦点小组 问卷 市场研究 行业分析" \
    "strategy-consulting:策略 GTM 商业模式 商业计划 产品战略 定价策略 路线图 进入市场 商业策划" \
    "brand-identity:品牌 VI Logo 视觉识别 品牌手册 品牌指南 品牌设计 标志" \
    "visual-design:海报 印刷 物料 宣传册 展板 包装 视觉设计 平面设计" \
    "content-project:写文档 文案 白皮书 技术文档 用户手册 博客 内容 strategy-consulting 写作 编辑" \
    "unity-game:Unity unity C# 3D游戏 2D游戏 unity3d" \
    "unreal-game:Unreal UE5 UE4 蓝图 虚幻引擎 虚幻" \
    "infra-project:Docker K8s Kubernetes CI/CD DevOps 运维 部署 云架构 Terraform" \
    "ai-ml-project:机器学习 深度学习 模型训练 LLM RAG 大模型 NLP 神经网络 AI模型" \
    "wechat-game:小游戏 微信小游戏 抖音小游戏 H5游戏 休闲游戏 消除 合成 三消" \
    "web-app:页面 网站 后台 管理 注册 登录 表单 报表 供应商 门户 控制台 账号" \
    "landing-page:落地页 官网 landing 主页 首页 品牌页" \
    "api-service:API 接口 后端服务 restful graphql 微服务" \
    "miniapp:小程序 微信 抖音小程序 小程序开发" \
    "mobile-app:APP 安卓 iOS 移动端 手机应用 Flutter React Native" \
    "dashboard:看板 报表 图表 数据可视化 统计 监控 大屏 BI" \
    "admin-system:后台管理 管理系统 CRUD 权限管理 审批流 后台系统" \
    "corp-site:企业官网 公司网站 企业站 品牌官网"; do
```

注意：`"content-project"` 的关键词中 `strategy-consulting` 要去掉（那是误输入的另一个类型名）。实际关键词应为 `"写文档 文案 白皮书 技术文档 用户手册 博客 内容 写作 编辑"`。

- [ ] **Step 3: 扩展 select_gates() 函数的类型映射**

在 `select_gates()` 函数中（约第 341-361 行），定位 `case "$type" in` 块，扩展为：

```bash
  case "$type" in
    web-app|landing-page|miniapp|mobile-app|full-stack|admin-system|corp-site)
      gates="$gates 3 4"  # behavior + playability
      ;;
    api-service|infra-project|ai-ml-project)
      gates="$gates 3"    # behavior only
      ;;
    wechat-game|unity-game|unreal-game)
      gates="$gates 3 4 5" # behavior + playability + agent-standards
      ;;
    research-report|strategy-consulting|brand-identity|visual-design|content-project)
      gates="1 2"          # completeness + syntax only (no behavior testing for docs)
      ;;
  esac
```

- [ ] **Step 4: 修复 select_agents() 中的类型匹配**

定位 `select_agents()` 函数中的 UI 类型检查（约第 167-170 行），将旧的类型名更新为新的：

```bash
  # Add accessibility-auditor for UI types
  case "$type" in
    web-app|landing-page|miniapp|dashboard|mobile-app|full-stack|admin-system|corp-site|brand-identity|visual-design)
      [[ "$agents" != *accessibility-auditor* ]] && agents="$agents accessibility-auditor";;
  esac
```

- [ ] **Step 5: 验证分类器覆盖所有 18 种类型**

```bash
cd /mnt/e/agentguild && bash -c '
source scripts/graph-generator.sh 2>/dev/null
tests=(
  "做一个用户调研报告:research-report"
  "写一份GTM策略方案:strategy-consulting"
  "设计一个品牌Logo和VI系统:brand-identity"
  "做一张活动海报:visual-design"
  "写一份产品白皮书:content-project"
  "用Unity做一个3D射击游戏:unity-game"
  "用Unreal Engine 5做一个开放世界:unreal-game"
  "搭建CI/CD流水线:infra-project"
  "训练一个文本分类模型:ai-ml-project"
  "做一个微信小游戏:wechat-game"
  "做一个后台管理系统:admin-system"
  "做一个公司官网:corp-site"
  "做一个数据分析看板:dashboard"
  "做一个微信小程序:miniapp"
  "做一个移动端App:mobile-app"
  "做一个React全栈网站:web-app"
  "做一个API后端服务:api-service"
  "做一个营销落地页:landing-page"
)
passed=0; failed=0
for t in "${tests[@]}"; do
  input="${t%%:*}"
  expected="${t##*:}"
  result=$(classify_task_fallback "$input")
  if [[ "$result" == "$expected" ]]; then
    echo "[OK]  $input → $result"
    passed=$((passed + 1))
  else
    echo "[FAIL] $input → got $result, expected $expected"
    failed=$((failed + 1))
  fi
done
echo "$passed passed, $failed failed"
'
```
Expected: 18/18 通过

- [ ] **Step 6: Commit**

```bash
cd /mnt/e/agentguild
git add scripts/graph-generator.sh
git commit -m "feat: graph-generator 分类器扩展至18种产品类型

TYPE_AGENTS: +9种 (research-report..ai-ml-project)
classify_task_fallback: 关键词覆盖所有18种类型
select_gates: 新增类型门禁策略
select_agents: 新增品牌/设计类型的无障碍审计

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: 新增 guild classify 命令 — 纯分类 + JSON 输出

**Files:**
- Modify: `scripts/graph-generator.sh` (add `cmd_classify` function)
- Modify: `scripts/nexus.sh:446` (add `classify` route)

**Interfaces:**
- Consumes: Task 2 的扩展分类器函数
- Produces: `cmd_classify()` 函数，`guild classify "task"` CLI 命令
- 输出: `{type, label, confidence, alternatives[], agents[], template, gates}` JSON

- [ ] **Step 1: 在 graph-generator.sh 末尾添加 cmd_classify() 函数**

在 `build_product` 函数之后（约第 461 行之后）、`# ── CLI entry` 注释之前，添加：

```bash
# ── Classify command ──────────────────────────────────────────────────
# Standalone classification + confidence scoring
# Usage: guild classify "task description"
#        guild classify --json "task description"
classify_score() {
  local task="$1" type="$2"
  local score=0
  # Count keyword matches for this type against the task
  local kws=""
  case "$type" in
    research-report) kws="调研 用户研究 竞品 访谈 可用性测试 焦点小组 问卷 市场研究 行业分析";;
    strategy-consulting) kws="策略 GTM 商业模式 商业计划 产品战略 定价策略 路线图 进入市场";;
    brand-identity) kws="品牌 VI Logo 视觉识别 品牌手册 品牌指南 标志";;
    visual-design) kws="海报 印刷 物料 宣传册 展板 包装 视觉设计 平面设计";;
    content-project) kws="写文档 文案 白皮书 技术文档 用户手册 博客 内容 写作";;
    unity-game) kws="Unity unity C# 3D游戏 2D游戏 unity3d";;
    unreal-game) kws="Unreal UE5 UE4 蓝图 虚幻引擎";;
    infra-project) kws="Docker K8s Kubernetes CI/CD DevOps 运维 部署 云架构 Terraform";;
    ai-ml-project) kws="机器学习 深度学习 模型训练 LLM RAG 大模型 NLP 神经网络";;
    wechat-game) kws="小游戏 微信小游戏 抖音小游戏 H5游戏 休闲游戏 消除 三消";;
    web-app) kws="页面 网站 注册 登录 表单 门户 控制台";;
    landing-page) kws="落地页 官网 landing 主页 首页 品牌页";;
    api-service) kws="API 接口 后端服务 restful graphql 微服务";;
    miniapp) kws="小程序 微信小程序 抖音小程序";;
    mobile-app) kws="APP 安卓 iOS 移动端 手机应用 Flutter React Native";;
    dashboard) kws="看板 报表 图表 数据可视化 统计 监控 大屏 BI";;
    admin-system) kws="后台管理 管理系统 CRUD 权限管理 审批流";;
    corp-site) kws="企业官网 公司网站 企业站";;
  esac
  for kw in $kws; do
    echo "$task" | grep -qi "$kw" && score=$((score + 1))
  done
  echo $score
}

cmd_classify() {
  local task="$1"
  [[ -z "$task" ]] && { err "Usage: guild classify \"<task description>\""; return 1; }

  local best_type best_score=0 best_label=""
  local -a scores=()

  # Score all 18 types
  for type in research-report strategy-consulting brand-identity visual-design content-project \
              unity-game unreal-game infra-project ai-ml-project \
              wechat-game web-app landing-page api-service miniapp mobile-app dashboard admin-system corp-site; do
    local s; s=$(classify_score "$task" "$type")
    scores+=("$type:$s")
    if [[ $s -gt $best_score ]]; then
      best_score=$s
      best_type="$type"
    fi
  done

  # Get type metadata from capabilities.json
  local label
  label=$(node -e "const c=JSON.parse(require('fs').readFileSync('$REPO_ROOT/capabilities.json','utf8'));console.log((c.product_types['$best_type']||{}).label||'$best_type')" 2>/dev/null || echo "$best_type")

  # Collect alternatives (types with score > 0, sorted)
  local alternatives="[]"
  if command -v node &>/dev/null; then
    alternatives=$(printf '%s\n' "${scores[@]}" | sort -t: -k2 -rn | while IFS=: read -r t s; do
      [[ "$t" == "$best_type" ]] && continue
      [[ "$s" -eq 0 ]] && continue
      local tl; tl=$(node -e "const c=JSON.parse(require('fs').readFileSync('$REPO_ROOT/capabilities.json','utf8'));console.log((c.product_types['$t']||{}).label||'$t')" 2>/dev/null || echo "$t")
      echo "{\"type\":\"$t\",\"label\":\"$tl\",\"score\":$s}"
    done | node -e "const lines=require('fs').readFileSync('/dev/stdin','utf8').trim().split('\n').filter(Boolean).slice(0,3);console.log(JSON.stringify(lines.map(l=>JSON.parse(l))))" 2>/dev/null || echo "[]")
  fi

  # Get template and gates from capabilities
  local template gates
  template=$(node -e "const c=JSON.parse(require('fs').readFileSync('$REPO_ROOT/capabilities.json','utf8'));console.log((c.product_types['$best_type']||{}).template||'$best_type')" 2>/dev/null || echo "$best_type")
  gates=$(node -e "const c=JSON.parse(require('fs').readFileSync('$REPO_ROOT/capabilities.json','utf8'));console.log((c.product_types['$best_type']||{}).gates||'1 2')" 2>/dev/null || echo "1 2")

  # Calculate confidence: best_score / max_possible (capped at 1.0)
  local confidence="0.0"
  if [[ $best_score -gt 0 ]]; then
    confidence=$(node -e "console.log(Math.min(1.0, $best_score / 5).toFixed(2))" 2>/dev/null || echo "0.5")
  fi

  # Low confidence → ask user instead of guessing
  if [[ "$(echo "$confidence < 0.5" | bc -l 2>/dev/null || echo 0)" == "1" ]] || [[ "$best_score" -eq 0 ]]; then
    if [[ "${AG_AI_MODE:-}" == "1" ]] || [[ "${1:-}" == "--json" ]]; then
      # JSON mode: return low-confidence flag
      node -e "console.log(JSON.stringify({type:'$best_type',label:'$label',confidence:$confidence,alternatives:$alternatives,template:'$template',gates:'$gates',low_confidence:true,message:'请提供更多细节以准确分类'}))"
    else
      echo "🤔 需求描述不够明确，无法确定项目类型。"
      echo ""
      if [[ "$(echo "$alternatives" | node -e "const a=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));console.log(a.length)" 2>/dev/null || echo 0)" != "0" ]]; then
        echo "可能的类型："
        echo "$alternatives" | node -e "const a=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));a.forEach(x=>console.log('  - '+x.label+' ('+x.type+')'))" 2>/dev/null
      fi
      echo ""
      echo "能多说一点吗？比如目标用户是谁、在什么场景下使用？"
    fi
    return 0
  fi

  # Output classification result
  if [[ "${AG_AI_MODE:-}" == "1" ]] || [[ "${2:-}" == "--json" ]]; then
    node -e "console.log(JSON.stringify({type:'$best_type',label:'$label',confidence:$confidence,alternatives:$alternatives,template:'$template',gates:'$gates'},null,2))"
  else
    echo "📋 $label ($best_type)"
    echo "   置信度: $confidence"
    if [[ "$alternatives" != "[]" ]]; then
      echo "   备选: $(echo "$alternatives" | node -e "const a=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));console.log(a.map(x=>x.label).join(', '))" 2>/dev/null)"
    fi
  fi
}
```

- [ ] **Step 2: 在 nexus.sh 中添加 classify 路由**

在 `scripts/nexus.sh` 的 `case "$CMD" in` 块中，在 `capability) capability_show "$1";;` 行之后添加：

```bash
  classify)  cmd_classify "$*";;
```

- [ ] **Step 3: 更新 nexus.sh 帮助文本**

在 `scripts/nexus.sh` 的 `if [[ $# -eq 0 ]]` 帮助文本块中，在 `guild plan` 相关行附近添加：

```bash
  echo "  guild classify  — 识别需求类型 (自然语言 → 产品类型 + 置信度)"
```

同时将 `guild plan` 帮助行从任意现有行更新为：
```bash
  echo "  guild plan     — 生成完整执行计划 (类型 + 团队 + 流程 + 里程碑 + 风险)"
```

- [ ] **Step 4: 测试 classify 命令**

```bash
cd /mnt/e/agentguild

# 明确需求 → 高置信度
./guild classify "帮我做一个供应商后台管理系统"
# Expected: 📋 后台管理系统 (admin-system)  置信度: 0.80+

# JSON 模式
./guild classify --json "帮我做塔罗小程序"
# Expected: JSON with type=miniapp, confidence > 0.5

# 模糊需求 → 反问
./guild classify "做一个社交产品"
# Expected: 🤔 需求描述不够明确...
```

- [ ] **Step 5: Commit**

```bash
cd /mnt/e/agentguild
git add scripts/graph-generator.sh scripts/nexus.sh
git commit -m "feat: guild classify 命令 — 自然语言→产品类型+置信度

18种类型评分，置信度<0.5反问用户
--json 模式输出AI框架可消费的JSON
AI模式(AG_AI_MODE=1)自动启用JSON输出

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: 改进 guild plan — 结构化执行计划输出

**Files:**
- Modify: `scripts/graph-generator.sh:364-436` (`generate_graph` 函数)

**Interfaces:**
- Consumes: Task 2 的分类器, Task 3 的 `cmd_classify`, `capabilities.json`
- Produces: 增强的 `generate_graph()` → 输出包含 team/milestones/gates/risks/next_step 的结构化执行计划

- [ ] **Step 1: 在 generate_graph() 中添加里程碑和风险推断**

定位 `generate_graph()` 函数（约第 364 行），在 graph YAML 输出之前插入结构化计划输出。修改函数主体，在 `echo "$graph_yaml"` 之前添加以下计划输出逻辑。

找到函数中 `echo "  🚪 Gate 选择: $gates"` 这一行（约第 419 行），在其后添加：

```bash
  # ── Build structured execution plan ──────────────────────────────
  echo ""
  echo "╔══════════════════════════════════════════╗"
  echo "║  📋 执行计划                             ║"
  echo "╚══════════════════════════════════════════╝"
  echo ""
  
  # Summary
  local summary; summary=$(echo "$task" | cut -c1-80)
  echo "  📝 项目: $summary"
  echo "  🏷️  类型: $type_label"
  echo ""
  
  # Team
  echo "  👥 团队 (${agent_count}人):"
  for a in $agents; do
    local aname aemoji
    aname=$(agent_frontmatter "$a" "name" 2>/dev/null || echo "$a")
    aemoji=$(agent_frontmatter "$a" "emoji" 2>/dev/null || echo "")
    echo "      $aemoji $aname ($a)"
  done
  echo ""
  
  # Milestones from graph node ordering
  echo "  🗺️  关键里程碑:"
  local milestone_num=1
  for a in $agents; do
    local mname; mname=$(agent_frontmatter "$a" "name" 2>/dev/null || echo "$a")
    case "$a" in
      product-manager|game-designer) echo "      [$milestone_num] 需求定义完成 — $mname"; milestone_num=$((milestone_num + 1));;
      ui-designer|ux-researcher|brand-guardian|creative-director) echo "      [$milestone_num] 设计完成 — $mname"; milestone_num=$((milestone_num + 1));;
      frontend-engineer|backend-architect|mobile-developer|unity-developer|unreal-developer|game-programmer) echo "      [$milestone_num] 开发完成 — $mname"; milestone_num=$((milestone_num + 1));;
      qa-engineer|game-qa-engineer|performance-tester) echo "      [$milestone_num] 测试通过 — $mname"; milestone_num=$((milestone_num + 1));;
      security-engineer) echo "      [$milestone_num] 安全审查通过 — $mname"; milestone_num=$((milestone_num + 1));;
      game-producer|creative-director) echo "      [$milestone_num] 最终审核交付 — $mname"; milestone_num=$((milestone_num + 1));;
    esac
  done
  echo ""
  
  # Gates
  echo "  🚦 质量门禁: $gates"
  echo ""
  
  # Risks (type-specific)
  echo "  ⚠️  关键风险:"
  case "$type" in
    miniapp)
      echo "      - 微信审核政策风险 — 避免敏感内容";;
    wechat-game|unity-game|unreal-game)
      echo "      - 游戏可玩性风险 — 核心循环需充分测试"
      echo "      - 性能风险 — 目标设备帧率需达标";;
    admin-system)
      echo "      - RBAC权限设计复杂度 — 提前梳理角色矩阵"
      echo "      - 审批流逻辑 — 需与业务方逐条确认";;
    mobile-app)
      echo "      - 应用商店审核 — iOS/Android 各有规范"
      echo "      - 多设备兼容 — 屏幕尺寸和系统版本覆盖";;
    research-report|strategy-consulting)
      echo "      - 数据来源可靠性 — 标注所有数据出处"
      echo "      - 建议可行性 — 需结合客户实际资源评估";;
    brand-identity|visual-design)
      echo "      - 品牌调性对齐 — 需提前确认品牌基因"
      echo "      - 交付格式 — 确认甲方需要的源文件格式";;
    ai-ml-project)
      echo "      - 数据质量 — GIGO: 垃圾进垃圾出"
      echo "      - 模型部署成本 — GPU资源预估";;
    infra-project)
      echo "      - 生产环境差异 — dev/staging/prod 一致性"
      echo "      - 密钥管理 — 敏感信息不能进代码仓库";;
    *) echo "      - 需求范围蔓延 — 确认MVP边界";;
  esac
  echo ""
  
  # Next step
  echo "  ▶️  下一步: guild init --template $type ./my-project"
```

- [ ] **Step 2: 添加 --json 输出支持**

在 `generate_graph()` 函数开头（参数解析之后）添加 JSON 模式检测：

```bash
  local json_mode=false
  if [[ "${AG_AI_MODE:-}" == "1" ]] || [[ "${1:-}" == "--json" ]] || [[ "${2:-}" == "--json" ]]; then
    json_mode=true
  fi
```

在计划输出之后、Graph YAML 输出之前，添加 JSON 分支：

```bash
  if $json_mode; then
    # Build JSON plan for AI consumption
    local agents_json; agents_json=$(for a in $agents; do
      local an; an=$(agent_frontmatter "$a" "name" 2>/dev/null || echo "$a")
      echo "{\"slug\":\"$a\",\"name\":\"$an\"}"
    done | node -e "const lines=require('fs').readFileSync('/dev/stdin','utf8').trim().split('\n').filter(Boolean);console.log(JSON.stringify(lines.map(l=>JSON.parse(l))))" 2>/dev/null || echo "[]")
    
    node -e "
      const plan = {
        summary: '$summary',
        product_type: '$type',
        label: '$type_label',
        confidence: $confidence,
        team: { lead: '${agents%% *}', members: $agents_json },
        flow: { graph: 'feature-dev' },
        gates: '$gates',
        risks: $(node -e "console.log(JSON.stringify(require('fs').readFileSync('/dev/stdin','utf8').trim()))" <<< "$risks_json" 2>/dev/null || echo '[]')
      };
      console.log(JSON.stringify(plan, null, 2));
    "
    return 0
  fi
```

- [ ] **Step 3: 添加交互式确认**

在 `generate_graph()` 函数的 Graph YAML 输出之后，添加确认提示：

```bash
  # Interactive confirmation
  if [[ "${AG_AI_MODE:-}" != "1" ]]; then
    echo ""
    read -p "  确认启动? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo "  已取消。"
      return 0
    fi
  fi
```

- [ ] **Step 4: 测试 plan 命令**

```bash
cd /mnt/e/agentguild

# 完整执行计划
echo "y" | ./guild plan "帮我做塔罗小程序"
# Expected: 团队列表 + 里程碑 + 风险 + "确认启动?"

# JSON 模式
AG_AI_MODE=1 ./guild plan "做一个后台管理系统"
# Expected: valid JSON with summary, product_type, team, flow, gates, risks
```

- [ ] **Step 5: Commit**

```bash
cd /mnt/e/agentguild
git add scripts/graph-generator.sh
git commit -m "feat: guild plan 结构化执行计划 (团队+里程碑+门禁+风险+确认)

输出包含: 项目概况、团队列表、关键里程碑、质量门禁、类型特定风险、下一步
JSON模式: AI框架可直接消费
交互模式: 用户确认后才启动

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 5: 新增模板骨架（9 个新类型）

**Files:**
- Create: `templates/research-report/`, `templates/strategy-consulting/`, `templates/brand-identity/`, `templates/visual-design/`, `templates/content-project/`, `templates/unity-game/`, `templates/unreal-game/`, `templates/infra-project/`, `templates/ai-ml-project/`

**Interfaces:**
- Produces: 9 个模板目录，每个至少有 `template.json` 元数据文件

- [ ] **Step 1: 批量创建 9 个模板目录和 template.json**

```bash
cd /mnt/e/agentguild

declare -A TEMPLATES
TEMPLATES=(
  ["research-report"]="研究报告|用户调研、竞品分析、市场研究报告"
  ["strategy-consulting"]="策略咨询|产品策略、GTM策略、商业策划"
  ["brand-identity"]="品牌设计|品牌VI、视觉系统、品牌手册"
  ["visual-design"]="视觉设计|海报、印刷品、营销物料"
  ["content-project"]="内容项目|技术文档、营销文案、白皮书"
  ["unity-game"]="Unity游戏|Unity 3D/2D游戏项目"
  ["unreal-game"]="Unreal游戏|Unreal Engine 5项目"
  ["infra-project"]="基础设施|CI/CD、云架构、DevOps"
  ["ai-ml-project"]="AI/ML项目|RAG系统、模型训练、AI集成"
)

for tmpl in "${!TEMPLATES[@]}"; do
  IFS='|' read -r label desc <<< "${TEMPLATES[$tmpl]}"
  mkdir -p "templates/$tmpl"
  cat > "templates/$tmpl/template.json" << EOF
{
  "name": "$tmpl",
  "label": "$label",
  "description": "$desc",
  "version": "0.1.0",
  "init_command": "guild init --template $tmpl <project-dir>",
  "capabilities": "$(node -e "const c=JSON.parse(require('fs').readFileSync('capabilities.json','utf8'));const t=c.product_types['$tmpl'];console.log(JSON.stringify({agents:t.agents,modules:t.modules,gates:t.gates,metrics:t.metrics}))" 2>/dev/null)"
}
EOF
  echo "Created templates/$tmpl/template.json"
done
```

- [ ] **Step 2: 为每个模板创建 README.md 占位文件**

```bash
cd /mnt/e/agentguild
for tmpl in research-report strategy-consulting brand-identity visual-design content-project unity-game unreal-game infra-project ai-ml-project; do
  label=$(node -e "const c=JSON.parse(require('fs').readFileSync('capabilities.json','utf8'));console.log(c.product_types['$tmpl'].label)" 2>/dev/null)
  cat > "templates/$tmpl/README.md" << EOF
# $label 模板

## 这是什么

AgentGraph $label 项目模板。初始化后自动配置 Agent 团队和开发流程。

## 使用

\`\`\`bash
guild init --template $tmpl ./my-project
cd my-project
guild plan "你的需求描述"
\`\`\`

## Agent 团队

运行 \`guild capability $tmpl\` 查看完整 Agent 列表和模块。

## 流程

1. 需求定义 → 产品经理
2. 设计/规划 → 设计师/架构师
3. 开发实现 → 工程师
4. 质量验证 → QA/测试
5. 交付 → 项目负责人
EOF
  echo "Created templates/$tmpl/README.md"
done
```

- [ ] **Step 3: 验证所有模板可通过 guild init 使用**

```bash
cd /mnt/e/agentguild && for tmpl in research-report strategy-consulting brand-identity visual-design content-project unity-game unreal-game infra-project ai-ml-project; do
  tmpdir=$(mktemp -d)
  ./guild init --template "$tmpl" "$tmpdir" && echo "[OK] $tmpl" || echo "[FAIL] $tmpl"
  rm -rf "$tmpdir"
done
```
Expected: 9/9 `[OK]`

- [ ] **Step 4: Commit**

```bash
cd /mnt/e/agentguild
git add templates/research-report templates/strategy-consulting templates/brand-identity templates/visual-design templates/content-project templates/unity-game templates/unreal-game templates/infra-project templates/ai-ml-project
git commit -m "feat: 9个新模板骨架 (研究/策略/品牌/视觉/内容/Unity/Unreal/基础设施/AI)

每个模板包含 template.json 元数据和 README.md
guild init --template <name> 全覆盖18种类型

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 6: 新增 Graph 定义 + 自测扩展 + guild status bug 修复

**Files:**
- Create: `graphs/research-report.yml`, `graphs/unity-game.yml`
- Modify: `scripts/self-test.sh` (新增 classify + plan 测试, 修复 guild status bug)
- Modify: `scripts/nexus.sh` (`cmd_status` 函数 — 修复 JSON 编码 bug)

**Interfaces:**
- Consumes: Task 3 (classify), Task 4 (plan)
- Produces: 2 个新图定义, 扩展的自测（含 classify 准确性测试和 plan 输出验证）, 修复的 guild status

- [ ] **Step 1: 创建 graphs/research-report.yml**

```bash
cat > /mnt/e/agentguild/graphs/research-report.yml << 'EOF'
name: 研究报告 (Graph)
description: 研究报告开发 — 线性流程，无代码回路
nodes:
  define:
    agent: product-manager
    action: deliver
    delivers: [research_brief, scope]

  research:
    agent: ux-researcher
    needs: [define]
    delivers: [user_insights, behavior_data]

  analyze:
    agent: data-analyst
    needs: [research]
    delivers: [data_analysis, findings]

  write:
    agent: tech-writer
    needs: [analyze]
    delivers: [report_draft]

  review:
    agent: product-manager
    action: verify
    needs: [write]

  finalize:
    agent: tech-writer
    needs: [review]
    when: { review: passed }

edges:
  - { from: review, to: write, when: "review.status == failed", label: "修改后重审" }
  - { from: write, to: review, label: "重新审查" }
  - { from: review, to: finalize, when: "review.status == passed", label: "定稿" }
EOF
```

- [ ] **Step 2: 创建 graphs/unity-game.yml**

```bash
cat > /mnt/e/agentguild/graphs/unity-game.yml << 'EOF'
name: Unity游戏开发 (Graph)
description: Unity游戏 — 并行美术+程序+策划，完整测试回路
nodes:
  concept:
    agent: game-designer
    delivers: [gdd, core_loop]

  art:
    agent: technical-artist
    needs: [concept]
    delivers: [art_style, assets, shaders]

  code:
    agent: unity-developer
    needs: [concept]
    delivers: [prototype, gameplay_code]

  ui:
    agent: game-ui-designer
    needs: [concept]
    delivers: [ui_design, ui_prefabs]

  audio:
    agent: game-audio-engineer
    needs: [concept]
    delivers: [audio_assets]

  integration:
    agent: unity-developer
    needs: [art, code, ui, audio]
    delivers: [playable_build]

  qa:
    agent: game-qa-engineer
    action: verify
    needs: [integration]

  fix:
    agent: unity-developer
    needs: [qa]
    when: { qa: failed }

  ship:
    agent: game-producer
    needs: [qa]
    when: { qa: passed }

edges:
  - { from: qa, to: fix, when: "qa.status == failed", label: "QA不通过" }
  - { from: fix, to: qa, label: "修复后重测" }
  - { from: qa, to: ship, when: "qa.status == passed", label: "发布" }
EOF
```

- [ ] **Step 3: 修复 guild status bug**

定位 `scripts/nexus.sh` 中的 `cmd_status` 函数，找出 `guild status` 退出非零的原因。

```bash
cd /mnt/e/agentguild && grep -n "cmd_status" scripts/nexus.sh
```

读取 `cmd_status` 函数体，诊断问题。根据上次会话的诊断，问题可能是 JSON 编码相关的——`cmd_status` 可能在某些边界情况下（如空 handoffs 目录、损坏的 JSON 文件）调用 `node -e` 失败，或在没有 node 时退出非零。

修复思路：在 `cmd_status` 函数中添加防御性错误处理：
1. 如果 handoffs 目录为空，打印 "(no handoffs)" 并 `return 0`
2. 如果 node 不可用但有 handoff 文件，用纯 bash 回退读取
3. 个别文件解析失败不中断整个循环

找到 `cmd_status` 函数并添加以下保护：
```bash
cmd_status() {
  # ... existing code ...
  
  # Guard: empty handoffs dir
  if [[ ! -d "$HANDOFFS_DIR" ]] || [[ -z "$(ls -A "$HANDOFFS_DIR" 2>/dev/null)" ]]; then
    echo "No handoffs found."
    return 0
  fi
  
  # ... rest of function with per-file error tolerance ...
}
```

然后将 `cmd_status` 中的 JSON 读取从 `set -e` 模式改为逐个容错：
```bash
  for hf in "$HANDOFFS_DIR"/*.json; do
    [[ -f "$hf" ]] || continue
    # Each file parse is independent — don't fail the whole command on one bad file
    local info; info=$(node -e "..." 2>/dev/null || echo "")
    [[ -z "$info" ]] && continue
    echo "$info"
  done
```

- [ ] **Step 4: 扩展 self-test.sh — 新增 Test 9: classify 准确性**

在 `scripts/self-test.sh` 的 `test_handoff_integrity` 函数之后（约第 595 行），`# Run all tests` 注释之前，添加：

```bash
# ═══════════════════════════════════════════════════════════════════════
# Test 9: classify accuracy
# ═══════════════════════════════════════════════════════════════════════
test_classify_accuracy() {
  echo ""
  echo "── Test 9: classify accuracy ──"

  local -a cases=(
    "做一个用户调研报告:research-report"
    "写一份GTM策略:strategy-consulting"
    "设计品牌Logo:brand-identity"
    "做活动海报:visual-design"
    "写产品白皮书:content-project"
    "用Unity做3D游戏:unity-game"
    "用Unreal做开放世界:unreal-game"
    "搭建CI/CD流水线:infra-project"
    "训练文本分类模型:ai-ml-project"
    "微信小游戏:wechat-game"
    "后台管理系统:admin-system"
    "公司官网:corp-site"
    "数据看板:dashboard"
    "微信小程序:miniapp"
    "移动App:mobile-app"
    "React网站:web-app"
    "API后端:api-service"
    "营销落地页:landing-page"
  )

  local passed=0 failed=0
  for c in "${cases[@]}"; do
    local input="${c%%:*}" expected="${c##*:}"
    local result; result=$(timeout 10 "$GUILD" classify "$input" 2>/dev/null | grep -oP '\(\K[^)]+' | head -1 || echo "unknown")
    if [[ -z "$result" ]]; then
      # Try parsing the text output differently
      result=$(timeout 10 "$GUILD" classify "$input" 2>/dev/null | head -1 | grep -oP '\b(research-report|strategy-consulting|brand-identity|visual-design|content-project|unity-game|unreal-game|infra-project|ai-ml-project|wechat-game|admin-system|corp-site|dashboard|miniapp|mobile-app|web-app|api-service|landing-page)\b' | head -1 || echo "unknown")
    fi
    if [[ "$result" == "$expected" ]]; then
      passed=$((passed + 1))
    else
      fail "classify '$input': expected $expected, got $result"
      failed=$((failed + 1))
    fi
  done

  if [[ $failed -eq 0 ]]; then
    pass "classify: $passed/$passed types correctly identified"
  else
    echo "  $passed passed, $failed failed"
  fi
}
```

- [ ] **Step 5: 在 self-test.sh 中添加 Test 10: plan 输出验证**

```bash
# ═══════════════════════════════════════════════════════════════════════
# Test 10: plan output structure
# ═══════════════════════════════════════════════════════════════════════
test_plan_output() {
  echo ""
  echo "── Test 10: plan output structure ──"

  local plan_output
  plan_output=$(timeout 30 "$GUILD" plan "做一个测试后台管理系统" 2>/dev/null) || {
    fail "plan: command failed or timed out"
    return
  }

  local checks=0 failures=0

  # Check key sections exist in plan output
  echo "$plan_output" | grep -qi '团队' && checks=$((checks + 1)) || failures=$((failures + 1))
  echo "$plan_output" | grep -qi '门禁' && checks=$((checks + 1)) || failures=$((failures + 1))
  echo "$plan_output" | grep -qi '风险' && checks=$((checks + 1)) || failures=$((failures + 1))
  echo "$plan_output" | grep -qi 'guild init' && checks=$((checks + 1)) || failures=$((failures + 1))

  if [[ $failures -eq 0 ]]; then
    pass "plan: output contains team, gates, risks, and next_step ($checks sections verified)"
  else
    fail "plan: output missing $failures/4 expected sections"
  fi
}
```

- [ ] **Step 6: 在 self-test.sh 的 run-all 部分注册新测试**

在 `test_handoff_integrity || true` 之后添加：
```bash
test_classify_accuracy || true
test_plan_output || true
```

- [ ] **Step 7: 运行完整自测**

```bash
cd /mnt/e/agentguild && bash scripts/self-test.sh
```
Expected: 全部通过（包括 guild status）

- [ ] **Step 8: Commit**

```bash
cd /mnt/e/agentguild
git add graphs/research-report.yml graphs/unity-game.yml scripts/self-test.sh scripts/nexus.sh
git commit -m "feat: 新图定义 + 自测扩展 + guild status 修复

graphs: research-report.yml, unity-game.yml
self-test: +classify准确性(18用例) +plan结构验证
fix: guild status 空目录/损坏JSON容错

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 7: 文档更新 + ai-manifest 同步

**Files:**
- Modify: `ai-manifest.json` (新增 classify/plan 的 AI 可发现定义)
- Modify: `README_zh-CN.md` (更新命令列表)
- Modify: `scripts/nexus.sh:376-405` (更新帮助文本一行)

**Interfaces:**
- Consumes: Task 3, 4 的新命令
- Produces: 更新的文档和 AI manifest

- [ ] **Step 1: 更新 ai-manifest.json 添加 classify 命令定义**

在 `ai-manifest.json` 的 `"commands"` 对象中，`"capabilities"` 之后添加：

```json
    "classify": {
      "description": "Classify a natural language task into a product type with confidence score",
      "usage": "guild classify [--json] '<task description>'",
      "input": {
        "task": "string (natural language)"
      },
      "output_json": {
        "type": "string",
        "label": "string",
        "confidence": "number (0-1)",
        "alternatives": "array",
        "template": "string",
        "gates": "string"
      },
      "example": "guild classify --json '做一个供应商后台管理系统'"
    }
```

并更新 `"plan"` 命令定义（已存在但需更新 description）：

```json
    "plan": {
      "description": "Full execution plan: classify → team matching → graph selection → milestones → risks",
      "usage": "guild plan [--json] '<task description>'",
      "input": {
        "task": "string (natural language)"
      },
      "output_json": {
        "summary": "string",
        "product_type": "string",
        "label": "string",
        "confidence": "number",
        "team": { "lead": "string", "members": "array" },
        "flow": { "graph": "string" },
        "gates": "string",
        "risks": "array"
      },
      "example": "guild plan --json '帮我做塔罗小程序'"
    }
```

- [ ] **Step 2: 更新 nexus.sh 帮助文本**

在 `scripts/nexus.sh` 的帮助文本中，确保 `guild classify` 和 `guild plan` 的描述准确：

```bash
  echo "  guild classify  — 自然语言 → 产品类型 + 置信度 (18种类型)"
  echo "  guild plan     — 生成完整执行计划 (类型+团队+流程+里程碑+风险)"
```

- [ ] **Step 3: 运行 ai-manifest 验证**

```bash
cd /mnt/e/agentguild && node -e "JSON.parse(require('fs').readFileSync('ai-manifest.json','utf8')); console.log('ai-manifest.json: OK')"
```
Expected: `ai-manifest.json: OK`

- [ ] **Step 4: 最终自测确认**

```bash
cd /mnt/e/agentguild && bash scripts/self-test.sh
```
Expected: 全部通过（新增 Test 9 和 Test 10 也通过）

- [ ] **Step 5: Commit**

```bash
cd /mnt/e/agentguild
git add ai-manifest.json README_zh-CN.md scripts/nexus.sh
git commit -m "docs: ai-manifest + 帮助文本同步 v0.3 新命令

ai-manifest: +classify 命令定义, 更新 plan 输出schema
nexus.sh: 帮助文本更新为18种类型

Co-Authored-By: Claude <noreply@anthropic.com>"
```
