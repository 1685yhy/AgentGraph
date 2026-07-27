#!/usr/bin/env bash
#
# ci-test.sh — Fast CI smoke tests for AgentGraph
#
# Runs on every push/PR. Designed to complete in <30s.
# Focused on: no regressions, no duplicate IDs, all commands respond.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

GUILD="$REPO_ROOT/guild"
PASSED=0
FAILED=0

pass() { PASSED=$((PASSED + 1)); }
fail() { FAILED=$((FAILED + 1)); err "$1"; }

echo "╔══════════════════════════════════════════╗"
echo "║  AgentGraph CI Smoke Test                ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ── 1. Duplicate check ──
echo "── 1. Duplicate ID check ──"
if timeout 10 "$GUILD" check --duplicates > /dev/null 2>&1; then
  ok "No duplicate handoff IDs"
  pass
else
  fail "Duplicate handoff IDs found!"
fi

# ── 2. Gate system ──
echo "── 2. Gate system ──"
if timeout 10 "$GUILD" gate --list > /dev/null 2>&1; then
  ok "Gate list works"
  pass
else
  fail "gate --list failed"
fi

# ── 3. Handoff integrity ──
echo "── 3. Handoff integrity ──"
errors=0
for f in "$REPO_ROOT/handoffs"/*.json; do
  [[ -f "$f" ]] || continue
  [[ "$(basename "$f")" == self-test-* ]] && continue
  if ! node -e "JSON.parse(require('fs').readFileSync('$f','utf8'))" 2>/dev/null; then
    err "Invalid JSON: $(basename "$f")"
    errors=$((errors + 1))
  fi
done
if [[ $errors -eq 0 ]]; then
  ok "All handoff JSON files valid"
  pass
else
  fail "$errors handoff files have invalid JSON"
fi

# ── 4. CLI commands respond ──
echo "── 4. CLI smoke ──"
for cmd in "status" "feedback --list" "changelog" "list --handoffs" "context show"; do
  if timeout 10 "$GUILD" $cmd > /dev/null 2>&1; then
    pass
  else
    fail "guild $cmd"
  fi
done

# ── 5. Config consistency ──
echo "── 5. Config consistency ──"
config_count=$(awk -F'"' '/"slug":/{print $4}' "$REPO_ROOT/guild.config.json" | sort -u | wc -l)
file_count=$(find "$REPO_ROOT/agents" -name "*.md" | wc -l)
if [[ "$config_count" -eq "$file_count" ]]; then
  ok "Config-agent consistency: $config_count agents match"
  pass
else
  fail "Mismatch: $config_count in config vs $file_count agent files"
fi

# ── 6. Graph engine ──
echo "── 6. Graph engine ──"
if timeout 15 "$GUILD" graph --file "$REPO_ROOT/graphs/feature-dev.yml" --dry-run > /dev/null 2>&1; then
  ok "Graph engine parses feature-dev.yml"
  pass
else
  fail "Graph engine failed on feature-dev.yml"
fi

# ── Summary ──
echo ""
echo "══════════════════════════════════════════"
echo "  $PASSED passed, $FAILED failed"
echo "══════════════════════════════════════════"

[[ $FAILED -eq 0 ]]
