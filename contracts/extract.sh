#!/usr/bin/env bash
#
# extract.sh — Extract structured collaboration contracts from AgentGuild agent files.
#
# Reads all agent .md files, parses their section 13 (协作契约),
# and generates contracts/guild-contracts.yml.
#
# Usage:
#   ./contracts/extract.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=../scripts/lib.sh
. "$REPO_ROOT/scripts/lib.sh"

CONFIG="$REPO_ROOT/guild.config.json"
OUTPUT="$REPO_ROOT/contracts/guild-contracts.yml"

{
  echo "# AgentGuild Collaboration Contracts"
  echo "# Auto-generated: $(date -Iseconds)"
  echo "# Source: agents/*/ section 13 (协作契约)"
  echo "#"
  echo "# Schema:"
  echo "#   <agent-slug>:"
  echo "#     delivers:"
  echo "#       - name: <deliverable-name>"
  echo "#         description: <what-it-is>"
  echo "#     requires:"
  echo "#       - from: <upstream-agent-slug>"
  echo "#         items:"
  echo "#           - name: <requirement-name>"
  echo "#             description: <what-it-is>"
  echo "#             required: true|false"
  echo "---"
  echo "contracts:"
  echo ""

  while IFS= read -r agent_file; do
    [[ -f "$agent_file" ]] || continue
    slug="$(agent_slug "$agent_file")"
    name="$(get_field name "$agent_file")"
    echo "# ── $name ──"
    parse_contract "$agent_file"
    echo ""
  done < <(get_agent_files "$CONFIG")

  echo ""
  echo "# ── Generated $(date -Iseconds) ──"
} > "$OUTPUT"

echo "[OK] Contracts extracted to: $OUTPUT"
echo "     Agents processed: $(get_agent_files "$CONFIG" | wc -l)"
