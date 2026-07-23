#!/usr/bin/env bash
#
# convert.sh — Convert AgentGuild agent .md files into tool-specific formats.
#
# Usage:
#   ./scripts/convert.sh [--tool <name>] [--help]
#
# Tools: claude-code, cursor, copilot, windsurf, all (default)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

CONFIG="$REPO_ROOT/guild.config.json"
OUT_DIR="$REPO_ROOT/integrations"

# ── Converters ────────────────────────────────────────────────────────

# identity format: direct .md copy (Claude Code, Copilot)
convert_identity() {
  local src="$1" out="$2"
  mkdir -p "$(dirname "$out")"
  cp "$src" "$out"
}

# cursor-mdc format: .mdc rule file with frontmatter
convert_cursor_mdc() {
  local src="$1" out="$2"
  local name desc
  name="$(get_field name "$src")"
  desc="$(get_field description "$src")"
  mkdir -p "$(dirname "$out")"
  {
    echo "---"
    echo "description: $desc"
    echo "globs: **/*"
    echo "alwaysApply: false"
    echo "---"
    echo ""
    get_body "$src"
  } > "$out"
}

# windsurf-rules format: all agents merged into one file
convert_windsurf_rules() {
  local out="$1"; shift
  local srcs=("$@")
  mkdir -p "$(dirname "$out")"
  {
    echo "# AgentGuild Agents"
    echo "# Generated: $(date +%Y-%m-%d)"
    echo "# Agent count: ${#srcs[@]}"
    echo ""
    for src in "${srcs[@]}"; do
      local name; name="$(get_field name "$src")"
      echo "# --- $name ---"
      echo ""
      get_body "$src"
      echo ""
      echo ""
    done
  } > "$out"
}

# ── Main ──────────────────────────────────────────────────────────────

TOOL="${1:-all}"
if [[ "$TOOL" == "--tool" ]]; then
  TOOL="${2:-all}"
fi

case "$TOOL" in
  --help|-h|help)
    sed -n '3,12p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac

# Collect agent files from config
AGENT_FILES=()
while IFS= read -r f; do
  AGENT_FILES+=("$f")
done < <(get_agent_files "$CONFIG")

convert_tool() {
  local tool="$1"
  local format; format=$(awk -F'"' '/"'"$tool"'"/{found=1} found && /"format":/{print $4; exit}' "$CONFIG")
  local kind; kind=$(awk -F'"' '/"'"$tool"'"/{found=1} found && /"installKind":/{print $4; exit}' "$CONFIG")

  echo "Converting for $tool (format=$format, kind=$kind)..."

  local tool_out="$OUT_DIR/$tool"
  rm -rf "$tool_out"
  mkdir -p "$tool_out"

  case "$format" in
    identity)
      for src in "${AGENT_FILES[@]}"; do
        local slug; slug="$(agent_slug "$src")"
        local out="$tool_out/${slug}.md"
        convert_identity "$src" "$out"
        ok "  $slug"
      done
      ;;
    cursor-mdc)
      for src in "${AGENT_FILES[@]}"; do
        local slug; slug="$(agent_slug "$src")"
        local out="$tool_out/${slug}.mdc"
        convert_cursor_mdc "$src" "$out"
        ok "  $slug"
      done
      ;;
    windsurf-rules)
      local out="$tool_out/.windsurfrules"
      convert_windsurf_rules "$out" "${AGENT_FILES[@]}"
      ok "  .windsurfrules (${#AGENT_FILES[@]} agents merged)"
      ;;
    *)
      warn "Unknown format '$format' for tool '$tool' — skipping"
      ;;
  esac
}

case "$TOOL" in
  all)
    for tool in claude-code cursor copilot windsurf; do
      convert_tool "$tool"
    done
    ;;
  claude-code|cursor|copilot|windsurf)
    convert_tool "$TOOL"
    ;;
  *)
    die "Unknown tool: $TOOL. Valid: claude-code, cursor, copilot, windsurf, all"
    ;;
esac

echo ""
ok "Conversion complete. Output: $OUT_DIR"
