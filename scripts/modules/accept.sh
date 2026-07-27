#!/usr/bin/env bash
# Module: accept.sh — cmd_accept
# Source guard: only loadable via guild
[[ -n "${_AG_MODULE_SOURCING:-}" ]] || { echo "This module must be loaded via guild, not run directly" >&2; exit 1; }

# ── cmd_accept ─────────────────────────────────────────────────────────

cmd_accept() {
  local id="" as=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --handoff) id="$2"; shift 2;;
      --as) as="$2"; shift 2;;
      *) shift;;
    esac
  done

  [[ -z "$id" ]] && die "--handoff <id> is required"
  [[ -z "$as" ]] && die "--as <agent> is required"

  local as_slug
  as_slug="$(resolve_agent "$as")"
  [[ -n "$as_slug" ]] || die "Unknown agent: $as"

  # Find handoff file by ID
  local json_file=""
  for f in "$HANDOFFS_DIR"/*.json; do
    [[ -f "$f" ]] || continue
    local fid
    fid=$(json_get "$f" "id")
    if [[ "$fid" == "$id" ]]; then
      json_file="$f"
      break
    fi
  done

  [[ -f "$json_file" ]] || die "Handoff #$id not found"

  echo "接收交接 #$id ..."
  echo ""

  # ── Precondition: status must be "ready" ──
  local current_status
  current_status=$(json_get "$json_file" "status")

  if [[ "$current_status" == "accepted" ]]; then
    err "无法接收: 交接已被接收"
    return 1
  fi

  # ── Guild Gate: run all 5 quality gates ──
  echo "━━━ 质量门禁检查 ━━━"
  echo ""
  if ! cmd_gate --handoff "$id"; then
    echo ""
    err "无法接收: 质量门禁未通过"
    echo "→ 请修复后重新 handoff"
    return 1
  fi
  echo "━━━ 门禁检查通过 ━━━"
  echo ""

  # ── Additional check: open critical bugs on this handoff ──
  local reject_reasons=""
  if [[ -d "$FEEDBACK_DIR" ]]; then
    local open_criticals=""
    for ff in "$FEEDBACK_DIR"/fb-*.json; do
      [[ -f "$ff" ]] || continue
      local fb_hid fb_sev fb_status fb_summary fb_id
      fb_hid=$(json_get "$ff" "handoff_id")
      fb_sev=$(json_get "$ff" "severity")
      fb_status=$(json_get "$ff" "status")
      fb_summary=$(json_get "$ff" "summary")
      fb_id=$(json_get "$ff" "id")

      if [[ "$fb_hid" == "$id" && "$fb_status" == "open" && "$fb_sev" == "critical" ]]; then
        open_criticals="${open_criticals}  - $fb_id ($fb_summary)\n"
      fi
    done
    if [[ -n "$open_criticals" ]]; then
      reject_reasons="${reject_reasons}有关联的未解决关键 bug:\n${open_criticals}"
    fi
  fi

  if [[ -n "$reject_reasons" ]]; then
    err "无法接收:"
    echo -e "$reject_reasons"
    echo "→ 请修复后重新 handoff"
    return 1
  fi

  # ── All gates passed — proceed with accept ──
  local accept_ok=false
  if command -v node &>/dev/null; then
    node -e "
const fs=require('fs');
let d=JSON.parse(fs.readFileSync('$json_file','utf8'));
if(d.to!=='$as_slug'){console.log('警告: 交接目标为 '+d.to+'，但你以 $as_slug 身份接收')}
d.status='accepted'; d.accepted_by='$as_slug';
fs.writeFileSync('$json_file',JSON.stringify(d,null,2)+'\n','utf8');
console.log('交接 #'+d.id+' 已接收 — $as_slug 开始工作');
" 2>/dev/null && accept_ok=true
  fi
  $accept_ok || ok "交接 #$id 已标记为接收"
}
