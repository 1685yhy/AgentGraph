#!/usr/bin/env bash
# ═══════ Research & Ideation Engine ═══════
# AgentGraph 第一步 — 调研+创意。缺了这一步, 系统只会产出消消乐克隆。
# guild research "<topic>" → 市场调研报告
# guild ideate "<problem>" → 创意概念生成+验证

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/lib.sh"

# ── Research Templates ───────────────────────────────────────────────
# Each product type has a research checklist

RESEARCH_TEMPLATES="$REPO_ROOT/templates/research"

# ── Research Command ──────────────────────────────────────────────────
cmd_research() {
  local topic="${*:-}"
  [[ -z "$topic" ]] && { err "Usage: guild research '<topic/domain>'"; return 1; }

  cat << REPORT
╔══════════════════════════════════════════╗
║  AgentGraph Research — 市场调研          ║
║  Topic: ${topic}
╚══════════════════════════════════════════╝

## 1. 市场趋势

📋 调研清单:
  □ 该领域近期(6个月)的搜索趋势 (百度指数/微信指数/抖音热度)
  □ 社交媒体讨论热度 (小红书/抖音话题播放量)
  □ 线下相关活动/商品热度 (淘宝/拼多多搜索量)
  □ 是否有新兴的消费趋势可以线上化?

## 2. 竞品分析

📋 调研清单:
  □ 微信小游戏/抖音小游戏中有哪些同类产品?
  □ 它们的DAU/留存/变现数据如何?
  □ 用户评价: 最喜欢什么? 最讨厌什么?
  □ 竞品的差异化空间在哪里?

## 3. 用户洞察

📋 调研清单:
  □ 目标用户画像: 年龄/性别/使用场景/碎片时间
  □ 核心心理需求: 炫耀?解压?杀时间?社交?
  □ 分享动机: 为什么用户会分享这个?
  □ 付费意愿: 为什么用户愿意看广告/付费?

## 4. 机会判断

📋 调研清单:
  □ 市场是否已被过度开发? (消消乐=过度开发 ❌)
  □ 是否有线下热点可以线上化? (拼豆=+500% ✅)
  □ 是否有App玩法可以轻量化?
  □ 社交裂变潜力如何?

## 5. 风险评估

📋 调研清单:
  □ 玩法是否容易复制? (护城河在哪)
  □ 是否依赖外部平台API? (微信/抖音政策风险)
  □ 内容审查风险? (敏感题材)

══════════════════════════════════════════
💡 下一步: guild ideate "<从这个调研中提炼的创意方向>"
REPORT
}

# ── Ideation Command ──────────────────────────────────────────────────
cmd_ideate() {
  local problem="${*:-}"
  [[ -z "$problem" ]] && { err "Usage: guild ideate '<problem/opportunity>'"; return 1; }

  cat << IDEATE
╔══════════════════════════════════════════╗
║  AgentGraph Ideation — 创意生成          ║
║  Problem: ${problem}
╚══════════════════════════════════════════╝

## 创意概念生成

基于调研，生成5-10个差异化概念:

### 评估维度
| 维度 | 权重 | 说明 |
|------|------|------|
| 新颖度 | 30% | 市场上是否有同类? |
| 可行性 | 20% | 技术/时间/资源能否实现? |
| 病毒性 | 25% | 用户会主动分享吗? |
| 变现力 | 25% | 广告/内购的天然场景? |

### 概念模板
\`\`\`
概念 #N: [一句话描述]
  差异化: [和现有产品有什么不同]
  核心循环: [用户30秒内的体验]
  病毒钩子: [为什么用户会分享]
  变现点: [广告/内购的自然时机]
  风险: [最大的失败可能]
  评分: 新颖_X 可行_X 病毒_X 变现_X = X.X/10
\`\`\`

## 反克隆检查
⚠️ 如果创意和以下品类相似，需要重新思考:
  ❌ 消消乐 (三消/堆叠/连线)
  ❌ 合成 (2048/大西瓜)
  ❌ 跑酷 (上下左右躲)
  ❌ 排序 (颜色/水/球)
  ❌ 找茬/解谜 (已过度开发)
  ✅ 线下热点线上化
  ✅ App玩法轻量化
  ✅ 新社交机制

## 概念验证问题
1. 你能用一句话让朋友立刻想玩吗? (电梯测试)
2. 30秒内用户能体验到核心乐趣吗? (上手测试)
3. 用户失败后会立刻点"再来一次"吗? (粘性测试)
4. 用户会主动截图/分享吗? (传播测试)
5. 广告出现时用户会觉得自然吗? (变现测试)

══════════════════════════════════════════
💡 下一步: 选定概念后 → guild plan "<选定的概念描述>"
IDEATE
}

# ── Concept Validation ────────────────────────────────────────────────
cmd_validate_concept() {
  local concept="${*:-}"
  [[ -z "$concept" ]] && { err "Usage: guild validate '<concept description>'"; return 1; }

  # Anti-clone check
  local clone_score=0
  for kw in 消消乐 消除 三消 合成 合并 排序 跑酷 连连看 找茬; do
    echo "$concept" | grep -qi "$kw" && clone_score=$((clone_score + 1))
  done

  cat << VALIDATE
╔══════════════════════════════════════════╗
║  Concept Validation — 概念验证           ║
╚══════════════════════════════════════════╝

概念: ${concept}

VALIDATE

  if [[ $clone_score -ge 2 ]]; then
    cat << WARN
⚠️  **克隆风险: HIGH (${clone_score}/10)**
   这个概念和市场上已过度开发的品类高度相似!
   建议: 运行 guild research + guild ideate 寻找差异化方向。
   如果坚持要做: 必须明确说明差异化在哪里。
WARN
  elif [[ $clone_score -ge 1 ]]; then
    cat << WARN
⚡ **克隆风险: MEDIUM (${clone_score}/10)**
   有一定相似度, 需要有明确的差异化点。
   建议: 明确回答"和现有XX有什么不同?"
WARN
  else
    cat << PASS
✅ **克隆风险: LOW**
   概念通过反克隆检查。进入下一步。
PASS
  fi

  cat << NEXT

📋 概念检查清单:
  □ 电梯测试: 一句话能让朋友想玩?
  □ 上手测试: 30秒内体验核心乐趣?
  □ 粘性测试: 失败后立刻点"再来一次"?
  □ 传播测试: 用户会主动截图/分享?
  □ 变现测试: 广告时机是否自然?

══════════════════════════════════════════
💡 下一步: guild plan "<concept>"
NEXT
}

# ── Full Pre-Flight (research + ideate + validate → plan) ───────────
cmd_preflight() {
  local goal="${*:-}"
  [[ -z "$goal" ]] && { err "Usage: guild preflight '<product goal>'"; return 1; }

  echo "╔══════════════════════════════════════════╗"
  echo "║  Pre-Flight Check — 完整前置验证        ║"
  echo "╚══════════════════════════════════════════╝"
  echo ""
  echo "  Step 1/4: Research"
  echo "  Step 2/4: Ideate"
  echo "  Step 3/4: Validate"
  echo "  Step 4/4: Plan"
  echo ""

  cmd_research "$goal"
  echo ""
  cmd_ideate "$goal"
  echo ""
  cmd_validate_concept "$goal"
}
