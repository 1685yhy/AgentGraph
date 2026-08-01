#!/usr/bin/env bash
#
# event-bus.sh — AgentGraph Event Bus (filesystem backend).
# Watches handoffs/ directory for new completed handoffs.
#
# Modes:
#   - inotifywait (Linux, real-time)
#   - polling (fallback, 2s interval)
#
# Usage:
#   guild watch [--once] [--timeout <seconds>]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

HANDOFFS_DIR="$REPO_ROOT/handoffs"
POLL_INTERVAL=2  # seconds

# ── Detect transport ──
detect_transport() {
  if command -v inotifywait &>/dev/null; then
    echo "inotify"
  else
    echo "polling"
  fi
}

# ── inotify mode ──
watch_inotify() {
  local once="${1:-false}" timeout="${2:-0}"
  local start_time; start_time=$(date +%s)

  echo "[EventBus] Watching $HANDOFFS_DIR (inotify mode)"

  while true; do
    local event
    event=$(inotifywait -q -e close_write -e moved_to --format '%w%f' "$HANDOFFS_DIR" 2>/dev/null) || continue

    # Only process .json files
    [[ "$event" == *.json ]] || continue
    local fname; fname=$(basename "$event")

    # Parse handoff metadata
    if command -v node &>/dev/null; then
      local info
      info=$(node -e "
        try {
          const d=JSON.parse(require('fs').readFileSync('$event','utf8'));
          console.log('handoff_id='+d.id+' from='+d.from+' to='+d.to+' status='+(d.status||'unknown')+' file='+'$fname');
        } catch(e) { console.log(''); }
      " 2>/dev/null)
      [[ -n "$info" ]] && echo "EVENT: $info"
    else
      echo "EVENT: file=$fname"
    fi

    if $once; then return 0; fi
    if [[ $timeout -gt 0 ]] && [[ $(($(date +%s) - start_time)) -ge $timeout ]]; then
      echo "[EventBus] Timeout reached."
      return 0
    fi
  done
}

# ── Polling mode ──
watch_polling() {
  local once="${1:-false}" timeout="${2:-0}"
  local start_time; start_time=$(date +%s)

  echo "[EventBus] Watching $HANDOFFS_DIR (polling mode, ${POLL_INTERVAL}s)"

  # Track known files
  local -A seen
  for f in "$HANDOFFS_DIR"/*.json; do
    [[ -f "$f" ]] || continue
    seen["$(basename "$f")"]=1
  done

  while true; do
    for f in "$HANDOFFS_DIR"/*.json; do
      [[ -f "$f" ]] || continue
      local fname; fname=$(basename "$f")
      [[ -n "${seen[$fname]:-}" ]] && continue
      seen["$fname"]=1

      # New file detected
      if command -v node &>/dev/null; then
        local info
        info=$(node -e "
          try {
            const d=JSON.parse(require('fs').readFileSync('$f','utf8'));
            console.log('handoff_id='+d.id+' from='+d.from+' to='+d.to+' status='+(d.status||'unknown')+' file='+'$fname');
          } catch(e) { console.log(''); }
        " 2>/dev/null)
        [[ -n "$info" ]] && echo "EVENT: $info"
      else
        echo "EVENT: file=$fname"
      fi

      if $once; then return 0; fi
    done

    if [[ $timeout -gt 0 ]] && [[ $(($(date +%s) - start_time)) -ge $timeout ]]; then
      echo "[EventBus] Timeout reached."
      return 0
    fi

    sleep "$POLL_INTERVAL"
  done
}

# ── Main ──
cmd_watch() {
  local once=false timeout=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --once) once=true; shift ;;
      --timeout) timeout="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  local transport; transport=$(detect_transport)
  case "$transport" in
    inotify) watch_inotify "$once" "$timeout" ;;
    polling) watch_polling "$once" "$timeout" ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  cmd_watch "$@"
fi
