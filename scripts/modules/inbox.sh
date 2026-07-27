#!/usr/bin/env bash
# Module: inbox.sh — cmd_inbox, cmd_read, cmd_resolve
# Source guard: only loadable via guild
[[ -n "${_AG_MODULE_SOURCING:-}" ]] || { echo "This module must be loaded via guild, not run directly" >&2; exit 1; }

# ── cmd_inbox ──────────────────────────────────────────────────────

cmd_inbox() {
  local agent="" unread_only=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --agent) agent="$2"; shift 2;;
      --unread) unread_only=true; shift;;
      *) shift;;
    esac
  done

  if [[ -n "$agent" ]]; then
    local agent_slug; agent_slug="$(resolve_agent "$agent")"
    local inbox_dir="$REPO_ROOT/context/inbox/${agent_slug}"
    if [[ ! -d "$inbox_dir" ]] || [[ -z "$(ls "$inbox_dir"/*.json 2>/dev/null)" ]]; then
      echo "  ${agent_slug} 收件箱为空"
      return 0
    fi

    local unread; unread=$(count_unread "$agent_slug")
    local total; total=$(ls "$inbox_dir"/*.json 2>/dev/null | wc -l)
    echo "=== ${agent_slug} 的收件箱 ==="
    echo "  未读: $unread / 总计: $total"
    echo ""

    for f in "$inbox_dir"/*.json; do
      [[ -f "$f" ]] || continue
      local is_read; is_read=$(grep -o '"read": [a-z]*' "$f" | cut -d' ' -f2)
      $unread_only && [[ "$is_read" == "true" ]] && continue

      local itype; itype=$(grep -o '"type": "[^"]*"' "$f" | head -1 | cut -d'"' -f4)
      local ifrom; ifrom=$(grep -o '"from": "[^"]*"' "$f" | head -1 | cut -d'"' -f4)
      local isummary; isummary=$(grep -o '"summary": "[^"]*"' "$f" | head -1 | cut -d'"' -f4)
      local iaction; iaction=$(grep -o '"action": "[^"]*"' "$f" | head -1 | cut -d'"' -f4)

      local icon="📌"
      case "$itype" in
        handoff_incoming) icon="📨";;
        conflict_active) icon="⚠️";;
        decision_relevant) icon="📋";;
      esac

      local read_mark="🔵"
      [[ "$is_read" == "true" ]] && read_mark="  "

      echo "$read_mark $icon [$ifrom] $isummary"
      echo "      → $iaction"
      echo ""
    done
  else
    echo "=== 所有收件箱 ==="
    local any=false
    for d in "$REPO_ROOT/context/inbox"/*/; do
      [[ -d "$d" ]] || continue
      local a; a=$(basename "$d")
      local unread; unread=$(count_unread "$a")
      if [[ "$unread" -gt 0 ]]; then
        echo "  $a: $unread 未读"
        any=true
      fi
    done
    $any || echo "  所有收件箱为空"
  fi
}

# ── cmd_read ──────────────────────────────────────────────────────

cmd_read() {
  local agent="" all=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --agent) agent="$2"; shift 2;;
      --all) all=true; shift;;
      *) shift;;
    esac
  done

  [[ -n "$agent" ]] || die "--agent is required"
  local agent_slug; agent_slug="$(resolve_agent "$agent")"
  local inbox_dir="$REPO_ROOT/context/inbox/${agent_slug}"
  [[ -d "$inbox_dir" ]] || { echo "  收件箱为空"; return 0; }

  mark_all_read "$agent_slug"
  ok "已标记 ${agent_slug} 的所有消息为已读"
}

# ── cmd_resolve ────────────────────────────────────────────────────

cmd_resolve() {
  local topic=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --topic) topic="$2"; shift 2;;
      *) shift;;
    esac
  done

  [[ -n "$topic" ]] || die "--topic is required"

  echo "=== 冲突解决: $topic ==="

  # Find conflicting decisions
  local parties=""
  for f in "$REPO_ROOT/context/decisions"/*.json; do
    [[ -f "$f" ]] || continue
    local t; t=$(grep -o '"topic": "[^"]*"' "$f" | head -1 | cut -d'"' -f4)
    [[ "$t" == "$topic" ]] || continue
    local a; a=$(grep -o '"agent": "[^"]*"' "$f" | head -1 | cut -d'"' -f4)
    local s; s=$(grep -o '"summary": "[^"]*"' "$f" | head -1 | cut -d'"' -f4)
    echo "  $a: $s"
    parties="$parties $a"
  done

  if [[ -z "$parties" ]]; then
    echo "  未找到与主题“$topic”相关的决策"
    return 0
  fi

  echo ""
  echo "  决策权重分析:"

  # Determine authority based on topic keywords
  local authority=""
  case "$topic" in
    *api*|*API*|*schema*|*database*|*db*|*model*|*endpoint*|*auth*|*认证*|*api*)
      # api-design, backend related
      if echo "$parties" | grep -q "backend-architect"; then
        authority="backend-architect"
      fi
      ;;
    *ui*|*UX*|*design*|*component*|*style*|*layout*|*interface*|*ui*|*设计*)
      if echo "$parties" | grep -q "ui-designer"; then
        authority="ui-designer"
      elif echo "$parties" | grep -q "creative-director"; then
        authority="creative-director"
      fi
      ;;
    *game*|*mechanic*|*gameplay*|*循环*|*game*)
      if echo "$parties" | grep -q "game-designer"; then
        authority="game-designer"
      fi
      ;;
    *scope*|*feature*|*priority*|*prd*|*范围*|*功能*)
      if echo "$parties" | grep -q "product-manager"; then
        authority="product-manager"
      fi
      ;;
    *security*|*auth*|*permission*|*安全*)
      if echo "$parties" | grep -q "security-engineer"; then
        authority="security-engineer"
      fi
      ;;
  esac

  if [[ -n "$authority" ]]; then
    echo "  → 此领域拥有最终决策权的 Agent: $authority"
    echo "  建议: 由 $authority 做出最终裁决"
    echo "  处理方式:"
    echo "    1. $authority 运行 guild decide 记录最终决策"
    echo "    2. 受影响方确认并更新自己的工作"
  else
    echo "  警告: 无法自动确定此领域的决策权威"
    echo "  建议: 由 PM 协调决策或运行 guild decide --authority <agent> 人工指定"
  fi

  echo ""
  echo "  受影响方应被通知最终决定"
}
