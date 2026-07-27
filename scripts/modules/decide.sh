#!/usr/bin/env bash
# Module: decide.sh — cmd_decide
# Source guard: only loadable via guild
[[ -n "${_AG_MODULE_SOURCING:-}" ]] || { echo "This module must be loaded via guild, not run directly" >&2; exit 1; }

# ── cmd_decide ────────────────────────────────────────────────────────

cmd_decide() {
  local agent="" type="" topic="" summary="" rationale="" constraints="" authority=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --agent) agent="$2"; shift 2;;
      --type) type="$2"; shift 2;;
      --topic) topic="$2"; shift 2;;
      --summary) summary="$2"; shift 2;;
      --rationale) rationale="$2"; shift 2;;
      --constraints) constraints="$2"; shift 2;;
      --authority) authority="$2"; shift 2;;
      *) shift;;
    esac
  done

  [[ -n "$agent" ]] || die "--agent is required"
  [[ -n "$type" ]] || die "--type is required (api-design, data-model, naming, scope, architecture, deployment, ux, brand)"
  [[ -n "$topic" ]] || die "--topic is required"
  [[ -n "$summary" ]] || die "--summary is required"

  local agent_slug; agent_slug="$(resolve_agent "$agent")"
  [[ -n "$agent_slug" ]] || die "Unknown agent: $agent"

  # Auto-fill authority from agent's decision authority section
  [[ -z "$authority" ]] && authority="$agent_slug"

  # PREVENTIVE CHECK: Calculate impact scope
  echo "记录决策: $agent_slug / $type / $topic"
  echo ""
  echo "=== 影响分析 ==="

  # Check which agents depend on this agent (from guild-contracts.yml)
  local affected=""
  local affected_count=0
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local downstream; downstream=$(echo "$line" | awk -F'|' '{print $1}')
    local item; item=$(echo "$line" | awk -F'|' '{print $2}')
    if [[ -n "$downstream" && "$downstream" != "$agent_slug" ]]; then
      if [[ -z "$(echo "$affected" | grep "$downstream")" ]]; then
        affected="$affected $downstream"
        affected_count=$((affected_count + 1))
      fi
    fi
  done < <(awk -v agent="$agent_slug" '
    /^  [a-z]/ { current=$1; gsub(/:$/,"",current) }
    /- from:/ && $0 ~ agent { found=1; print current }
  ' "$CONTRACTS" 2>/dev/null)

  if [[ -n "$affected" ]]; then
    echo "  此决策影响以下 Agent："
    for a in $affected; do
      echo "    - $a"
    done
    echo ""
    echo "  建议：通知所有受影响方。"
    echo "  是否继续记录？(Enter/Y = 继续, N = 取消)"
    read -r confirm
    [[ "$confirm" == "N" || "$confirm" == "n" ]] && { echo "已取消"; return 0; }
  else
    echo "  未检测到直接影响（基于现有契约）。"
  fi

  # Create decision record
  local id; id=$(date +%s)
  local timestamp; timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local slug_topic; slug_topic=$(echo "$topic" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//')
  local filename="${id}-${agent_slug}-${slug_topic}.json"
  local filepath="$REPO_ROOT/context/decisions/$filename"

  # Parse affected list for JSON array
  local affected_json="["
  local first=true
  for a in $affected; do
    $first && first=false || affected_json+=", "
    affected_json+="\"$a\""
  done
  affected_json+="]"

  cat > "$filepath" << JSONEOF
{
  "id": $id,
  "agent": "$agent_slug",
  "timestamp": "$timestamp",
  "decision": {
    "type": "$type",
    "topic": "$topic",
    "summary": "$summary",
    "rationale": "$rationale",
    "constraints": "$constraints",
    "authority": "$authority"
  },
  "impact": {
    "affects": $affected_json,
    "breaking_changes": [],
    "notified": [],
    "confirmed": []
  },
  "traceability": [],
  "status": "active",
  "superseded_by": null
}
JSONEOF

  # Update index
  local idx="$REPO_ROOT/context/index.json"
  local tmpidx="${idx}.tmp"
  local idx_ok=false
  if command -v node &>/dev/null; then
    node -e "
const fs=require('fs');
const idx=JSON.parse(fs.readFileSync('$idx','utf8'));
idx.updated='$timestamp';
idx.decisions.push({id:$id,agent:'$agent_slug',type:'$type',topic:'$topic',file:'$filename',status:'active'});
fs.writeFileSync('$tmpidx',JSON.stringify(idx,null,2)+'\n','utf8');
" 2>/dev/null && idx_ok=true
  fi
  if $idx_ok; then
    mv "$tmpidx" "$idx"
  else
    ok "索引更新跳过。决策已保存至: $filepath"
    return 0
  fi

  echo ""
  ok "决策 #$id 已记录: $agent_slug / $type / $topic"
  ok "文件: $filename"
  if [[ -n "$affected" ]]; then echo "  受影响方: $affected"; fi

  # Auto-notify affected agents about this decision
  if [[ -n "$affected" ]]; then
    echo "  📨 正在通知受影响方..."
    for a in $affected; do
      add_inbox_item "$a" "decision_relevant" "$agent_slug"         "topic=$topic"         "$agent_slug 做出了关于 $topic 的决策: $summary"         "确认你的工作是否受此决策影响"
      echo "    → 已通知 $a"
    done
  fi
}
