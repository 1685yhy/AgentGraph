#!/usr/bin/env bash
# Module: cleanup.sh — cmd_cleanup
# Source guard: only loadable via guild
[[ -n "${_AG_MODULE_SOURCING:-}" ]] || { echo "This module must be loaded via guild, not run directly" >&2; exit 1; }

# ── cmd_cleanup ──────────────────────────────────────────────────────

# Usage: guild cleanup [--stale]
cmd_cleanup() {
  local stale_mode=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --stale) stale_mode=true; shift;;
      *) shift;;
    esac
  done

  # Gather stuck handoffs (incomplete or needs_fix)
  local -a stale_items=()
  for f in "$HANDOFFS_DIR"/*.json; do
    [[ -f "$f" ]] || continue
    local sid sfrom sto sstatus sts
    sid=$(json_get "$f" "id")
    sfrom=$(json_get "$f" "from")
    sto=$(json_get "$f" "to")
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
    stale_items+=("$sid|$sfrom|$sto|$sstatus|$age_days|$f")
  done

  if [[ ${#stale_items[@]} -eq 0 ]]; then
    echo "  No stale handoffs found."
    return 0
  fi

  if $stale_mode; then
    local archive_dir="$HANDOFFS_DIR/.archive"
    mkdir -p "$archive_dir"
    echo "Archiving stale handoffs:"
    for entry in "${stale_items[@]}"; do
      local sid sfrom sto sstatus age_days fpath
      IFS='|' read -r sid sfrom sto sstatus age_days fpath <<< "$entry"
      mv "$fpath" "$archive_dir/"
      echo "  Archived #$sid: $sfrom → $sto ($sstatus, ${age_days}d old)"
    done
  else
    echo "Stale handoffs (incomplete/needs_fix):"
    for entry in "${stale_items[@]}"; do
      local sid sfrom sto sstatus age_days fpath
      IFS='|' read -r sid sfrom sto sstatus age_days fpath <<< "$entry"
      if (( age_days >= 7 )); then
        echo "  ⚠ #$sid: $sfrom → $sto ($sstatus, ${age_days}d old)"
      else
        echo "    #$sid: $sfrom → $sto ($sstatus, ${age_days}d old)"
      fi
    done
    echo ""
    echo "Run 'guild cleanup --stale' to archive them."
  fi
}
