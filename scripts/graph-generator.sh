#!/usr/bin/env bash
#
# graph-generator.sh — Task → Graph 自动映射引擎
#
# 输入: 自然语言任务描述
# 输出: 可执行的 Graph YAML (stdout)
#
# 核心逻辑:
#   任务 → 分析类型+特征 → 匹配contracts → 选Agent → 建依赖图 → 生成Graph
#
# Usage:
#   bash scripts/graph-generator.sh "做一个供应商注册登录页面"
#   guild plan "做一个供应商注册登录页面"
#   guild build "做一个供应商注册登录页面"  # plan + execute

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

CONTRACTS="$REPO_ROOT/contracts/guild-contracts.yml"
CONFIG="$REPO_ROOT/guild.config.json"

# ── Product type definitions ─────────────────────────────────────────
# Each type maps to: agent chain + default gates + keywords

# Product type → core agents (in dependency order)
declare -A TYPE_AGENTS

# web-app: 网页应用（后台/门户/注册登录/看板）
TYPE_AGENTS["web-app"]="product-manager ui-designer frontend-engineer backend-architect database-specialist qa-engineer security-engineer"

# landing-page: 落地页/官网
TYPE_AGENTS["landing-page"]="product-manager ui-designer frontend-engineer qa-engineer"

# api: 后端API/服务
TYPE_AGENTS["api"]="product-manager backend-architect database-specialist qa-engineer security-engineer"

# miniapp: 微信小程序
TYPE_AGENTS["miniapp"]="product-manager ui-designer frontend-engineer backend-architect qa-engineer"

# mobile: 移动应用
TYPE_AGENTS["mobile"]="product-manager ui-designer mobile-developer backend-architect qa-engineer"

# full-stack: 全栈应用
TYPE_AGENTS["full-stack"]="product-manager ui-designer frontend-engineer backend-architect database-specialist mobile-developer qa-engineer security-engineer"

# dashboard: 数据看板/报表
TYPE_AGENTS["dashboard"]="product-manager ui-designer frontend-engineer backend-architect database-specialist data-analyst qa-engineer"

# game: 游戏
TYPE_AGENTS["game"]="game-designer game-programmer technical-artist game-ui-designer game-audio-engineer game-qa-engineer game-producer"

# doc: 文档/方案
TYPE_AGENTS["doc"]="product-manager tech-writer creative-director"

# marketing: 营销/增长
TYPE_AGENTS["marketing"]="product-manager growth-hacker content-creator data-analyst"

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

# wechat-game: 微信/抖音小游戏（复用 game 链）
TYPE_AGENTS["wechat-game"]="game-designer game-programmer technical-artist game-ui-designer game-audio-engineer game-qa-engineer game-producer"

# api-service: 后端API/服务（原 api）
TYPE_AGENTS["api-service"]="product-manager backend-architect database-specialist qa-engineer security-engineer"

# mobile-app: 移动应用（原 mobile）
TYPE_AGENTS["mobile-app"]="product-manager ui-designer mobile-developer backend-architect qa-engineer"

# admin-system: 后台管理系统
TYPE_AGENTS["admin-system"]="product-manager ui-designer frontend-engineer backend-architect database-specialist qa-engineer security-engineer"

# corp-site: 企业官网（复用 landing-page 链）
TYPE_AGENTS["corp-site"]="product-manager ui-designer frontend-engineer qa-engineer"

# ── Keyword → product type mapping ────────────────────────────────────
# ── AI-powered task analysis ──────────────────────────────────────────
# In Claude Code / OpenClaw: the host LLM (Claude) is the intelligence.
# The script provides execution — keyword fallback for standalone use.
# For LLM-driven analysis, pipe JSON via --analysis flag or stdin.

ai_analyze_task() {
  local task="$1"

  # Fast path: keyword matching (works everywhere, no deps)
  local type; type=$(classify_task_fallback "$task")
  local features; features=$(detect_features "$task")
  echo "{\"type\":\"$type\",\"agents\":[],\"features\":\"$features\",\"gates\":\"$(select_gates "$type")\",\"reasoning\":\"关键词匹配 — 运行在 ${CLAUDE_CODE:+Claude Code}${OPENCLAW:+OpenClaw}${CLAUDE_CODE:-${OPENCLAW:-(无宿主)}} 中\"}"
}

classify_task_fallback() {
  local task="$1"
  local best="" best_score=0
  for pair in \
    "research-report:调研 用户研究 竞品 访谈 可用性测试 焦点小组 问卷 市场研究 行业分析" \
    "strategy-consulting:策略 GTM 商业模式 商业计划 产品战略 定价策略 路线图 进入市场 商业策划" \
    "brand-identity:品牌 VI Logo 视觉识别 品牌手册 品牌指南 品牌设计 标志" \
    "visual-design:海报 印刷 物料 宣传册 展板 包装 视觉设计 平面设计" \
    "content-project:写文档 文案 白皮书 技术文档 用户手册 博客 内容 写作 编辑" \
    "unity-game:Unity unity C# 3D游戏 2D游戏 unity3d" \
    "unreal-game:Unreal UE5 UE4 蓝图 虚幻引擎 虚幻" \
    "infra-project:Docker K8s Kubernetes CI/CD DevOps 运维 部署 云架构 Terraform" \
    "ai-ml-project:机器学习 深度学习 模型训练 训练 分类 LLM RAG 大模型 NLP 神经网络 AI模型" \
    "wechat-game:小游戏 微信小游戏 抖音小游戏 H5游戏 休闲游戏 消除 合成 三消" \
    "web-app:页面 网站 管理 注册 登录 表单 报表 供应商 门户 控制台 账号" \
    "landing-page:落地页 landing 主页 首页 品牌页" \
    "api-service:API 接口 后端服务 restful graphql 微服务" \
    "miniapp:小程序 微信 抖音小程序 小程序开发" \
    "mobile-app:APP 安卓 iOS 移动端 手机应用 Flutter React Native" \
    "dashboard:看板 报表 图表 数据可视化 统计 监控 大屏 BI" \
    "admin-system:后台 后台管理 管理系统 CRUD 权限管理 审批流 后台系统" \
    "corp-site:官网 企业官网 公司网站 企业站 品牌官网"; do
    local type="${pair%%:*}"
    local kws="${pair#*:}"
    local score=0
    for kw in $kws; do echo "$task" | grep -qi "$kw" && score=$((score+1)); done
    [[ $score -gt $best_score ]] && { best_score=$score; best="$type"; }
  done
  echo "${best:-web-app}"
}

classify_task() {
  local analysis
  analysis=$(ai_analyze_task "$1" 2>/dev/null)
  local type; type=$(echo "$analysis" | node -e "try{console.log(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).type||'web-app')}catch(e){console.log('web-app')}" 2>/dev/null)
  echo "${type:-web-app}"
}

# ── Feature detection ─────────────────────────────────────────────────
# Detect if task needs specific specialist agents
detect_features() {
  local task="$1"
  local features=""

  # Auth/Security
  echo "$task" | grep -qi '登录\|注册\|权限\|密码\|认证\|授权\|oauth\|sso' && features="$features auth"

  # Payment
  echo "$task" | grep -qi '支付\|付款\|微信支付\|支付宝\|订单\|交易\|充值' && features="$features payment"

  # Real-time
  echo "$task" | grep -qi '实时\|即时\|推送\|websocket\|消息' && features="$features realtime"

  # File upload
  echo "$task" | grep -qi '上传\|文件\|图片\|附件\|导出\|导入' && features="$features upload"

  # Search
  echo "$task" | grep -qi '搜索\|查询\|筛选\|检索\|全文' && features="$features search"

  # Notification
  echo "$task" | grep -qi '通知\|提醒\|消息推送\|邮件\|短信' && features="$features notify"

  # Internationalization
  echo "$task" | grep -qi '多语言\|国际化\|i18n\|英文' && features="$features i18n"

  # Analytics
  echo "$task" | grep -qi '分析\|统计\|数据\|指标\|报表\|趋势\|洞察' && features="$features analytics"

  # Content-heavy
  echo "$task" | grep -qi '内容\|文章\|博客\|文档\|知识库\|帮助中心' && features="$features content"

  echo "$features"
}

# ── Agent selection ───────────────────────────────────────────────────
# Given product type + features, return ordered list of agent slugs
select_agents() {
  local type="$1" features="$2"
  local agents="${TYPE_AGENTS[$type]}"

  # Add specialist agents based on features
  for feat in $features; do
    case "$feat" in
      auth)    [[ "$agents" != *security-engineer* ]] && agents="$agents security-engineer";;
      payment) [[ "$agents" != *financial-analyst* ]] && agents="$agents financial-analyst";;
      analytics) [[ "$agents" != *data-analyst* ]] && agents="$agents data-analyst";;
      content) [[ "$agents" != *tech-writer* ]] && agents="$agents tech-writer";;
      i18n)    [[ "$agents" != *tech-writer* ]] && agents="$agents tech-writer";;
      notify)  [[ "$agents" != *devops-engineer* ]] && agents="$agents devops-engineer";;
      realtime) [[ "$agents" != *devops-engineer* ]] && agents="$agents devops-engineer";;
    esac
  done

  # Always add QA if not present (for non-doc types)
  [[ "$type" != "doc" && "$type" != "marketing" && "$agents" != *qa-engineer* ]] && agents="$agents qa-engineer"

  # Add accessibility-auditor for UI types
  case "$type" in
    web-app|landing-page|miniapp|dashboard|mobile-app|full-stack|admin-system|corp-site|brand-identity|visual-design)
      [[ "$agents" != *accessibility-auditor* ]] && agents="$agents accessibility-auditor";;
  esac

  # Add project-manager for multi-agent projects
  local agent_count; agent_count=$(echo "$agents" | wc -w)
  [[ $agent_count -ge 5 ]] && [[ "$agents" != *project-manager* ]] && agents="project-manager $agents"

  echo "$agents"
}

# ── Dependency resolver ──────────────────────────────────────────────
# Build dependency map from contracts
# Returns: agent_slug|depends_on_agent_slug pairs
resolve_dependencies() {
  local agents="$1"
  local deps=""

  for agent in $agents; do
    # Extract requires.from from contracts
    local reqs
    reqs=$(awk -v slug="$agent" '
      $0 ~ "^  " slug ":" { in_agent=1; next }
      in_agent && /^  [a-z]/ && $0 !~ "^  " slug ":" { exit }
      in_agent && /^    requires:/ { in_req=1; next }
      in_agent && /^    delivers:/ { in_req=0; next }
      in_req && /^      - from:/ {
        sub(/.*from: "/, ""); sub(/".*/, "");
        print $0
      }
    ' "$CONTRACTS" 2>/dev/null)

    # Map display names to slugs
    for req_name in $reqs; do
      local req_slug; req_slug=$(resolve_by_display_name "$req_name")
      [[ -z "$req_slug" ]] && req_slug=$(resolve_agent "$req_name")
      [[ -n "$req_slug" ]] && deps="$deps\n${agent}|${req_slug}"
    done
  done

  echo -e "$deps" | grep -v '^$' | sort -u
}

# ── Graph assembler ───────────────────────────────────────────────────
# Generate complete graph YAML from agents + dependencies
assemble_graph() {
  local task="$1" type="$2" agents="$3" deps="$4"

  local name; name=$(echo "$task" | cut -c1-40 | tr -cd 'a-zA-Z0-9[:space:]' | tr '[:space:]' '-' | tr '[:upper:]' '[:lower:]' | sed 's/--*/-/g; s/^-//; s/-$//')
  name="task-${name:0:30}"
  [[ -z "$name" ]] && name="auto-generated"

  cat << YAML
# Auto-generated graph: $(date -Iseconds)
# Task: $task
# Type: $type
# Agents: $agents
name: $name
description: $task
type: $type
nodes:
YAML

  # Assign phases based on dependency order
  # Phase 0: product-manager, project-manager
  # Phase 1: ui-designer, backend-architect, database-specialist
  # Phase 2: frontend-engineer, mobile-developer
  # Phase 3: qa-engineer, security-engineer, accessibility-auditor
  # Phase 4: game-producer, creative-director

  local phase_order="product-manager project-manager ux-researcher data-analyst game-designer ui-designer interaction-designer backend-architect database-specialist tech-writer financial-analyst frontend-engineer mobile-developer unity-developer unreal-developer game-programmer technical-artist game-ui-designer game-audio-engineer monetization-designer devops-engineer growth-hacker content-creator seo-specialist social-media-strategist qa-engineer performance-tester accessibility-auditor security-engineer game-qa-engineer game-producer creative-director brand-guardian code-reviewer deal-strategist sales-engineer customer-support"

  # Assign each agent to a phase (order index)
  for agent in $agents; do
    local needs=""
    # Find dependencies for this agent
    while IFS='|' read -r ag dep; do
      [[ "$ag" == "$agent" ]] && [[ "$agents" == *"$dep"* ]] && needs="$needs $dep"
    done <<< "$deps"

    # Build clean YAML needs list
    local needs_yaml=""
    local unique_needs; unique_needs=$(echo "$needs" | tr ' ' '\n' | grep -v '^$' | sort -u)
    if [[ -n "$unique_needs" ]]; then
      while IFS= read -r nd; do
        [[ -z "$nd" ]] && continue
        needs_yaml="${needs_yaml}
      - $nd"
      done <<< "$unique_needs"
    fi

    # Determine action: QA/test agents use "verify"
    local action="deliver"
    case "$agent" in
      qa-engineer|performance-tester|accessibility-auditor|security-engineer|game-qa-engineer|code-reviewer|creative-director|game-producer)
        action="verify";;
    esac

    # Deliverables from contracts
    local delivers
    delivers=$(awk -v slug="$agent" '
      $0 ~ "^  " slug ":" { in_agent=1; next }
      in_agent && /^  [a-z]/ && $0 !~ "^  " slug ":" { exit }
      in_agent && /^    delivers:/ { in_del=1; next }
      in_agent && /^    requires:/ { in_del=0; next }
      in_del && /^      - name:/ {
        sub(/.*name: "/, ""); sub(/".*/, "");
        gsub(/[{}"]/, "");  # strip YAML special chars
        print $0
      }
    ' "$CONTRACTS" 2>/dev/null | head -3 | sed 's/^/        - /')

    local node_name; node_name=$(echo "$agent" | tr '-' '_')
    # Build the complete node YAML including deliverables
    local node_block="  $node_name:
    agent: $agent
    action: $action"
    if [[ -z "$needs_yaml" ]]; then
      node_block="${node_block}
    needs: []"
    else
      node_block="${node_block}
    needs:$needs_yaml"
    fi
    node_block="${node_block}
    delivers:"
    # Add deliverable items
    while IFS= read -r dline; do
      [[ -z "$dline" ]] && continue
      node_block="${node_block}
$dline"
    done <<< "$delivers"

    echo "$node_block"
    echo ""
  done

  # Generate edges: QA feedback loops
  cat << YAML
edges:
YAML

  # For each verify agent, add feedback loop to the agent before it
  for agent in $agents; do
    case "$agent" in
      qa-engineer|performance-tester|game-qa-engineer)
        # Find the implementor agent before this one
        local prev=""
        for a in $agents; do
          [[ "$a" == "$agent" ]] && break
          case "$a" in
            frontend-engineer|backend-architect|mobile-developer|game-programmer|unity-developer|unreal-developer)
              prev="$a";;
          esac
        done
        if [[ -n "$prev" ]]; then
          cat << YAML
  - { from: $agent, to: $prev, when: "$agent.status == failed", label: "修复后重测" }
  - { from: $prev, to: $agent, label: "重新验证" }
YAML
        fi
        ;;
    esac
  done

  # Add completion edge
  local last_agent; last_agent=$(echo "$agents" | awk '{print $NF}')
  cat << YAML
  - { from: $last_agent, to: complete, when: "$last_agent.status == passed", label: "完成" }
YAML
}

# ── Gate selection ─────────────────────────────────────────────────────
select_gates() {
  local type="$1"
  local gates="1 2"  # completeness + syntax always

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

  echo "$gates"
}

# ── Main: generate graph from task ─────────────────────────────────────
generate_graph() {
  local task="$1"
  local ai_analysis="${AG_AI_ANALYSIS:-}"  # Accept pre-analyzed JSON from host LLM

  # Parse --analysis flag
  if [[ "$1" == "--analysis" ]]; then
    ai_analysis="$2"
    shift 2
    task="$*"
  fi

  # JSON mode: AI frameworks consume structured output
  local json_mode=false
  if [[ "${AG_AI_MODE:-}" == "1" ]] || [[ "${1:-}" == "--json" ]] || [[ "${2:-}" == "--json" ]]; then
    json_mode=true
  fi
  # Drop a leading --json flag so the task description is parsed correctly
  if [[ "${1:-}" == "--json" ]]; then
    shift
    task="$*"
  fi

  [[ -z "$task" ]] && { err "Usage: guild plan \"<task description>\""; return 1; }

  echo "╔══════════════════════════════════════════╗"
  echo "║  AgentGraph — 智能 Task → Graph 映射    ║"
  echo "╚══════════════════════════════════════════╝"
  echo ""

  # Step 1: Task analysis — use host LLM analysis if provided, else keyword
  local analysis type agents features gates reasoning

  if [[ -n "$ai_analysis" ]]; then
    # Use the host LLM's analysis (from Claude Code / orchestrator)
    analysis="$ai_analysis"
    echo "  🧠 分析模式: 宿主 LLM (Claude Code)"
  else
    # Keyword-based fallback
    analysis=$(ai_analyze_task "$task" 2>/dev/null)
    echo "  🧠 分析模式: 关键词匹配"
  fi

  type=$(echo "$analysis" | node -e "try{console.log(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).type||'web-app')}catch(e){console.log('web-app')}" 2>/dev/null)
  agents=$(echo "$analysis" | node -e "try{console.log((JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).agents||[]).join(' '))}catch(e){console.log('')}" 2>/dev/null)
  features=$(echo "$analysis" | node -e "try{console.log(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).features||'')}catch(e){console.log('')}" 2>/dev/null)
  gates=$(echo "$analysis" | node -e "try{console.log(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).gates||'1 2')}catch(e){console.log('1 2')}" 2>/dev/null)
  reasoning=$(echo "$analysis" | node -e "try{console.log(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).reasoning||'')}catch(e){console.log('')}" 2>/dev/null)

  # Fallback: if analysis returned no agents, use keyword-based selection
  if [[ -z "$agents" || "$agents" == " " ]]; then
    type=$(classify_task_fallback "$task")
    features=$(detect_features "$task")
    agents=$(select_agents "$type" "$features")
    gates=$(select_gates "$type")
    reasoning="关键词匹配"
  fi

  local type_label="${type:-web-app}"
  echo "  📋 任务类型: $type_label"
  echo "  🔍 检测特征: ${features:-无}"
  echo "  👥 Agent 选择:"
  for a in $agents; do echo "      - $a"; done

  # Step 2: Resolve dependencies from contracts
  local deps; deps=$(resolve_dependencies "$agents")

  echo "  🚪 Gate 选择: $gates"

  # ── Build structured execution plan ──────────────────────────────
  local agent_count; agent_count=$(echo "$agents" | wc -w)
  local confidence="1.0"
  local cscore; cscore=$(classify_score "$task" "$type")
  if [[ $cscore -gt 0 ]]; then
    confidence=$(node -e "console.log(Math.min(1.0, $cscore / 5).toFixed(2))" 2>/dev/null || echo "0.5")
  fi

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
  local risks_json="[]"
  case "$type" in
    miniapp)
      risks_json='["微信审核政策风险 — 避免敏感内容"]'
      echo "      - 微信审核政策风险 — 避免敏感内容";;
    wechat-game|unity-game|unreal-game)
      risks_json='["游戏可玩性风险 — 核心循环需充分测试","性能风险 — 目标设备帧率需达标"]'
      echo "      - 游戏可玩性风险 — 核心循环需充分测试"
      echo "      - 性能风险 — 目标设备帧率需达标";;
    admin-system)
      risks_json='["RBAC权限设计复杂度 — 提前梳理角色矩阵","审批流逻辑 — 需与业务方逐条确认"]'
      echo "      - RBAC权限设计复杂度 — 提前梳理角色矩阵"
      echo "      - 审批流逻辑 — 需与业务方逐条确认";;
    mobile-app)
      risks_json='["应用商店审核 — iOS/Android 各有规范","多设备兼容 — 屏幕尺寸和系统版本覆盖"]'
      echo "      - 应用商店审核 — iOS/Android 各有规范"
      echo "      - 多设备兼容 — 屏幕尺寸和系统版本覆盖";;
    research-report|strategy-consulting)
      risks_json='["数据来源可靠性 — 标注所有数据出处","建议可行性 — 需结合客户实际资源评估"]'
      echo "      - 数据来源可靠性 — 标注所有数据出处"
      echo "      - 建议可行性 — 需结合客户实际资源评估";;
    brand-identity|visual-design)
      risks_json='["品牌调性对齐 — 需提前确认品牌基因","交付格式 — 确认甲方需要的源文件格式"]'
      echo "      - 品牌调性对齐 — 需提前确认品牌基因"
      echo "      - 交付格式 — 确认甲方需要的源文件格式";;
    ai-ml-project)
      risks_json='["数据质量 — GIGO: 垃圾进垃圾出","模型部署成本 — GPU资源预估"]'
      echo "      - 数据质量 — GIGO: 垃圾进垃圾出"
      echo "      - 模型部署成本 — GPU资源预估";;
    infra-project)
      risks_json='["生产环境差异 — dev/staging/prod 一致性","密钥管理 — 敏感信息不能进代码仓库"]'
      echo "      - 生产环境差异 — dev/staging/prod 一致性"
      echo "      - 密钥管理 — 敏感信息不能进代码仓库";;
    *) echo "      - 需求范围蔓延 — 确认MVP边界";;
  esac
  echo ""

  # Next step
  echo "  ▶️  下一步: guild init --template $type ./my-project"

  # JSON output for AI consumption
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

  # Step 6: Assemble graph
  local graph_yaml; graph_yaml=$(assemble_graph "$task" "$type" "$agents" "$deps")

  echo ""
  echo "$graph_yaml"

  # Interactive confirmation
  if [[ "${AG_AI_MODE:-}" != "1" ]]; then
    echo ""
    read -p "  确认启动? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo "  已取消。"
      rm -f /tmp/guild-last-graph.txt
      return 0
    fi
  fi

  # Save to temp file for execution
  local graph_file; graph_file=$(mktemp /tmp/guild-auto-XXXXXX.yml)
  echo "$graph_yaml" > "$graph_file"
  echo ""
  echo "  💾 Graph 已保存: $graph_file"
  echo "  ▶️  运行: guild graph --file $graph_file"

  # Return the file path (for guild build to chain)
  echo "$graph_file" > /tmp/guild-last-graph.txt
}

# build_product — plan + execute in one shot
build_product() {
  local task="$*"
  [[ -z "$task" ]] && { err "Usage: guild build \"<task description>\""; return 1; }

  generate_graph "$task"

  local graph_file; graph_file=$(cat /tmp/guild-last-graph.txt 2>/dev/null)
  [[ -z "$graph_file" || ! -f "$graph_file" ]] && { err "Graph generation failed"; return 1; }

  echo ""
  echo "╔══════════════════════════════════════════╗"
  echo "║  🚀 开始执行 Graph                       ║"
  echo "╚══════════════════════════════════════════╝"

  # Execute via graph engine
  "$REPO_ROOT/guild" graph --file "$graph_file" --yes 2>&1 || {
    err "Graph 执行失败"
    return 1
  }

  echo ""
  ok "✅ Build 完成: $task"
}

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
    ai-ml-project) kws="机器学习 深度学习 模型训练 训练 分类 LLM RAG 大模型 NLP 神经网络";;
    wechat-game) kws="小游戏 微信小游戏 抖音小游戏 H5游戏 休闲游戏 消除 三消";;
    web-app) kws="页面 网站 注册 登录 表单 门户 控制台";;
    landing-page) kws="落地页 landing 主页 首页 品牌页";;
    api-service) kws="API 接口 后端服务 restful graphql 微服务";;
    miniapp) kws="小程序 微信小程序 抖音小程序";;
    mobile-app) kws="APP 安卓 iOS 移动端 手机应用 Flutter React Native";;
    dashboard) kws="看板 报表 图表 数据可视化 统计 监控 大屏 BI";;
    admin-system) kws="供应商 后台 后台管理 管理系统 CRUD 权限管理 审批流 后台系统";;
    corp-site) kws="官网 企业官网 公司网站 企业站 品牌官网";;
  esac
  for kw in $kws; do
    echo "$task" | grep -qi "$kw" && score=$((score + 1))
  done
  echo $score
}

cmd_classify() {
  local task="$1"
  [[ -z "$task" ]] && { err "Usage: guild classify \"<task description>\""; return 1; }

  local best_type="" best_score=0 best_label=""
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
    if [[ "${AG_AI_MODE:-}" == "1" ]] || [[ "${1:-}" == "--json"* ]]; then
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
  if [[ "${AG_AI_MODE:-}" == "1" ]] || [[ "${1:-}" == "--json"* ]]; then
    node -e "console.log(JSON.stringify({type:'$best_type',label:'$label',confidence:$confidence,alternatives:$alternatives,template:'$template',gates:'$gates'},null,2))"
  else
    echo "📋 $label ($best_type)"
    echo "   置信度: $confidence"
    if [[ "$alternatives" != "[]" ]]; then
      echo "   备选: $(echo "$alternatives" | node -e "const a=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));console.log(a.map(x=>x.label).join(', '))" 2>/dev/null)"
    fi
  fi
}

# ── CLI entry ──────────────────────────────────────────────────────────
if [[ "${1:-}" == "--generate" ]]; then
  shift
  generate_graph "$*"
fi
