#!/usr/bin/env bash
# Module: status.sh — cmd_status
# Source guard: only loadable via guild
[[ -n "${_AG_MODULE_SOURCING:-}" ]] || { echo "This module must be loaded via guild, not run directly" >&2; exit 1; }

cmd_status() {
  local agent="" status_filter=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --agent) agent="$2"; shift 2;;
      --status) status_filter="$2"; shift 2;;
      *) shift;;
    esac
  done

  echo "当前交接状态:"
  echo ""

  local count=0
  for f in "$HANDOFFS_DIR"/*.json; do
    [[ -f "$f" ]] || continue
    local id from to status timestamp
    id=$(json_get "$f" "id")
    from=$(json_get "$f" "from")
    to=$(json_get "$f" "to")
    status=$(json_get "$f" "status")
    timestamp=$(json_get "$f" "timestamp")
    timestamp="${timestamp:0:19}"

    [[ -n "$id" ]] || continue

    # Filter
    [[ -n "$agent" && "$from" != "$agent" && "$to" != "$agent" ]] && continue
    [[ -n "$status_filter" && "$status" != "$status_filter" ]] && continue

    local icon
    case "$status" in
      ready) icon="✅";;
      incomplete) icon="⚠️";;
      needs_fix) icon="🔧";;
      accepted) icon="✔️";;
      *) icon="📋";;
    esac

    echo "  $icon #$id: $from → $to ($status) — $timestamp"
    count=$((count + 1))
  done

  if (( count == 0 )); then
    echo "  (无交接记录)"
  fi

  # Check for stale handoffs (older than 7 days, incomplete or needs_fix)
  local stale_count=0
  for f in "$HANDOFFS_DIR"/*.json; do
    [[ -f "$f" ]] || continue
    local sid sstatus sts
    sid=$(json_get "$f" "id")
    sstatus=$(json_get "$f" "status")
    sts=$(json_get "$f" "timestamp")
    sts="${sts:0:19}"
    [[ -n "$sid" ]] || continue
    [[ "$sstatus" == "incomplete" || "$sstatus" == "needs_fix" ]] || continue
    local septokh
    septokh=$(date -d "$(echo "$sts" | tr 'T' ' ')" +%s 2>/dev/null || echo 0)
    local now_epoch
    now_epoch=$(date +%s)
    local age_days=$(( (now_epoch - septokh) / 86400 ))
    if (( age_days >= 7 )); then
      stale_count=$((stale_count + 1))
    fi
  done

  if (( stale_count > 0 )); then
    echo ""
    echo "  ⚠  Warning: $stale_count stale handoff(s) found (older than 7 days, incomplete/needs_fix)."
    echo "     Run 'guild cleanup' to review or 'guild cleanup --stale' to archive."
  fi
}
