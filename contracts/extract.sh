#!/usr/bin/env bash
#
# extract.sh — Extract structured collaboration contracts from AgentGraph agent files.
#
# Reads all agent .md files, parses their section 13 (协作契约),
# and generates contracts/guild-contracts.yml.
#
# Usage:
#   ./contracts/extract.sh [--validate]
#
# Options:
#   --validate   Run post-extraction validation checks on the output

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=../scripts/lib.sh
. "$REPO_ROOT/scripts/lib.sh"

CONFIG="$REPO_ROOT/guild.config.json"
OUTPUT="$REPO_ROOT/contracts/guild-contracts.yml"

# ── Argument parsing ────────────────────────────────────────────────
VALIDATE_MODE=false
for arg in "$@"; do
  case "$arg" in
    --validate) VALIDATE_MODE=true;;
  esac
done

{

  echo "# AgentGraph Collaboration Contracts"
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

  processed=0
  failed=0

  while IFS= read -r agent_file; do
    [[ -f "$agent_file" ]] || continue
    slug="$(agent_slug "$agent_file")"
    name="$(get_field name "$agent_file")"
    echo "# ── $name ──"

    # Error handling: catch failures from parse_contract so a single
    # malformed section doesn't abort the entire extraction
    if ! parse_contract "$agent_file" 2>/dev/null; then
      warn "extract: failed to parse contract for '$slug' ($name) — section 13 may be missing or malformed"
      echo "  ${slug}:"
      echo "    delivers: []"
      echo "    requires: []"
      failed=$((failed + 1))
    fi

    echo ""
    processed=$((processed + 1))
  done < <(get_agent_files "$CONFIG")

  echo ""
  echo "# ── Generated $(date -Iseconds) ──"
} > "$OUTPUT"

echo "[OK] Contracts extracted to: $OUTPUT"
echo "     Agents processed: $processed"
[[ $failed -gt 0 ]] && warn "     Agents with malformed sections: $failed"

# ── Validation (--validate flag) ────────────────────────────────────
if $VALIDATE_MODE; then
  echo ""
  echo "── Validation ──"
  errors=0

  # Check 1: File is not empty and has expected structure
  if [[ ! -s "$OUTPUT" ]]; then
    err "  [ERR] Output file is empty"
    errors=$((errors + 1))
  else
    if grep -q 'contracts:' "$OUTPUT"; then
      ok "  [OK] Output has 'contracts:' root key"
    else
      err "  [ERR] Output missing 'contracts:' root key"
      errors=$((errors + 1))
    fi
  fi

  # Check 2: No empty deliverable names
  empty_names=""
  empty_names=$(grep -c 'name: ""' "$OUTPUT" 2>/dev/null || echo 0)
  if [[ "$empty_names" -eq 0 ]]; then
    ok "  [OK] No empty deliverable names"
  else
    err "  [ERR] $empty_names empty deliverable name(s) found"
    errors=$((errors + 1))
  fi

  # Check 3: No malformed YAML constructs (e.g., unquoted colons in values)
  if grep -qE 'name: .*:.*' "$OUTPUT" 2>/dev/null; then
    warn "  [!!] Some names contain colons — ensure they are properly quoted"
  else
    ok "  [OK] All names appear properly formatted"
  fi

  # Check 4: All referenced 'from' agents exist in config
  config_slugs=""
  config_slugs=$(get_agent_slugs "$CONFIG")
  missing_from=0
  while IFS= read -r from_agent; do
    [[ -z "$from_agent" ]] && continue
    if ! echo "$config_slugs" | grep -q "^${from_agent}$"; then
      err "  [ERR] requires references unknown agent: '$from_agent'"
      missing_from=$((missing_from + 1))
    fi
  done < <(grep -oP '(?<=from: ")[^"]+' "$OUTPUT" 2>/dev/null || true)

  if [[ $missing_from -eq 0 ]]; then
    ok "  [OK] All referenced 'from' agents exist in config"
  else
    warn "  [!!] $missing_from unknown agent reference(s) found"
    errors=$((errors + 1))
  fi

  # Check 5: YAML is parseable (if python3 available)
  if command -v python3 &>/dev/null; then
    if timeout 10 python3 -c "
import sys
try:
    import yaml
    with open('$OUTPUT') as f:
        yaml.safe_load(f)
    sys.exit(0)
except ImportError:
    sys.exit(2)
except Exception as e:
    print(str(e))
    sys.exit(1)
" 2>/dev/null; then
      ok "  [OK] Output is valid YAML"
    elif [[ $? -eq 2 ]]; then
      warn "  [!!] PyYAML not available — cannot validate YAML strictly"
    else
      err "  [ERR] Output is invalid YAML"
      errors=$((errors + 1))
    fi
  fi

  echo ""
  if [[ $errors -eq 0 ]]; then
    echo "[OK] Validation passed"
  else
    echo "[WARN] $errors issue(s) found"
  fi
fi
