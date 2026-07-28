#!/usr/bin/env bash
# Module: doctor.sh — cmd_doctor
# Diagnoses system health with structured checks.
# Source guard: only loadable via guild
[[ -n "${_AG_MODULE_SOURCING:-}" ]] || { echo "This module must be loaded via guild, not run directly" >&2; exit 1; }

# ── Doctor check helpers ────────────────────────────────────────────

doctor_pass() { ok "$1"; }
doctor_warn() { warn "$1"; }
doctor_fail() { err "$1"; }

# ── Checks ──────────────────────────────────────────────────────────

# Check 1: guild.config.json is valid JSON
check_config_json() {
  local file="$REPO_ROOT/guild.config.json"
  if [[ ! -f "$file" ]]; then
    doctor_fail "guild.config.json: file not found at $file"
    return 1
  fi
  if json_validate "$file"; then
    doctor_pass "guild.config.json: valid JSON"
    return 0
  else
    doctor_fail "guild.config.json: invalid JSON"
    return 1
  fi
}

# Check 2: All agent .md files exist and have required frontmatter fields
check_agent_files() {
  local total=0 missing=0 missing_fields=0

  # Build a lookup: slug→file in ONE pass (avoid glob inside loop)
  declare -A slug_to_file
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    local s; s=$(basename "$f" .md)
    slug_to_file["$s"]="$f"
  done < <(find "$REPO_ROOT"/agents -name "*.md" -type f 2>/dev/null)

  # Check all slugs from config
  local config_slugs; config_slugs=$(get_agent_slugs "$CONFIG")
  while IFS= read -r slug; do
    [[ -z "$slug" ]] && continue
    total=$((total + 1))
    local f="${slug_to_file[$slug]:-}"
    if [[ -z "$f" ]]; then
      doctor_warn "$slug: agent .md file not found"
      missing=$((missing + 1))
      continue
    fi
    for field in name short role description; do
      local val; val=$(get_field "$field" "$f")
      [[ -z "$val" ]] && { doctor_warn "$slug: missing '$field'"; missing_fields=$((missing_fields + 1)); }
    done
  done <<< "$config_slugs"

  if [[ $missing -eq 0 && $missing_fields -eq 0 ]]; then
    doctor_pass "agent files: all $total agents present"
    return 0
  else
    doctor_warn "agent files: $total checked, $missing missing files, $missing_fields missing fields"
    return 1
  fi
}

# Check 3: contracts/guild-contracts.yml is valid YAML
check_contracts_yaml() {
  local file="$REPO_ROOT/contracts/guild-contracts.yml"
  if [[ ! -f "$file" ]]; then
    doctor_fail "guild-contracts.yml: file not found at $file"
    return 1
  fi

  # Try python3 for YAML validation
  if command -v python3 &>/dev/null; then
    if timeout 10 python3 -c "
import sys
try:
    import yaml
    with open('$file') as f:
        yaml.safe_load(f)
    sys.exit(0)
except ImportError:
    sys.exit(2)
except Exception:
    sys.exit(1)
" 2>/dev/null; then
      doctor_pass "guild-contracts.yml: valid YAML"
      return 0
    elif [[ $? -eq 2 ]]; then
      # PyYAML not available, basic structure check
      if grep -q 'contracts:' "$file" && grep -q 'delivers:' "$file"; then
        doctor_pass "guild-contracts.yml: basic structure OK (PyYAML unavailable)"
        return 0
      else
        doctor_fail "guild-contracts.yml: missing expected structure (contracts:/delivers:)"
        return 1
      fi
    else
      doctor_fail "guild-contracts.yml: invalid YAML"
      return 1
    fi
  else
    # Basic structure check with awk
    if grep -q 'contracts:' "$file" && grep -q 'delivers:' "$file"; then
      doctor_pass "guild-contracts.yml: basic structure OK (python3 unavailable)"
      return 0
    else
      doctor_fail "guild-contracts.yml: missing expected structure"
      return 1
    fi
  fi
}

# Check 4: No duplicate handoff IDs
check_duplicate_ids() {
  local handoff_dir="$REPO_ROOT/handoffs"
  local has_dupes=false

  # Only check if there are handoff files
  local -a json_files=()
  for f in "$handoff_dir"/*.json; do
    [[ -f "$f" ]] || continue
    [[ "$(basename "$f")" == self-test-* ]] && continue
    json_files+=("$f")
  done

  if [[ ${#json_files[@]} -eq 0 ]]; then
    doctor_pass "handoff IDs: no handoff files to check"
    return 0
  fi

  local duplicates
  if command -v node &>/dev/null; then
    duplicates=$(timeout 10 node -e "
const fs = require('fs'), path = require('path');
const dir = '$handoff_dir';
const ids = {};
fs.readdirSync(dir).filter(f => f.endsWith('.json') && !f.startsWith('self-test-')).forEach(f => {
  try {
    const d = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8'));
    const id = d.id;
    if (ids[id] !== undefined) {
      console.log('Duplicate ID ' + id + ': ' + ids[id] + ' and ' + f);
    }
    ids[id] = f;
  } catch(e) { /* skip invalid files */ }
});
" 2>/dev/null)
  else
    # Fallback with bash + python3
    local -A seen_ids
    for f in "${json_files[@]}"; do
      local bn; bn=$(basename "$f")
      local id
      if command -v python3 &>/dev/null; then
        id=$(python3 -c "import json; print(json.load(open('$f')).get('id',0))" 2>/dev/null || echo 0)
      else
        id=$(grep -o '"id"[[:space:]]*:[[:space:]]*[0-9]*' "$f" 2>/dev/null | head -1 | grep -o '[0-9]*' || echo 0)
      fi
      if [[ -n "${seen_ids[$id]:-}" ]]; then
        duplicates="${duplicates}Duplicate ID $id: ${seen_ids[$id]} and $bn"
        has_dupes=true
      fi
      seen_ids[$id]="$bn"
    done
  fi

  if [[ -z "$duplicates" ]]; then
    doctor_pass "handoff IDs: all ${#json_files[@]} files have unique IDs"
    return 0
  else
    while IFS= read -r line; do
      [[ -n "$line" ]] && doctor_warn "$line"
    done <<< "$duplicates"
    return 1
  fi
}

# Check 5: All handoff JSON files are valid
check_handoff_json() {
  local handoff_dir="$REPO_ROOT/handoffs"
  local count=0
  local errors=0

  for f in "$handoff_dir"/*.json; do
    [[ -f "$f" ]] || continue
    [[ "$(basename "$f")" == self-test-* ]] && continue
    count=$((count + 1))
    if ! json_validate "$f"; then
      doctor_warn "handoff JSON: $(basename "$f") is invalid"
      errors=$((errors + 1))
    fi
  done

  if [[ $count -eq 0 ]]; then
    doctor_pass "handoff JSON: no handoff files to validate"
    return 0
  elif [[ $errors -eq 0 ]]; then
    doctor_pass "handoff JSON: all $count files are valid"
    return 0
  else
    doctor_fail "handoff JSON: $errors/$count files are invalid"
    return 1
  fi
}

# Check 6: scripts/modules/ directory has all expected files
check_modules_dir() {
  local modules_dir="$REPO_ROOT/scripts/modules"
  if [[ ! -d "$modules_dir" ]]; then
    doctor_fail "modules directory: not found at $modules_dir"
    return 1
  fi

  local expected_files=("accept.sh" "changelog.sh" "check.sh" "cleanup.sh" "context.sh" "decide.sh" "feedback.sh" "gate.sh" "graph.sh" "handoff.sh" "inbox.sh" "list.sh" "run.sh" "status.sh" "verify.sh")
  local missing=0
  local present=0

  for f in "${expected_files[@]}"; do
    if [[ -f "$modules_dir/$f" ]]; then
      present=$((present + 1))
    else
      doctor_warn "modules: expected $f not found"
      missing=$((missing + 1))
    fi
  done

  if [[ $missing -eq 0 ]]; then
    doctor_pass "modules: all ${#expected_files[@]} expected files present"
    return 0
  else
    doctor_warn "modules: $present present, $missing missing out of ${#expected_files[@]} expected"
    return 1
  fi
}

# Check 7: Git repo is accessible
check_git_repo() {
  if ! command -v git &>/dev/null; then
    doctor_fail "git: not installed"
    return 1
  fi

  if timeout 10 git -C "$REPO_ROOT" status &>/dev/null; then
    local branch
    branch=$(timeout 10 git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    doctor_pass "git repo: accessible on branch '$branch'"
    return 0
  else
    doctor_fail "git repo: not accessible at $REPO_ROOT"
    return 1
  fi
}

# ═══════════════════════════════════════════════════════════════════════
# cmd_doctor — run all health checks
# ═══════════════════════════════════════════════════════════════════════
cmd_doctor() {
  echo "╔══════════════════════════════════════════╗"
  echo "║  AgentGraph System Health Check          ║"
  echo "║  $(date -u +"%Y-%m-%d %H:%M UTC")                "
  echo "╚══════════════════════════════════════════╝"
  echo ""

  local pass_count=0
  warn_count=0
  fail_count=0
  local total=7

  # Run all checks
  echo "── 1/7 Config JSON ──"
  if check_config_json; then pass_count=$((pass_count + 1)); else fail_count=$((fail_count + 1)); fi
  echo ""

  echo "── 2/7 Agent Files ──"
  if check_agent_files; then pass_count=$((pass_count + 1)); else warn_count=$((warn_count + 1)); fi
  echo ""

  echo "── 3/7 Contracts YAML ──"
  if check_contracts_yaml; then pass_count=$((pass_count + 1)); else fail_count=$((fail_count + 1)); fi
  echo ""

  echo "── 4/7 Duplicate Handoff IDs ──"
  if check_duplicate_ids; then pass_count=$((pass_count + 1)); else warn_count=$((warn_count + 1)); fi
  echo ""

  echo "── 5/7 Handoff JSON ──"
  if check_handoff_json; then pass_count=$((pass_count + 1)); else fail_count=$((fail_count + 1)); fi
  echo ""

  echo "── 6/7 Modules Directory ──"
  if check_modules_dir; then pass_count=$((pass_count + 1)); else warn_count=$((warn_count + 1)); fi
  echo ""

  echo "── 7/7 Git Repository ──"
  if check_git_repo; then pass_count=$((pass_count + 1)); else fail_count=$((fail_count + 1)); fi
  echo ""

  # Summary
  echo "══════════════════════════════════════════"
  echo "  [OK] $pass_count/7 checks passed"
  if [[ $warn_count -gt 0 ]]; then
    warn "  [!!] $warn_count checks have warnings"
  fi
  if [[ $fail_count -gt 0 ]]; then
    err "  [ERR] $fail_count checks failed"
  fi
  echo "══════════════════════════════════════════"

  [[ $fail_count -eq 0 ]]
}
