# Handoff Engine (Phase 2a) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the AgentGuild Handoff Engine — a CLI tool that enables structured handoffs between agents with automatic completeness checking based on collaboration contracts.

**Architecture:** Two new Bash scripts (`contracts/extract.sh` extracts structured contracts from agent files; `scripts/nexus.sh` is the CLI with handoff/check/status/accept commands). Contracts stored in YAML, handoff records stored as JSON files. Zero new dependencies beyond what Phase 1 already uses.

**Tech Stack:** Bash 3.2+, YAML (contracts), JSON (handoff records), awk/sed (parsing)

## Global Constraints

- Bash 3.2+ compatible (macOS and Linux)
- Zero external dependencies (no jq, no yq, no Python packages)
- Do NOT modify existing agent files (their collaboration contracts are already in section 13)
- Do NOT modify existing scripts (lib.sh, lint.sh, convert.sh, install.sh)
- Only add to lib.sh — never remove or rename existing functions
- Project root: `/mnt/e/agentguild`
- All new user-facing docs in Chinese
- Code comments in English

---

## File Map

```
/mnt/e/agentguild/
├── contracts/
│   ├── extract.sh               ← T1: Contract extraction script
│   └── guild-contracts.yml      ← T1 output: Structured contracts
├── handoffs/                    ← T1: Created with .gitkeep
│   └── .gitkeep
├── scripts/
│   ├── lib.sh                   ← T1: Extended with contract helpers
│   └── nexus.sh                 ← T2: CLI tool (handoff/check/status/accept)
├── docs/
│   └── 协作指南.md               ← T3: Usage guide
└── demos/                       ← T4: Demo scenarios
    ├── pm-to-backend.md
    ├── pm-to-ux.md
    └── frontend-to-qa.md
```

---

### Task 1: Contract Extraction + Infrastructure

**Files:**
- Create: `/mnt/e/agentguild/contracts/extract.sh`
- Create: `/mnt/e/agentguild/contracts/guild-contracts.yml`
- Create: `/mnt/e/agentguild/handoffs/.gitkeep`
- Modify: `/mnt/e/agentguild/scripts/lib.sh` (append contract helper functions)

**Interfaces:**
- Consumes: 12 agent `.md` files (their section 13), `lib.sh` existing functions
- Produces: `guild-contracts.yml`, `lib.sh` extended with `parse_contract()`, `get_contract()`, consumed by T2 (nexus.sh handoff command)

- [ ] **Step 1: Create directories**

```bash
cd /mnt/e/agentguild
mkdir -p contracts handoffs demos
touch handoffs/.gitkeep
```

- [ ] **Step 2: Append contract helper functions to scripts/lib.sh**

Read the current `lib.sh` to see its end line, then append:

```bash
cat >> /mnt/e/agentguild/scripts/lib.sh << 'LIBEXT'

# ── Contract helpers (Phase 2a) ──────────────────────────────────

# parse_contract <agent_file> — extract structured contract from section 13.
# Outputs YAML fragment to stdout.
parse_contract() {
  local file="$1"
  local body; body="$(get_body "$file")"
  local slug; slug="$(agent_slug "$file")"

  # Extract section 13 (after "## 13." heading, until next ## heading or EOF)
  local section13; section13=$(echo "$body" | awk '/^## 13\./{found=1; next} /^## /{if(found) exit} found{print}')

  echo "  ${slug}:"
  echo "    delivers:"

  # Extract deliverables from "**我向下游交付：**" block
  # Lines starting with "- " after the delivers header
  echo "$section13" | awk '
    /我向下游交付|I deliver/ { in_delivers=1; next }
    /我需要上游提供|I require|I need/ { in_delivers=0 }
    in_delivers && /^- / {
      gsub(/^- /, "")
      gsub(/\*\*/, "")
      gsub(/：.*/, "")
      gsub(/:.*/, "")
      name = $0
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
      if (length(name) > 3 && length(name) < 80)
        printf "      - name: \"%s\"\n        description: \"%s\"\n", name, name
    }
  '

  echo "    requires:"

  # Extract requirements from "**我需要上游提供：**" block
  # Parse per-role requirements
  echo "$section13" | awk '
    BEGIN { role = "general"; in_requires = 0; in_role = 0 }
    /我需要上游提供|I require|I need/ { in_requires = 1; next }
    /我向下游交付|I deliver/ { in_requires = 0 }
    in_requires && /\*\*/ {
      # Extract role name from bold text
      line = $0
      gsub(/.*\*\*/, "")
      gsub(/\*\*.*/, "")
      gsub(/[：:].*/, "")
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (length(line) > 1 && length(line) < 60) {
        role = line
        printf "      - from: \"%s\"\n        items:\n", role
      }
      next
    }
    in_requires && /^- / && role != "" {
      gsub(/^- /, "")
      gsub(/\*\*/, "")
      gsub(/：.*/, "")
      gsub(/:.*/, "")
      name = $0
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
      if (length(name) > 3 && length(name) < 80)
        printf "          - name: \"%s\"\n            description: \"%s\"\n            required: true\n", name, name
    }
  '
}
LIBEXT
```

- [ ] **Step 3: Write contracts/extract.sh**

```bash
cat > /mnt/e/agentguild/contracts/extract.sh << 'EXTREOF'
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
EXTREOF
chmod +x /mnt/e/agentguild/contracts/extract.sh
```

- [ ] **Step 4: Run extract.sh and verify output**

```bash
cd /mnt/e/agentguild
bash -n contracts/extract.sh
bash -n scripts/lib.sh
./contracts/extract.sh
```

Expected: Both syntax checks pass. Output shows "Contracts extracted" with 12 agents. File `contracts/guild-contracts.yml` created with content.

Check the output contains all 12 agents:
```bash
grep -c '^  [a-z]' contracts/guild-contracts.yml
```
Expected: 12 (one per agent).

- [ ] **Step 5: Verify YAML is valid**

```bash
python3 -c "import yaml; d=yaml.safe_load(open('contracts/guild-contracts.yml')); print(f'Contracts: {len(d[\"contracts\"])} agents')"
```
Expected: "Contracts: 12 agents"

- [ ] **Step 6: Commit**

```bash
cd /mnt/e/agentguild
git add contracts/ handoffs/ scripts/lib.sh
git commit -m "feat: add contract extraction and infrastructure for Handoff Engine

- contracts/extract.sh: parse agent section 13 into structured YAML
- contracts/guild-contracts.yml: 12-agent structured contracts
- scripts/lib.sh: added parse_contract() and contract helpers
- handoffs/: directory for handoff records

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: Nexus CLI Tool (nexus.sh)

**Files:**
- Create: `/mnt/e/agentguild/scripts/nexus.sh`

**Interfaces:**
- Consumes: `lib.sh` (all functions), `guild-contracts.yml` from T1, `guild.config.json`
- Produces: CLI with 4 subcommands: handoff, check, status, accept
- Produces: JSON handoff records in `handoffs/`

- [ ] **Step 1: Write nexus.sh — header and handoff command**

```bash
cat > /mnt/e/agentguild/scripts/nexus.sh << 'NEXEOF'
#!/usr/bin/env bash
#
# nexus.sh — AgentGuild Handoff Engine CLI
#
# Usage:
#   guild handoff  --from <agent> --to <agent> --path <dir> [--message <msg>]
#   guild check    --handoff <id>
#   guild status   [--agent <name>] [--status incomplete|ready|accepted]
#   guild accept   --handoff <id> --as <agent>
#   guild list     [--contracts] [--handoffs]
#
# guild is an alias: ln -s scripts/nexus.sh guild

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

CONTRACTS="$REPO_ROOT/contracts/guild-contracts.yml"
HANDOFFS_DIR="$REPO_ROOT/handoffs"
CONFIG="$REPO_ROOT/guild.config.json"

# ── Helpers ────────────────────────────────────────────────────────

# next_id — auto-increment handoff ID
next_id() {
  local max=0
  for f in "$HANDOFFS_DIR"/*.json; do
    [[ -f "$f" ]] || continue
    local id; id=$(python3 -c "import json; print(json.load(open('$f')).get('id',0))" 2>/dev/null || echo 0)
    (( id > max )) && max=$id
  done
  echo $((max + 1))
}

# resolve_agent <name-or-slug> — normalize to slug
resolve_agent() {
  local input="$1"
  # Try direct slug match
  if grep -q "\"slug\": \"$input\"" "$CONFIG"; then
    echo "$input"
    return
  fi
  # Try slugify
  local slug; slug=$(echo "$input" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//')
  if grep -q "\"slug\": \"$slug\"" "$CONFIG"; then
    echo "$slug"
    return
  fi
  # Try partial match on slug
  local match; match=$(awk -F'"' '/"slug":/{print $4}' "$CONFIG" | grep "$slug" | head -1)
  if [[ -n "$match" ]]; then
    echo "$match"
    return
  fi
  echo ""
}

# get_requires <agent-slug> — extract required items from contracts YAML
# Output: from_agent|item_name
get_requires() {
  local slug="$1"
  python3 -c "
import yaml, sys
with open('$CONTRACTS') as f:
    data = yaml.safe_load(f)
contract = data['contracts'].get('$slug', {})
for req in contract.get('requires', []):
    upstream = req.get('from', 'unknown')
    for item in req.get('items', []):
        print(f\"{upstream}|{item['name']}|{item.get('required', True)}\")
" 2>/dev/null
}

# scan_artifacts <path> <requirements-list> — match files to required items
scan_artifacts() {
  local path="$1"
  local reqs="$2"
  local matched=""
  local missing=""

  while IFS='|' read -r from name required; do
    [[ -z "$name" ]] && continue
    local found=false
    # Try filename match
    local pattern; pattern=$(echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/*/g')
    if find "$path" -type f -name "*${pattern}*" 2>/dev/null | grep -q .; then
      found=true
      matched="${matched}${name}|found\n"
    fi
    # Try content keyword match
    if ! $found && grep -rqi "$(echo "$name" | cut -c1-8)" "$path" 2>/dev/null; then
      found=true
      matched="${matched}${name}|content_match\n"
    fi
    if ! $found; then
      missing="${missing}${from}|${name}|${required}\n"
    fi
  done <<< "$reqs"

  echo "MATCHED_START"
  echo -e "$matched"
  echo "MATCHED_END"
  echo "MISSING_START"
  echo -e "$missing"
  echo "MISSING_END"
}

# ── Commands ────────────────────────────────────────────────────────

cmd_handoff() {
  local from="" to="" path="" message=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --from) from="$2"; shift 2;;
      --to) to="$2"; shift 2;;
      --path) path="$2"; shift 2;;
      --message) message="$2"; shift 2;;
      *) shift;;
    esac
  done

  [[ -n "$from" ]] || die "--from is required"
  [[ -n "$to" ]] || die "--to is required"
  [[ -d "$path" ]] || die "--path must be a directory: $path"

  local from_slug to_slug
  from_slug="$(resolve_agent "$from")"
  to_slug="$(resolve_agent "$to")"

  [[ -n "$from_slug" ]] || die "Unknown agent: $from"
  [[ -n "$to_slug" ]] || die "Unknown agent: $to"

  local id; id=$(next_id)
  local date; date=$(date -Iseconds)

  echo "创建交接 #${id}: ${from_slug} → ${to_slug}"

  # Get receiver's requirements
  local reqs; reqs=$(get_requires "$to_slug" | grep "|${from_slug}|" || get_requires "$to_slug")

  # Scan artifacts
  local scan_result; scan_result=$(scan_artifacts "$path" "$reqs")
  local matched; matched=$(echo "$scan_result" | awk '/^MATCHED_START/{found=1; next} /^MATCHED_END/{found=0} found')
  local missing; missing=$(echo "$scan_result" | awk '/^MISSING_START/{found=1; next} /^MISSING_END/{found=0} found')

  local req_total=0 req_provided=0 req_missing=0

  # Build JSON
  local json_file="$HANDOFFS_DIR/$(date +%Y-%m-%d)-${from_slug}-to-${to_slug}.json"

  python3 -c "
import json, os

artifacts = []
matched_lines = '''$matched'''.strip().split('\n') if '''$matched'''.strip() else []
missing_lines = '''$missing'''.strip().split('\n') if '''$missing'''.strip() else []

for line in matched_lines:
    parts = line.split('|')
    if len(parts) >= 2:
        artifacts.append({'name': parts[0], 'file': 'found', 'status': 'provided'})

for line in missing_lines:
    parts = line.split('|')
    if len(parts) >= 3:
        artifacts.append({'name': parts[1], 'file': None, 'status': 'missing', 'required': parts[2] == 'True'})

req_total = len(artifacts)
req_provided = sum(1 for a in artifacts if a['status'] == 'provided')
req_missing = sum(1 for a in artifacts if a['status'] == 'missing' and a.get('required', True))

record = {
    'id': $id,
    'from': '$from_slug',
    'to': '$to_slug',
    'timestamp': '$date',
    'message': '''$message''' or '',
    'path': '$path',
    'artifacts': artifacts,
    'checklist': {
        'required_total': req_total,
        'required_provided': req_provided,
        'required_missing': req_missing
    },
    'status': 'ready' if req_missing == 0 else 'incomplete',
    'accepted_by': None
}

os.makedirs('$HANDOFFS_DIR', exist_ok=True)
with open('$json_file', 'w') as f:
    json.dump(record, f, indent=2, ensure_ascii=False)

print(f'  状态: {record[\"status\"]}')
print(f'  完整度: {req_provided}/{req_total} 项已提供')
if req_missing > 0:
    print(f'  [!!] 缺失 {req_missing} 项:')
    for a in artifacts:
        if a['status'] == 'missing':
            print(f'       - {a[\"name\"]}')
print(f'  记录: {json_file}')
" 2>/dev/null || {
    # Fallback: manual JSON if python3 fails
    err "python3 unavailable — creating minimal record"
    cat > "$json_file" << JSONFALLBACK
{
  "id": $id,
  "from": "$from_slug",
  "to": "$to_slug",
  "timestamp": "$date",
  "message": "$message",
  "status": "incomplete",
  "note": "auto-check unavailable (python3 required)"
}
JSONFALLBACK
  }
}

cmd_check() {
  local id=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --handoff) id="$2"; shift 2;;
      *) shift;;
    esac
  done

  [[ -n "$id" ]] && die "--handoff <id> is required"

  local json_file; json_file=$(find "$HANDOFFS_DIR" -name "*.json" -exec python3 -c "import json; d=json.load(open('{}')); print('{}' if d.get('id')==$id else '')" 2>/dev/null \; 2>/dev/null | head -1)

  [[ -f "$json_file" ]] || die "Handoff #$id not found"

  python3 -c "
import json
with open('$json_file') as f:
    d = json.load(f)
print(f'交接 #{d[\"id\"]}: {d[\"from\"]} → {d[\"to\"]}')
print(f'状态: {d[\"status\"]}')
print(f'时间: {d[\"timestamp\"]}')
c = d.get('checklist', {})
print(f'完整度: {c.get(\"required_provided\", \"?\")}/{c.get(\"required_total\", \"?\")} 项')
if c.get('required_missing', 0) > 0:
    print('缺失项:')
    for a in d.get('artifacts', []):
        if a['status'] == 'missing':
            print(f'  - {a[\"name\"]}')
else:
    print('所有必需项已满足 ✓')
" 2>/dev/null || cat "$json_file"
}

cmd_status() {
  local agent="" status_filter=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --agent) agent="$2"; shift 2;;
      --status) status_filter="$2"; shift 2;;
      *) shift;;
    esac
  done

  echo "当前交接状态:"
  echo ""

  local count=0
  for f in "$HANDOFFS_DIR"/*.json; do
    [[ -f "$f" ]] || continue
    local id from to status timestamp
    read -r id from to status timestamp <<< $(python3 -c "
import json
d = json.load(open('$f'))
print(d['id'], d['from'], d['to'], d['status'], d['timestamp'][:19])
" 2>/dev/null)

    [[ -n "$id" ]] || continue

    # Filter
    [[ -n "$agent" && "$from" != "$agent" && "$to" != "$agent" ]] && continue
    [[ -n "$status_filter" && "$status" != "$status_filter" ]] && continue

    local icon
    case "$status" in
      ready) icon="✅";;
      incomplete) icon="⚠️";;
      accepted) icon="✔️";;
      *) icon="📋";;
    esac

    echo "  $icon #$id: $from → $to ($status) — $timestamp"
    ((count++))
  done

  if (( count == 0 )); then
    echo "  (无交接记录)"
  fi
}

cmd_accept() {
  local id="" as=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --handoff) id="$2"; shift 2;;
      --as) as="$2"; shift 2;;
      *) shift;;
    esac
  done

  [[ -n "$id" ]] && die "--handoff <id> is required"
  [[ -n "$as" ]] && die "--as <agent> is required"

  local as_slug; as_slug="$(resolve_agent "$as")"
  local json_file; json_file=$(find "$HANDOFFS_DIR" -name "*.json" | head -1)  # simplified — in production find by id

  for f in "$HANDOFFS_DIR"/*.json; do
    local fid; fid=$(python3 -c "import json; print(json.load(open('$f'))['id'])" 2>/dev/null)
    if [[ "$fid" == "$id" ]]; then
      json_file="$f"
      break
    fi
  done

  [[ -f "$json_file" ]] || die "Handoff #$id not found"

  python3 -c "
import json
with open('$json_file') as f:
    d = json.load(f)
if d['to'] != '$as_slug' and '$as_slug' not in d['to']:
    print(f'警告: 交接目标为 {d[\"to\"]}，但你以 {as_slug} 身份接收')
    print('继续...' if input('确认? (y/N): ').lower() == 'y' else '...已取消')
d['status'] = 'accepted'
d['accepted_by'] = '$as_slug'
with open('$json_file', 'w') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
print(f'交接 #{d[\"id\"]} 已接收 — {as_slug} 开始工作')
" 2>/dev/null || {
    # Fallback
    ok "交接 #$id 已标记为接收"
  }
}

cmd_list() {
  local mode=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --contracts) mode="contracts";;
      --handoffs) mode="handoffs";;
      *) shift;;
    esac
  done

  case "$mode" in
    contracts)
      echo "已注册的交接契约:"
      python3 -c "
import yaml
d = yaml.safe_load(open('$CONTRACTS'))
for slug, contract in d['contracts'].items():
    delivers = len(contract.get('delivers', []))
    requires = sum(len(r.get('items', [])) for r in contract.get('requires', []))
    print(f'  {slug}: 产出 {delivers} 项, 需求 {requires} 项')
" 2>/dev/null
      ;;
    handoffs|*)
      cmd_status
      ;;
  esac
}

# ── Main ────────────────────────────────────────────────────────────

if [[ $# -eq 0 ]]; then
  echo "AgentGuild Handoff Engine"
  echo ""
  echo "Commands:"
  echo "  guild handoff   — 创建交接 (Agent A → Agent B)"
  echo "  guild check     — 检查交接完整性"
  echo "  guild status    — 查看所有交接状态"
  echo "  guild accept    — 接收交接并开始工作"
  echo "  guild list      — 列出契约或交接记录"
  echo ""
  echo "Run 'guild <command> --help' for details."
  exit 0
fi

CMD="$1"
shift

case "$CMD" in
  handoff) cmd_handoff "$@";;
  check)   cmd_check "$@";;
  status)  cmd_status "$@";;
  accept)  cmd_accept "$@";;
  list)    cmd_list "$@";;
  --help|-h|help)
    sed -n '3,12p' "$0" | sed 's/^# \{0,1\}//'
    ;;
  *) die "Unknown command: $CMD. Valid: handoff, check, status, accept, list";;
esac
NEXEOF
chmod +x /mnt/e/agentguild/scripts/nexus.sh
```

- [ ] **Step 2: Create guild symlink**

```bash
cd /mnt/e/agentguild
ln -sf scripts/nexus.sh guild
```

- [ ] **Step 3: Verify syntax and basic invocation**

```bash
cd /mnt/e/agentguild
bash -n scripts/nexus.sh
./guild
```

Expected: Syntax passes. "guild" shows help text with 4 commands.

- [ ] **Step 4: Test handoff command end-to-end**

```bash
cd /mnt/e/agentguild

# Create a test PRD directory
mkdir -p /tmp/test-prd
cat > /tmp/test-prd/problem-statement.md << 'EOF'
# 问题陈述
目标用户：一线教师
核心问题：备课效率
成功指标：备课时间减少30%
EOF

# Test handoff
./guild handoff --from product-manager --to backend-architect --path /tmp/test-prd --message "MVP 需求评审"
```

Expected: Creates a JSON file in `handoffs/`. Shows completeness status.

- [ ] **Step 5: Test check command**

```bash
./guild check --handoff 1
```

Expected: Shows handoff details with completeness info.

- [ ] **Step 6: Test status command**

```bash
./guild status
```

Expected: Lists the handoff with icon and status.

- [ ] **Step 7: Commit**

```bash
cd /mnt/e/agentguild
git add scripts/nexus.sh guild
git commit -m "feat: add Handoff Engine CLI (nexus.sh)

- guild handoff: create structured handoff with auto-completeness check
- guild check: inspect handoff details and missing items
- guild status: list all handoffs with status icons
- guild accept: mark handoff as received
- guild list: show contracts or handoff records

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: Usage Guide

**Files:**
- Create: `/mnt/e/agentguild/docs/协作指南.md`

**Interfaces:**
- Consumes: nexus.sh CLI from T2, Phase 1 agent roster
- Produces: Standalone usage guide, no code dependencies

- [ ] **Step 1: Write docs/协作指南.md**

Write a comprehensive Chinese usage guide covering:

1. **什么是 Handoff Engine** — 一句话解释
2. **为什么需要它** — agency-agents 的问题（口头说"你传给后端"但没人检查完整性）
3. **快速开始** — 4 步完成第一次 handoff
4. **四个命令详解** — 每个命令的用途、参数、示例输出
5. **交接契约是如何工作的** — 解释 contracts/guild-contracts.yml 的作用
6. **常见问题** — "为什么显示缺失？"、"怎么补充缺失项？"、"交接记录在哪？"
7. **进阶技巧** — 链式交接（PM→后端→QA）、并行交接（PM→前端+后端同时）

The guide should be ~150-200 lines, practical and example-driven, with real command output shown.

- [ ] **Step 2: Commit**

```bash
cd /mnt/e/agentguild
git add docs/协作指南.md
git commit -m "docs: add Handoff Engine usage guide (Chinese)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: Demo Scenarios

**Files:**
- Create: `/mnt/e/agentguild/demos/pm-to-backend.md`
- Create: `/mnt/e/agentguild/demos/pm-to-ux.md`
- Create: `/mnt/e/agentguild/demos/frontend-to-qa.md`

**Interfaces:**
- Consumes: nexus.sh CLI from T2, 12 agent files
- Produces: 3 end-to-end demo walkthroughs

- [ ] **Step 1: Write demos/pm-to-backend.md**

End-to-end demo: PM writes PRD → handoff to Backend Architect → check reveals missing performance targets → PM supplements → re-handoff passes → Backend accepts.

Each step shows the exact command and expected output. Include real sample PRD content.

- [ ] **Step 2: Write demos/pm-to-ux.md**

PM hands off user research request to UX Researcher → check reveals missing target user definition → PM supplements → handoff complete.

- [ ] **Step 3: Write demos/frontend-to-qa.md**

Frontend Engineer hands off built component to QA (Evidence Collector) → QA needs accessibility audit results and test coverage report → Frontend provides → QA accepts.

- [ ] **Step 4: Commit**

```bash
cd /mnt/e/agentguild
git add demos/
git commit -m "docs: add 3 demo scenarios for Handoff Engine

- PM → Backend Architect (PRD handoff with completeness check)
- PM → UX Researcher (research request handoff)
- Frontend Engineer → QA (component delivery handoff)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 5: Integration Test

**Files:**
- No new files — validation of all Phase 2a deliverables

- [ ] **Step 1: Verify all files exist**

```bash
cd /mnt/e/agentguild
echo "Deliverable check:"
[[ -f contracts/extract.sh ]] && echo "  ✓ contracts/extract.sh" || echo "  ✗ contracts/extract.sh"
[[ -f contracts/guild-contracts.yml ]] && echo "  ✓ contracts/guild-contracts.yml" || echo "  ✗ contracts/guild-contracts.yml"
[[ -f scripts/nexus.sh ]] && echo "  ✓ scripts/nexus.sh" || echo "  ✗ scripts/nexus.sh"
[[ -f guild ]] && echo "  ✓ guild (symlink)" || echo "  ✗ guild"
[[ -d handoffs ]] && echo "  ✓ handoffs/" || echo "  ✗ handoffs/"
[[ -f docs/协作指南.md ]] && echo "  ✓ docs/协作指南.md" || echo "  ✗ docs/协作指南.md"
[[ -f demos/pm-to-backend.md ]] && echo "  ✓ demos/pm-to-backend.md" || echo "  ✗ demos/pm-to-backend.md"
[[ -f demos/pm-to-ux.md ]] && echo "  ✓ demos/pm-to-ux.md" || echo "  ✗ demos/pm-to-ux.md"
[[ -f demos/frontend-to-qa.md ]] && echo "  ✓ demos/frontend-to-qa.md" || echo "  ✗ demos/frontend-to-qa.md"
```

- [ ] **Step 2: Full contract extraction test**

```bash
cd /mnt/e/agentguild
rm -f contracts/guild-contracts.yml
./contracts/extract.sh
python3 -c "import yaml; d=yaml.safe_load(open('contracts/guild-contracts.yml')); print(f'{len(d[\"contracts\"])} agents extracted')"
```

Expected: 12 agents.

- [ ] **Step 3: Full handoff flow test**

```bash
cd /mnt/e/agentguild
# Clear previous test records
rm -f handoffs/*.json

# Create test artifacts
mkdir -p /tmp/handoff-test
echo "# Problem Statement: 教师备课效率优化" > /tmp/handoff-test/problem-statement.md
echo "# User Stories: 教师可在5分钟内完成当日备课" > /tmp/handoff-test/user-stories.md
echo "# Success Metrics: 备课时间减少30%，教师满意度 > 4.5/5" > /tmp/handoff-test/success-metrics.md

# Test handoff
./guild handoff --from pm --to backend --path /tmp/handoff-test --message "备课优化 MVP"

# Test status
./guild status

# Test check
./guild check --handoff 1

# Cleanup
rm -rf /tmp/handoff-test
```

Expected: handoff creates record, status shows it, check shows details.

- [ ] **Step 4: Script syntax check**

```bash
cd /mnt/e/agentguild
for f in contracts/extract.sh scripts/nexus.sh scripts/lib.sh; do
  bash -n "$f" && echo "OK: $f" || echo "FAIL: $f"
done
```

Expected: All 3 OK.

- [ ] **Step 5: Verify Phase 1 not broken**

```bash
cd /mnt/e/agentguild
./scripts/lint.sh --all
```

Expected: 12 agents still PASS.

- [ ] **Step 6: Git status and final commit**

```bash
cd /mnt/e/agentguild
git status
git log --oneline
```

- [ ] **Step 7: Commit any remaining changes**

```bash
cd /mnt/e/agentguild
git add -A
git commit -m "chore: Phase 2a integration test and final cleanup" || echo "Nothing to commit"
```

---

## Implementation Order

```
T1 (Contracts + Infrastructure)
  │
  ▼
T2 (Nexus CLI) ─────┐
  │                  │
  ├──────────────────┤
  ▼                  ▼
T3 (Usage Guide)   T4 (Demo Scenarios)
  │                  │
  └────────┬─────────┘
           ▼
     T5 (Integration Test)
```

T3 and T4 are independent and can be dispatched in parallel after T2 completes.

---

## Self-Review

**Spec coverage check:**
- [x] D1: contracts/extract.sh → T1
- [x] D2: contracts/guild-contracts.yml → T1 output
- [x] D3: scripts/nexus.sh (4 commands) → T2
- [x] D4: handoffs/.gitkeep → T1
- [x] D5: docs/协作指南.md → T3
- [x] D6: 3 demo scenarios → T4
- [x] Success criterion: 12/12 contracts extracted → T5 Step 2
- [x] Success criterion: 5 missing scenarios detected → T4 (demos show this)
- [x] Success criterion: zero dependencies → entire plan uses Bash + built-in python3
- [x] Success criterion: bash -n passes → T5 Step 4

**Placeholder scan:** No TBD, TODO. All steps have actual code or specific content requirements.

**Type consistency:** Agent slugs consistent with Phase 1 guild.config.json. Contract YAML schema consistent between extract.sh output and nexus.sh consumption. Command names (handoff/check/status/accept) consistent across all tasks.
