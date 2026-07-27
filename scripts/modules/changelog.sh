#!/usr/bin/env bash
# Module: changelog.sh — cmd_changelog
# Source guard: only loadable via guild
[[ -n "${_AG_MODULE_SOURCING:-}" ]] || { echo "This module must be loaded via guild, not run directly" >&2; exit 1; }

# ── cmd_changelog ──────────────────────────────────────────────────────

# Usage: guild changelog [--since <version|date>]

cmd_changelog() {
  local since=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --since) since="$2"; shift 2;;
      *) shift;;
    esac
  done

  local -a handoff_files=()
  for f in "$HANDOFFS_DIR"/*.json; do
    [[ -f "$f" ]] || continue
    local status
    status=$(json_get "$f" "status")
    [[ "$status" != "accepted" ]] && continue
    handoff_files+=("$f")
  done

  if [[ ${#handoff_files[@]} -eq 0 ]]; then
    echo "暂无已接受的交接记录。"
    return
  fi

  # Sort by timestamp
  local sorted
  sorted=$(for f in "${handoff_files[@]}"; do
    if command -v node &>/dev/null; then
      node -e "
const d=JSON.parse(require('fs').readFileSync('$f','utf8'));
console.log(d.timestamp+' '+d.id+' '+d.from+' '+d.to+' '+(d.message||''));
" 2>/dev/null
    fi
  done | sort)

  echo "变更日志"
  echo "========"
  echo ""

  local count=0
  local version_minor=0

  while IFS=' ' read -r ts id from to msg; do
    [[ -z "$ts" ]] && continue
    count=$((count + 1))
    if (( count % 5 == 1 )); then
      version_minor=$((version_minor + 1))
      local date_str; date_str=$(echo "$ts" | cut -d'T' -f1)
      echo ""
      echo "v0.${version_minor}.0 ($date_str)"
      echo "------------------------------"
    fi

    # Check if this handoff is linked to any feedback
    local fb_ref=""
    for ff in "$FEEDBACK_DIR"/fb-*.json; do
      [[ -f "$ff" ]] || continue
      local linked
      linked=$(json_get "$ff" "linked_fix_handoff")
      if [[ -n "$linked" ]]; then
        # Check if linked handoff id matches this handoff's id as string
        local h_id_str="$id"
        if [[ "$linked" == "$h_id_str" ]]; then
          local fb_summary
          fb_summary=$(json_get "$ff" "summary")
          local fb_id_name
          fb_id_name=$(json_get "$ff" "id")
          fb_ref="$fb_id_name: $fb_summary"
          break
        fi
      fi
    done

    if [[ -n "$fb_ref" ]]; then
      echo "  ✅ 修复: $fb_ref"
      [[ -n "$msg" ]] && echo "     $msg"
      echo "     [handoff #$id]"
    else
      local display_msg="${msg:-交付完成}"
      echo "  ✅ $from → $to: $display_msg [handoff #$id]"
    fi
  done <<< "$sorted"
}
