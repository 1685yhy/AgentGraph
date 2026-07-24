#!/usr/bin/env bash
#
# agent-prompt.sh — Generate activation prompt for any agent with inbox context.
#
# Usage:
#   ./scripts/agent-prompt.sh <agent-slug>
#   ./scripts/agent-prompt.sh backend-architect
#
# Output:
#   You are Backend Architect.
#   Before starting work, check these items:
#   🔵 1. [PM] PM's PRD — request supplement
#   Complete pending items before new work.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

CONFIG="$REPO_ROOT/guild.config.json"

if [[ $# -eq 0 ]]; then
  echo "Usage: $0 <agent-slug>"
  echo "  e.g., $0 backend-architect"
  exit 0
fi

AGENT_SLUG="$1"

# Look up agent name in config
AGENT_NAME=$(awk -F'"' -v slug="$AGENT_SLUG" '
  /"slug":/ { s = $4 }
  /"file":/ && s == slug { getline; next }
  /"slug":/ { s = $4; next }
  s == slug && /"division":/ { div = $4 }
  END { print s }
' "$CONFIG")

# Try to find the actual display name from the agent file
AGENT_FILE=$(awk -F'"' -v slug="$AGENT_SLUG" '
  /"slug":/ { s = $4 }
  /"file":/ && s == slug { print $12; exit }
' "$CONFIG")

DISPLAY_NAME="$AGENT_SLUG"
if [[ -f "$REPO_ROOT/$AGENT_FILE" ]]; then
  DISPLAY_NAME=$(get_field "name" "$REPO_ROOT/$AGENT_FILE")
fi

# ANSI color
C_BOLD=$'\033[1m'
C_RESET=$'\033[0m'

echo "${C_BOLD}你是 ${DISPLAY_NAME}。${C_RESET}"
echo ""

INBOX="$REPO_ROOT/context/inbox/${AGENT_SLUG}.json"

if [[ -f "$INBOX" ]]; then
  UNREAD=$(python3 -c "
import json
d = json.load(open('$INBOX'))
print(d['unread'])
" 2>/dev/null || echo "0")

  if [[ "$UNREAD" -gt 0 ]]; then
    echo "在开始工作前，检查以下待办:"
    echo ""

    python3 -c "
import json
d = json.load(open('$INBOX'))
count = 0
for item in d['items']:
    if item['read']: continue
    count += 1
    icon = {'handoff_incoming': '📨', 'conflict_active': '⚠️', 'decision_relevant': '📋'}.get(item['type'], '📌')
    from_display = item['from']
    print(f'  🔵 {count}. {icon} [{from_display}] {item[\"summary\"]}')
    print(f'      → {item[\"action\"]}')
    print()
" 2>/dev/null || {
      # Fallback: show raw
      echo "  (有 $UNREAD 条未读消息)"
    }
    echo "完成待办后开始新任务。"
  else
    echo "收件箱为空。可以开始新任务。"
  fi
else
  echo "收件箱为空。可以开始新任务。"
fi
