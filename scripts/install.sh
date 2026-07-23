#!/usr/bin/env bash
#
# install.sh — Install AgentGuild agents into local AI tools.
#
# Usage:
#   ./scripts/install.sh [--tool <name>] [--dry-run] [--help]
#
# Tools: claude-code, cursor, copilot, windsurf, all (default)
# Run convert.sh first if integrations/ is missing or stale.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

CONFIG="$REPO_ROOT/guild.config.json"
INTEGRATIONS="$REPO_ROOT/integrations"
DRY_RUN=false

# ── Tool detection ──────────────────────────────────────────────────

detect_tools() {
  local found=()
  [[ -d "$HOME/.claude" ]] && found+=(claude-code)
  [[ -d "$HOME/.cursor" ]] && found+=(cursor)
  command -v gh &>/dev/null && found+=(copilot)
  [[ -d "$HOME/.windsurf" || -d "$HOME/.codeium" ]] && found+=(windsurf)
  echo "${found[@]:-none}"
}

# ── Installers ──────────────────────────────────────────────────────

install_claude_code() {
  local src_dir="$INTEGRATIONS/claude-code"
  local dest="$HOME/.claude/agents"
  mkdir -p "$dest"
  for f in "$src_dir"/*.md; do
    [[ -f "$f" ]] || continue
    if $DRY_RUN; then
      echo "  [DRY-RUN] cp $f -> $dest/"
    else
      cp "$f" "$dest/"
      ok "  $(basename "$f")"
    fi
  done
}

install_cursor() {
  local src_dir="$INTEGRATIONS/cursor"
  local dest="${CURSOR_RULES_DIR:-$PWD/.cursor/rules}"
  mkdir -p "$dest"
  for f in "$src_dir"/*.mdc; do
    [[ -f "$f" ]] || continue
    if $DRY_RUN; then
      echo "  [DRY-RUN] cp $f -> $dest/"
    else
      cp "$f" "$dest/"
      ok "  $(basename "$f")"
    fi
  done
}

install_copilot() {
  local src_dir="$INTEGRATIONS/copilot"
  for dest in "$HOME/.github/agents" "$HOME/.copilot/agents"; do
    mkdir -p "$dest"
    for f in "$src_dir"/*.md; do
      [[ -f "$f" ]] || continue
      if $DRY_RUN; then
        echo "  [DRY-RUN] cp $f -> $dest/"
      else
        cp "$f" "$dest/"
        ok "  $(basename "$f") -> $dest"
      fi
    done
  done
}

install_windsurf() {
  local src="$INTEGRATIONS/windsurf/.windsurfrules"
  local dest="${WINDSURF_RULES_DIR:-$PWD}/.windsurfrules"
  if $DRY_RUN; then
    echo "  [DRY-RUN] cp $src -> $dest"
  else
    cp "$src" "$dest"
    ok "  .windsurfrules"
  fi
}

# ── Main ────────────────────────────────────────────────────────────

TOOL="all"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tool) TOOL="${2:-all}"; shift 2;;
    --dry-run) DRY_RUN=true; shift;;
    --help|-h|help) sed -n '3,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) TOOL="$1"; shift;;
  esac
done

# Check integrations exist
if [[ ! -d "$INTEGRATIONS/claude-code" ]]; then
  warn "Integrations not found. Run ./scripts/convert.sh first."
  exit 1
fi

install_tool() {
  local tool="$1"
  echo "Installing for $tool..."
  case "$tool" in
    claude-code)  install_claude_code ;;
    cursor)       install_cursor ;;
    copilot)      install_copilot ;;
    windsurf)     install_windsurf ;;
    *)            die "Unknown tool: $tool" ;;
  esac
}

case "$TOOL" in
  all)
    echo "Detected tools: $(detect_tools)"
    echo ""
    for tool in claude-code cursor copilot windsurf; do
      install_tool "$tool"
    done
    ;;
  claude-code|cursor|copilot|windsurf)
    install_tool "$TOOL"
    ;;
  *)
    die "Unknown: $TOOL. Valid: claude-code, cursor, copilot, windsurf, all"
    ;;
esac

echo ""
ok "Installation complete."
$DRY_RUN && echo "[DRY-RUN mode — no files were written]"
