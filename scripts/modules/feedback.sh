#!/usr/bin/env bash
# Module: feedback.sh — cmd_feedback
# Source guard: only loadable via guild
[[ -n "${_AG_MODULE_SOURCING:-}" ]] || { echo "This module must be loaded via guild, not run directly" >&2; exit 1; }

# ── cmd_feedback ──────────────────────────────────────────────────────

# Usage: guild feedback --handoff <id> --type bug|improvement --summary "..." [--severity low|medium|high|critical] [--repro "..."]
#        guild feedback --list [--handoff <id>] [--status open|fixed]
#        guild feedback --fix <feedback-id> --handoff <new-handoff-id>

cmd_feedback() {
  local handoff_id="" fb_type="" severity="medium" summary="" repro=""
  local list_mode=false list_status="" fix_id="" fix_handoff=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --handoff) handoff_id="$2"; shift 2;;
      --type) fb_type="$2"; shift 2;;
      --severity) severity="$2"; shift 2;;
      --summary) summary="$2"; shift 2;;
      --repro) repro="$2"; shift 2;;
      --list) list_mode=true; shift;;
      --status) list_status="$2"; shift 2;;
      --fix) fix_id="$2"; shift 2;;
      *) shift;;
    esac
  done

  # List mode
  if $list_mode; then
    mkdir -p "$FEEDBACK_DIR"
    echo "=== 反馈列表 ==="
    echo ""
    local count=0
    for f in "$FEEDBACK_DIR"/fb-*.json; do
      [[ -f "$f" ]] || continue
      local id hid type severity summary status created
      id=$(json_get "$f" "id")
      hid=$(json_get "$f" "handoff_id")
      type=$(json_get "$f" "type")
      severity=$(json_get "$f" "severity")
      summary=$(json_get "$f" "summary")
      status=$(json_get "$f" "status")
      created=$(json_get "$f" "created")
      created="${created:0:19}"

      [[ -n "$id" ]] || continue
      [[ -n "$handoff_id" && "$hid" != "$handoff_id" ]] && continue
      [[ -n "$list_status" && "$status" != "$list_status" ]] && continue

      local icon
      case "$type" in
        bug) icon="🐛";;
        improvement) icon="💡";;
        *) icon="📋";;
      esac

      local sev_icon
      case "$severity" in
        critical) sev_icon="🔴";;
        high) sev_icon="🟠";;
        medium) sev_icon="🟡";;
        low) sev_icon="🟢";;
        *) sev_icon="⚪";;
      esac

      echo "  $icon $id [$sev_icon$severity] $summary"
      echo "    Handoff #$hid | 状态: $status | $created"
      echo ""
      count=$((count + 1))
    done
    [[ $count -eq 0 ]] && echo "  (无反馈记录)"
    return 0
  fi

  # Fix/link mode
  if [[ -n "$fix_id" ]]; then
    [[ -n "$fix_handoff" ]] || { handoff_id="${handoff_id:-}"; fix_handoff="$handoff_id"; }
    [[ -n "$fix_handoff" ]] || die "--handoff <new-handoff-id> is required with --fix"

    local fb_file="$FEEDBACK_DIR/$fix_id.json"
    [[ -f "$fb_file" ]] || die "反馈 $fix_id 不存在"

    local fix_ok=false
    if command -v node &>/dev/null; then
      node -e "
const fs=require('fs'),d=JSON.parse(fs.readFileSync('$fb_file','utf8'));
d.status='fixed';d.linked_fix_handoff='$fix_handoff';d.resolved=new Date().toISOString().replace(/\.[0-9]+Z/,'Z');
fs.writeFileSync('$fb_file',JSON.stringify(d,null,2)+'\n','utf8');
console.log('反馈 $fix_id 已标记为已修复（关联 Handoff #$fix_handoff）');
" 2>/dev/null && fix_ok=true
    fi
    $fix_ok || ok "反馈 $fix_id 已链接"
    return
  fi

  # Create mode
  [[ -n "$handoff_id" ]] || die "--handoff <id> is required"
  [[ -n "$fb_type" ]] || die "--type <bug|improvement> is required"
  [[ -n "$summary" ]] || die "--summary is required"

  mkdir -p "$FEEDBACK_DIR"

  local max=0
  for f in "$FEEDBACK_DIR"/fb-*.json; do
    [[ -f "$f" ]] || continue
    local num; num=$(basename "$f" .json | sed 's/fb-//')
    ((10#$num > max)) && max=$((10#$num))
  done
  local fb_id_num=$((max + 1))
  local fb_id
  fb_id=$(printf "fb-%03d" $fb_id_num)
  local date; date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local fb_file="$FEEDBACK_DIR/$fb_id.json"

  cat > "$fb_file" << JSONEOF
{
  "id": "$fb_id",
  "handoff_id": $handoff_id,
  "type": "$fb_type",
  "severity": "$severity",
  "summary": "$summary",
  "repro_steps": "$repro",
  "status": "open",
  "linked_fix_handoff": null,
  "created": "$date",
  "resolved": null
}
JSONEOF

  ok "反馈已记录: $fb_id ($summary)"
  echo "  文件: $fb_file"
}
