#!/usr/bin/env bash
#
# lint.sh — Validate AgentGraph agent files for quality and completeness.
#
# Usage:
#   ./scripts/lint.sh [file1.md file2.md ...]
#   ./scripts/lint.sh --all        # Lint all registered agents
#   ./scripts/lint.sh --check-duplicates  # Check for duplicate Contrarian Takes
#
# Exit code: 0 = pass, 1 = lint errors found.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

CONFIG="$REPO_ROOT/guild.config.json"

# ── Required frontmatter fields ────────────────────────────────────
REQUIRED_FIELDS=(name short role description color emoji difficulty pairing)
# ── Required body sections (checked by heading presence) ────────────
REQUIRED_SECTIONS=(
  "身份与记忆"
  "核心任务"
  "挑衅性观点"
  "铁律"
  "技术交付物"
  "工作流程"
  "交付模板"
  "沟通风格"
  "成功指标"
  "冲突偏好"
  "盲区声明"
  "决策权重"
  "协作契约"
)

ERRORS=0
WARNINGS=0

check_field() {
  local field="$1" file="$2"
  local val; val="$(get_field "$field" "$file")"
  if [[ -z "$val" ]]; then
    err "Missing frontmatter field '$field' in $file"
    ((ERRORS++))
  fi
}

check_section() {
  local section="$1" file="$2"
  if ! grep -qi "$section" "$file"; then
    err "Missing body section '$section' in $file"
    ((ERRORS++))
  fi
}

lint_file() {
  local file="$1"
  local name; name="$(get_field name "$file")"
  echo "Linting: $name ($file)"

  # Check it starts with frontmatter
  if ! is_agent_file "$file"; then
    err "$file does not start with YAML frontmatter (---)"
    ((ERRORS++))
  fi

  # Check required frontmatter fields
  for field in "${REQUIRED_FIELDS[@]}"; do
    check_field "$field" "$file"
  done

  # Check difficulty field is valid
  local diff; diff="$(get_field difficulty "$file")"
  case "$diff" in
    beginner|intermediate|advanced) ;;
    *) err "Invalid difficulty '$diff' in $file (must be: beginner, intermediate, advanced)"; ((ERRORS++)) ;;
  esac

  # Check required body sections
  for section in "${REQUIRED_SECTIONS[@]}"; do
    check_section "$section" "$file"
  done

  # Check contrarian take length (> 200 chars = meaningful)
  local body; body="$(get_body "$file")"
  local ct_start; ct_start=$(echo "$body" | grep -ni "挑衅性观点" | head -1 | cut -d: -f1 || true)
  if [[ -n "$ct_start" ]]; then
    # Skip the section heading line, then collect content until the next ## heading.
    local ct_len; ct_len=$(echo "$body" | tail -n +"$((ct_start + 1))" | awk '/^## /{exit} {print}' | wc -c)
    if (( ct_len < 200 )); then
      warn "Contrarian Take in $file is short ($ct_len chars). Should be at least 200 chars for meaningful insight."
      ((WARNINGS++))
    fi
  fi

  # Check code block present
  if ! echo "$body" | grep -q '```'; then
    err "No code block found in $file"
    ((ERRORS++))
  fi

  # Check pairing slugs exist in config
  local pairings; pairings=$(get_field pairing "$file" | tr -d '[]" ' | tr ',' '\n')
  for p in $pairings; do
    [[ -z "$p" ]] && continue
    if ! grep -q "\"slug\": \"$p\"" "$CONFIG"; then
      err "Pairing '$p' in $file not found in guild.config.json agents"
      ((ERRORS++))
    fi
  done
}

check_duplicates() {
  echo "Checking for duplicate Contrarian Takes..."
  local takes_file; takes_file=$(mktemp)

  for agent_file in $(get_agent_files "$CONFIG"); do
    local slug; slug=$(get_field name "$agent_file" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//')
    local body; body="$(get_body "$agent_file")"
    # Extract Contrarian Take section
    local ct; ct=$(echo "$body" | awk '/挑衅性观点/{found=1; next} /^## /{found=0} found{print}')
    # Compute similarity hash: first 100 normalized chars, no line breaks
    local hash; hash=$(echo "$ct" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g' | head -c 100)
    echo "${hash}|${slug}" >> "$takes_file"
  done

  # Check for near-duplicate hashes
  local dups; dups=$(cut -d'|' -f1 "$takes_file" | sort | uniq -d)
  if [[ -n "$dups" ]]; then
    err "Duplicate or near-duplicate Contrarian Takes detected:"
    while IFS= read -r dup; do
      grep "^${dup}|" "$takes_file" | while IFS='|' read -r _ agent; do
        echo "  - $agent"
      done
    done <<< "$dups"
    ((ERRORS++))
  fi
  rm -f "$takes_file"
}

# ── Main ────────────────────────────────────────────────────────────

LINTED=0
if [[ "${1:-}" == "--all" ]]; then
  while IFS= read -r agent_file; do
    lint_file "$agent_file"
    LINTED=$(( LINTED + 1 ))
  done < <(get_agent_files "$CONFIG")
elif [[ "${1:-}" == "--check-duplicates" ]]; then
  check_duplicates
elif [[ $# -gt 0 ]]; then
  for f in "$@"; do
    [[ -f "$f" ]] || die "File not found: $f"
    lint_file "$f"
    LINTED=$(( LINTED + 1 ))
  done
else
  echo "Usage: $0 [--all | --check-duplicates | file1.md file2.md ...]"
  echo "  --all               Lint all registered agents"
  echo "  --check-duplicates  Check for duplicate Contrarian Takes"
  exit 0
fi

# ── Report ──────────────────────────────────────────────────────────
echo ""
if (( ERRORS > 0 )); then
  echo "FAIL: $ERRORS error(s), $WARNINGS warning(s) across $LINTED file(s)"
  exit 1
elif (( WARNINGS > 0 )); then
  echo "PASS: $WARNINGS warning(s) across $LINTED file(s)"
  exit 0
else
  echo "PASS: $LINTED file(s) clean"
  exit 0
fi
