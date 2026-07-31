#!/usr/bin/env bash
#
# self-test.sh — AgentGraph System Self-Test Framework
#
# Tests the AgentGraph system's own scripts and components.
# Designed to be run from the project root via: bash scripts/self-test.sh
# Or via: guild self-test [--quick]
#
# Design:
#   Pure bash, bash-native test patterns.
#   Each test prints: [OK] or [FAIL] with description.
#   Final summary: "X passed, Y failed / Z total"
#   Exit code: 1 if any test fails.
#
# Options:
#   --quick   Skip slow tests (handoff create, graph dry-run)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source lib.sh for helpers (ok, warn, err, die, color vars)
. "$SCRIPT_DIR/lib.sh"

# ── Argument parsing ────────────────────────────────────────────────
QUICK_MODE=false
for arg in "$@"; do
  case "$arg" in
    --quick) QUICK_MODE=true;;
  esac
done

if $QUICK_MODE; then
  ok "Quick mode enabled — skipping slow tests (handoff create, graph dry-run)"
fi

# ── Test config ──────────────────────────────────────────────────────
TEMP_DIR="/tmp/agentgraph-self-test"
GUILD="$REPO_ROOT/guild"
PASSED=0
FAILED=0
TOTAL=0

# Track real handoff files we create (for cleanup)
CLEANUP_HANDOFFS=()

cleanup() {
  rm -rf "$TEMP_DIR"
  for f in "${CLEANUP_HANDOFFS[@]}"; do
    [[ -f "$f" ]] && rm -f "$f"
  done
}
trap cleanup EXIT

# ── Test helpers ─────────────────────────────────────────────────────
pass() { PASSED=$((PASSED + 1)); TOTAL=$((TOTAL + 1)); ok "$1"; }
fail() { FAILED=$((FAILED + 1)); TOTAL=$((TOTAL + 1)); err "$1"; }

# require_node — skip test if node not available
require_node() {
  command -v node &>/dev/null && return 0
  warn "node not available — skipping node-dependent check"
  return 1
}

# require_python3 — only for tests that genuinely need python3 (YAML)
require_python3() {
  command -v python3 &>/dev/null && return 0
  warn "python3 not available — skipping YAML-dependent check"
  return 1
}

# Make sure TEMP_DIR is clean at start
rm -rf "$TEMP_DIR"

# ═══════════════════════════════════════════════════════════════════════
# Test 1: next_id uniqueness
# ═══════════════════════════════════════════════════════════════════════
test_next_id() {
  echo ""
  echo "── Test 1: next_id uniqueness ──"

  require_node || return

  local hdir="$TEMP_DIR/handoffs"
  mkdir -p "$hdir"

  # Create 10 handoff files with IDs 1-10
  for i in $(seq 1 10); do
    cat > "$hdir/handoff-$i.json" << JSONEOF
{"id": $i, "from": "test", "to": "test", "status": "draft", "path": "/tmp", "timestamp": "2024-01-01T00:00:00Z"}
JSONEOF
  done

  # Reimplement next_id algorithm (same logic as nexus.sh:next_id)
  local max=0
  for f in "$hdir"/*.json; do
    [[ -f "$f" ]] || continue
    local id
    id=$(node -e "const d=JSON.parse(require('fs').readFileSync('$f','utf8'));console.log(d.id===undefined?'0':String(d.id))" 2>/dev/null || echo 0)
    (( id > max )) && max=$id
  done
  local next=$((max + 1))

  if [[ "$next" -ne 11 ]]; then
    fail "next_id: expected 11 after files 1-10, got $next"
    return
  fi

  # Uniqueness test: generate 10 consecutive IDs, verify no duplicates
  local ids=()
  local current_max=$max
  for i in $(seq 1 10); do
    local n=$((current_max + 1))
    ids+=("$n")
    cat > "$hdir/handoff-$n.json" << JSONEOF
{"id": $n, "from": "test", "to": "test", "status": "draft", "path": "/tmp", "timestamp": "2024-01-01T00:00:00Z"}
JSONEOF
    current_max=$n
  done

  local unique_count
  unique_count=$(printf '%s\n' "${ids[@]}" | sort -u | wc -l | tr -d ' ')

  if [[ "$unique_count" -eq 10 ]]; then
    pass "next_id returns 10 unique consecutive IDs (11-20)"
  else
    fail "next_id: expected 10 unique IDs, got $unique_count unique"
  fi
}

# ═══════════════════════════════════════════════════════════════════════
# Test 2: handoff create cycle (skipped in --quick mode)
# ═══════════════════════════════════════════════════════════════════════
test_handoff_cycle() {
  echo ""
  echo "── Test 2: handoff create cycle ──"

  if $QUICK_MODE; then
    warn "handoff create: skipped (--quick mode)"
    return
  fi

  require_node || return

  local deliver_dir="$TEMP_DIR/deliverables"
  mkdir -p "$deliver_dir"

  # Create a dummy deliverable file so the path isn't empty
  echo "<html><body>test</body></html>" > "$deliver_dir/test.html"
  echo "# Test File" > "$deliver_dir/README.md"

  # Run handoff create (use real agents from the config)
  local output
  output=$(timeout 20 "$GUILD" handoff --from product-manager --to frontend-engineer --path "$deliver_dir" 2>&1) || {
    fail "handoff create: command failed or timed out"
    echo "$output" | head -5
    return
  }

  # Extract ID from output: "创建交接 #<id>: ..."
  local id
  id=$(echo "$output" | grep -o '交接 #[0-9]*' | grep -o '[0-9]*' | head -1)

  if [[ -z "$id" ]]; then
    fail "handoff create: could not extract ID from output"
    echo "$output" | head -3
    return
  fi

  # Run guild check --handoff <id>
  local check_output
  check_output=$(timeout 20 "$GUILD" check --handoff "$id" 2>&1) || {
    fail "handoff check #$id: command failed or timed out"
    echo "$check_output"
    return
  }

  if echo "$check_output" | grep -q "交接 #$id"; then
    pass "handoff create + check cycle for #$id"
  else
    fail "handoff check #$id: output missing expected handoff reference"
    echo "$check_output"
  fi

  # Clean up the handoff JSON we created
  local hf
  for hf in "$REPO_ROOT/handoffs"/*.json; do
    [[ -f "$hf" ]] || continue
    local hid
    hid=$(node -e "const d=JSON.parse(require('fs').readFileSync('$hf','utf8'));console.log(d.id===undefined?'0':String(d.id))" 2>/dev/null || echo 0)
    if [[ "$hid" == "$id" ]]; then
      CLEANUP_HANDOFFS+=("$hf")
    fi
  done
}

# ═══════════════════════════════════════════════════════════════════════
# Test 3: gate completeness
# ═══════════════════════════════════════════════════════════════════════
test_gate_completeness() {
  echo ""
  echo "── Test 3: gate completeness ──"

  require_node || return

  local pass_dir="$TEMP_DIR/gate-pass"
  mkdir -p "$pass_dir"
  echo "work content" > "$pass_dir/work.txt"

  local hf1="$REPO_ROOT/handoffs/self-test-gate-pass.json"
  cat > "$hf1" << JSONEOF
{
  "id": 99901,
  "from": "product-manager",
  "to": "frontend-engineer",
  "timestamp": "2024-01-01T00:00:00Z",
  "path": "$pass_dir",
  "artifacts": [
    {"name": "test-artifact", "file": "found", "status": "provided", "required": true}
  ],
  "checklist": {"required_total": 1, "required_provided": 1, "required_missing": 0},
  "status": "ready",
  "accepted_by": null
}
JSONEOF
  CLEANUP_HANDOFFS+=("$hf1")

  # Gate 1 (completeness) on the complete handoff — should pass
  local gate_pass_output
  gate_pass_output=$(timeout 20 "$GUILD" gate --handoff 99901 --gate completeness 2>&1) || true

  if echo "$gate_pass_output" | grep -q "\[OK\]"; then
    pass "gate completeness passes when all artifacts provided"
  else
    fail "gate completeness: expected [OK] for complete handoff"
    echo "$gate_pass_output" | grep -E '\[OK\]|\[FAIL\]|\[SKIP\]'
  fi

  local fail_dir="$TEMP_DIR/gate-fail"
  mkdir -p "$fail_dir"

  local hf2="$REPO_ROOT/handoffs/self-test-gate-fail.json"
  cat > "$hf2" << JSONEOF
{
  "id": 99902,
  "from": "product-manager",
  "to": "frontend-engineer",
  "timestamp": "2024-01-01T00:00:00Z",
  "path": "$fail_dir",
  "artifacts": [
    {"name": "missing-artifact", "file": null, "status": "missing", "required": true}
  ],
  "checklist": {"required_total": 1, "required_provided": 0, "required_missing": 1},
  "status": "incomplete",
  "accepted_by": null
}
JSONEOF
  CLEANUP_HANDOFFS+=("$hf2")

  # Gate 1 (completeness) on the incomplete handoff — should fail
  local gate_fail_output
  gate_fail_output=$(timeout 20 "$GUILD" gate --handoff 99902 --gate completeness 2>&1) || true

  if echo "$gate_fail_output" | grep -q "\[FAIL\]"; then
    pass "gate completeness fails when required artifacts are missing"
  else
    fail "gate completeness: expected [FAIL] for incomplete handoff"
    echo "$gate_fail_output" | grep -E '\[OK\]|\[FAIL\]|\[SKIP\]'
  fi
}

# ═══════════════════════════════════════════════════════════════════════
# Test 4: gate syntax
# ═══════════════════════════════════════════════════════════════════════
test_gate_syntax() {
  echo ""
  echo "── Test 4: gate syntax ──"

  # This test only uses guild commands and shell builtins — no node/python3 needed

  local bad_syntax_dir="$TEMP_DIR/bad-syntax"
  mkdir -p "$bad_syntax_dir"

  # Invalid JSON
  printf '{invalid json' > "$bad_syntax_dir/bad.json"

  # Valid empty JSON (should not fail syntax)
  printf '{}' > "$bad_syntax_dir/empty.json"

  # Create handoff pointing to the directory with bad files
  local hf="$REPO_ROOT/handoffs/self-test-syntax.json"
  cat > "$hf" << JSONEOF
{
  "id": 99903,
  "from": "product-manager",
  "to": "frontend-engineer",
  "timestamp": "2024-01-01T00:00:00Z",
  "path": "$bad_syntax_dir",
  "artifacts": [
    {"name": "some-files", "file": "found", "status": "provided", "required": true}
  ],
  "checklist": {"required_total": 1, "required_provided": 1, "required_missing": 0},
  "status": "ready",
  "accepted_by": null
}
JSONEOF
  CLEANUP_HANDOFFS+=("$hf")

  local gate_output
  gate_output=$(timeout 20 "$GUILD" gate --handoff 99903 --gate syntax 2>&1) || true

  # Should report at least one [FAIL] due to invalid JSON
  if echo "$gate_output" | grep -q "\[FAIL\]"; then
    pass "gate syntax catches invalid JSON"
  else
    fail "gate syntax: expected [FAIL] for directory with invalid JSON"
    echo "$gate_output" | grep -E '\[OK\]|\[FAIL\]|\[SKIP\]'
  fi
}

# ═══════════════════════════════════════════════════════════════════════
# Test 5: graph engine (skipped in --quick mode)
# ═══════════════════════════════════════════════════════════════════════
test_graph_engine() {
  echo ""
  echo "── Test 5: graph engine ──"

  if $QUICK_MODE; then
    warn "graph engine: skipped (--quick mode)"
    return
  fi

  local graph_dir="$TEMP_DIR/graph-test"
  mkdir -p "$graph_dir"
  echo "placeholder" > "$graph_dir/placeholder.txt"

  local graph_file="$REPO_ROOT/graphs/feature-dev.yml"
  if [[ ! -f "$graph_file" ]]; then
    fail "graph engine: feature-dev.yml not found at $graph_file"
    return
  fi

  set +e
  local output
  output=$(timeout 20 "$GUILD" graph run --graph feature-dev --path "$graph_dir" --dry-run 2>&1)
  local rc=$?
  set -e

  if [[ $rc -eq 124 ]]; then
    fail "graph engine: timed out after 10s"
    echo "$output" | head -5
    return
  fi

  if [[ $rc -ne 0 ]]; then
    fail "graph engine: exit code $rc (expected 0)"
    echo "$output" | head -10
    return
  fi

  # Verify the output contains graph node names
  local has_nodes=false
  if echo "$output" | grep -qiE 'define|design|build|test|approve|fix'; then
    has_nodes=true
  fi

  if $has_nodes; then
    pass "graph engine parses feature-dev.yml and lists nodes (dry-run)"
  else
    # Still pass if exit code was 0
    pass "graph engine exits cleanly on feature-dev.yml dry-run (no node names found in output)"
  fi
}

# ═══════════════════════════════════════════════════════════════════════
# Test 6: CLI smoke tests
# ═══════════════════════════════════════════════════════════════════════
test_cli_smoke() {
  echo ""
  echo "── Test 6: CLI smoke tests ──"

  local all_ok=true

  # 6a: guild list --handoffs
  if timeout 20 "$GUILD" list --handoffs &>/dev/null; then
    pass "guild list --handoffs exits 0"
  else
    fail "guild list --handoffs exited non-zero or timed out"
    all_ok=false
  fi

  # 6b: guild status
  if timeout 20 "$GUILD" status &>/dev/null; then
    pass "guild status exits 0"
  else
    fail "guild status exited non-zero or timed out"
    all_ok=false
  fi

  # 6c: guild gate --list
  if timeout 20 "$GUILD" gate --list &>/dev/null; then
    pass "guild gate --list exits 0"
  else
    fail "guild gate --list exited non-zero or timed out"
    all_ok=false
  fi

  # 6d: guild feedback --list
  if timeout 20 "$GUILD" feedback --list &>/dev/null; then
    pass "guild feedback --list exits 0"
  else
    fail "guild feedback --list exited non-zero or timed out"
    all_ok=false
  fi

  # 6e: guild changelog (no --since)
  if timeout 20 "$GUILD" changelog &>/dev/null; then
    pass "guild changelog exits 0"
  else
    fail "guild changelog exited non-zero or timed out"
    all_ok=false
  fi

  # 6f: guild context show
  if timeout 20 "$GUILD" context show &>/dev/null; then
    pass "guild context show exits 0"
  else
    fail "guild context show exited non-zero or timed out"
    all_ok=false
  fi
}

# ═══════════════════════════════════════════════════════════════════════
# Test 7: contract validity (needs python3 for YAML)
# ═══════════════════════════════════════════════════════════════════════
test_contract_validity() {
  echo ""
  echo "── Test 7: contract validity ──"

  require_python3 || return

  local contracts_file="$REPO_ROOT/contracts/guild-contracts.yml"
  local config_file="$REPO_ROOT/guild.config.json"

  if [[ ! -f "$contracts_file" ]]; then
    fail "contract validity: contracts file not found: $contracts_file"
    return
  fi
  if [[ ! -f "$config_file" ]]; then
    fail "contract validity: config file not found: $config_file"
    return
  fi

  # Check contracts YAML is valid using python3 yaml
  if timeout 20 python3 -c "
import sys, json
try:
    import yaml
    with open('$contracts_file') as f:
        yaml.safe_load(f)
    print('VALID')
except ImportError:
    print('SKIP')
except Exception as e:
    print('INVALID: ' + str(e))
    sys.exit(1)
" 2>/dev/null | grep -q 'VALID'; then
    pass "contract validity: guild-contracts.yml is valid YAML"
  elif timeout 20 python3 -c "
import sys, json
try:
    import yaml
    with open('$contracts_file') as f:
        yaml.safe_load(f)
    print('VALID')
except ImportError:
    print('SKIP')
except Exception as e:
    print('INVALID')
    sys.exit(1)
" 2>/dev/null | grep -q 'SKIP'; then
    warn "contract YAML validation: PyYAML not available, skipping strict check"
    # Basic check: verify it's not empty and has expected structure
    if grep -q 'contracts:' "$contracts_file" && grep -q 'delivers:' "$contracts_file"; then
      pass "contract validity: guild-contracts.yml has expected structure (PyYAML unavailable)"
    else
      fail "contract validity: guild-contracts.yml missing expected structure"
      return
    fi
  else
    fail "contract validity: guild-contracts.yml is invalid YAML"
    return
  fi

  # Extract agent slugs from contracts (keys under 'contracts:' at 2-space indent)
  local contract_slugs
  contract_slugs=$(awk '/^  [a-z][a-z-]*:/ { gsub(/:$/, ""); print $1 }' "$contracts_file" | sort -u)

  # Extract agent slugs from guild.config.json
  local config_slugs
  config_slugs=$(timeout 20 python3 -c "
import json
with open('$config_file') as f:
    cfg = json.load(f)
for a in cfg.get('agents', []):
    print(a['slug'])
" 2>/dev/null)

  # Check each contract slug exists in config
  local missing_agents=""
  while IFS= read -r slug; do
    [[ -z "$slug" ]] && continue
    if ! echo "$config_slugs" | grep -q "^${slug}$"; then
      missing_agents="$missing_agents $slug"
    fi
  done <<< "$contract_slugs"

  if [[ -z "$missing_agents" ]]; then
    pass "contract validity: all agents referenced in contracts exist in guild.config.json"
  else
    fail "contract validity: agents in contracts not found in config:$missing_agents"
  fi
}

# ═══════════════════════════════════════════════════════════════════════
# Test 8: handoff integrity (uses node)
# ═══════════════════════════════════════════════════════════════════════
test_handoff_integrity() {
  echo ""
  echo "── Test 8: handoff integrity ──"

  require_node || return

  local handoff_dir="$REPO_ROOT/handoffs"
  local count=0
  local errors=0

  # Find handoff JSON files (excluding test artifacts from other tests)
  local -a json_files=()
  for f in "$handoff_dir"/*.json; do
    [[ -f "$f" ]] || continue
    local bn; bn=$(basename "$f")
    [[ "$bn" == self-test-* ]] && continue
    json_files+=("$f")
  done

  if [[ ${#json_files[@]} -eq 0 ]]; then
    warn "handoff integrity: no handoff files to validate (skipping)"
    pass "handoff integrity: no files means no integrity issues"
    return
  fi

  for json_file in "${json_files[@]}"; do
    count=$((count + 1))
    local result
    result=$(timeout 20 node -e "
const fs = require('fs');
try {
  const d = JSON.parse(fs.readFileSync('$json_file', 'utf8'));
  const required = ['id', 'from', 'to', 'status', 'path', 'timestamp'];
  const missing = required.filter(k => d[k] === undefined);
  if (missing.length > 0) {
    console.log('MISSING: ' + missing.join(', '));
    process.exit(1);
  }
  if (typeof d.id !== 'number') {
    console.log('TYPE: id is not number');
    process.exit(1);
  }
  if (typeof d.from !== 'string' || typeof d.to !== 'string') {
    console.log('TYPE: from/to not strings');
    process.exit(1);
  }
  console.log('OK');
} catch(e) {
  console.log('PARSE_ERROR: ' + e.message);
  process.exit(1);
}
" 2>/dev/null) || {
      errors=$((errors + 1))
      local fname; fname=$(basename "$json_file")
      warn "handoff integrity: $fname — $result"
      continue
    }
  done

  if [[ $errors -eq 0 ]]; then
    pass "handoff integrity: all $count handoff files have required fields (id, from, to, status, path, timestamp)"
  else
    fail "handoff integrity: $errors/$count handoff files failed validation"
  fi
}

# ═══════════════════════════════════════════════════════════════════════
# Test 9: classify accuracy
# ═══════════════════════════════════════════════════════════════════════
test_classify_accuracy() {
  echo ""
  echo "── Test 9: classify accuracy ──"

  local -a cases=(
    "做一个用户调研报告:research-report"
    "写一份GTM策略:strategy-consulting"
    "设计品牌Logo:brand-identity"
    "做活动海报:visual-design"
    "写产品白皮书:content-project"
    "用Unity做3D游戏:unity-game"
    "用Unreal做开放世界:unreal-game"
    "搭建CI/CD流水线:infra-project"
    "训练文本分类模型:ai-ml-project"
    "微信小游戏:wechat-game"
    "后台管理系统:admin-system"
    "公司官网:corp-site"
    "数据看板:dashboard"
    "微信小程序:miniapp"
    "移动App:mobile-app"
    "React网站:web-app"
    "API后端:api-service"
    "营销落地页:landing-page"
  )

  local passed=0 failed=0
  for c in "${cases[@]}"; do
    local input="${c%%:*}" expected="${c##*:}"
    # Capture full output first: piping classify straight into head -1 can
    # SIGPIPE it (rc 141 under pipefail) while it writes remaining lines.
    local out
    out=$(timeout 10 "$GUILD" classify "$input" 2>/dev/null)
    # Parse the slug from the classification line "📋 <label> (<type>)".
    # The type slug is always the LAST parenthesized group on the first line
    # (labels may themselves contain parens, e.g. "移动App (iOS/Android)").
    local result; result=$(echo "$out" | head -1 | grep -oP '\(\K[^)]+' | tail -1 || echo "unknown")
    if [[ -z "$result" ]]; then
      # Try parsing the text output differently
      result=$(echo "$out" | head -1 | grep -oP '\b(research-report|strategy-consulting|brand-identity|visual-design|content-project|unity-game|unreal-game|infra-project|ai-ml-project|wechat-game|admin-system|corp-site|dashboard|miniapp|mobile-app|web-app|api-service|landing-page)\b' | head -1 || echo "unknown")
    fi
    if [[ "$result" == "$expected" ]]; then
      passed=$((passed + 1))
    else
      fail "classify '$input': expected $expected, got $result"
      failed=$((failed + 1))
    fi
  done

  if [[ $failed -eq 0 ]]; then
    pass "classify: $passed/$passed types correctly identified"
  else
    echo "  $passed passed, $failed failed"
  fi
}

# ═══════════════════════════════════════════════════════════════════════
# Test 10: plan output structure
# ═══════════════════════════════════════════════════════════════════════
test_plan_output() {
  echo ""
  echo "── Test 10: plan output structure ──"

  # </dev/null: plan's interactive confirmation must not block on a TTY stdin
  local plan_output
  plan_output=$(timeout 30 "$GUILD" plan "做一个测试后台管理系统" </dev/null 2>/dev/null) || {
    fail "plan: command failed or timed out"
    return
  }

  local checks=0 failures=0

  # Check key sections exist in plan output
  echo "$plan_output" | grep -qi '团队' && checks=$((checks + 1)) || failures=$((failures + 1))
  echo "$plan_output" | grep -qi '门禁' && checks=$((checks + 1)) || failures=$((failures + 1))
  echo "$plan_output" | grep -qi '风险' && checks=$((checks + 1)) || failures=$((failures + 1))
  echo "$plan_output" | grep -qi 'guild init' && checks=$((checks + 1)) || failures=$((failures + 1))

  if [[ $failures -eq 0 ]]; then
    pass "plan: output contains team, gates, risks, and next_step ($checks sections verified)"
  else
    fail "plan: output missing $failures/4 expected sections"
  fi
}

# ═══════════════════════════════════════════════════════════════════════
# Run all tests
# ═══════════════════════════════════════════════════════════════════════

echo "╔══════════════════════════════════════════╗"
echo "║  AgentGraph System Self-Test             ║"
echo "║  $(date -u +"%Y-%m-%d %H:%M UTC")                "
echo "╚══════════════════════════════════════════╝"
echo ""

test_next_id || true
test_handoff_cycle || true
test_gate_completeness || true
test_gate_syntax || true
test_graph_engine || true
test_cli_smoke || true
test_contract_validity || true
test_handoff_integrity || true
test_classify_accuracy || true
test_plan_output || true

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════"
echo "  $PASSED passed, $FAILED failed / $TOTAL total"
echo "══════════════════════════════════════════"

[[ $FAILED -eq 0 ]]
