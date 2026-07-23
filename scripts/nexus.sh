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

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
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
    local id
    id=$(python3 -c "import json; print(json.load(open('$f')).get('id',0))" 2>/dev/null || echo 0)
    (( id > max )) && max=$id
  done
  echo $((max + 1))
}

# resolve_agent <name-or-slug> — normalize to slug
# Supports: exact slug, case-insensitive, partial match, abbreviation (pm→product-manager)
resolve_agent() {
  local input="$1"
  local slug

  # Try direct slug match
  if grep -q "\"slug\": \"$input\"" "$CONFIG"; then
    echo "$input"
    return
  fi

  # Try slugify
  slug=$(echo "$input" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//')
  if grep -q "\"slug\": \"$slug\"" "$CONFIG"; then
    echo "$slug"
    return
  fi

  # Try partial match on slug
  local match
  match=$(awk -F'"' '/"slug":/{print $4}' "$CONFIG" | grep "$slug" | head -1)
  if [[ -n "$match" ]]; then
    echo "$match"
    return
  fi

  # Try abbreviation: first letter of each hyphen-separated segment
  # e.g., "pm" matches "product-manager"
  local all_slugs
  all_slugs=$(awk -F'"' '/"slug":/{print $4}' "$CONFIG")
  while IFS= read -r s; do
    [[ -z "$s" ]] && continue
    local abbr=""
    local part
    local saved_ifs="$IFS"
    IFS='-'
    for part in $s; do
      abbr="${abbr}${part:0:1}"
    done
    IFS="$saved_ifs"
    if [[ "$abbr" == "$input" ]]; then
      echo "$s"
      return
    fi
  done <<< "$all_slugs"

  echo ""
}

# get_requires <agent-slug> — extract required items from contracts YAML
# Output: from_agent|item_name|required
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
    local pattern
    pattern=$(echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/*/g')
    if find "$path" -type f -name "*${pattern}*" 2>/dev/null | grep -q .; then
      found=true
      matched="${matched}${name}|found|provided\n"
    fi
    # Try content keyword match (first 8 chars of name)
    if ! $found; then
      local keyword
      keyword=$(echo "$name" | cut -c1-8)
      if grep -rqi "$keyword" "$path" 2>/dev/null; then
        found=true
        matched="${matched}${name}|content_match|provided\n"
      fi
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

  local id
  id=$(next_id)
  local date
  date=$(date -Iseconds 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")

  echo "创建交接 #${id}: ${from_slug} → ${to_slug}"

  # Get receiver's requirements (filter by sender if possible)
  local reqs
  reqs=$(get_requires "$to_slug" | grep "|${from_slug}|" || get_requires "$to_slug")

  # Scan artifacts
  local scan_result
  scan_result=$(scan_artifacts "$path" "$reqs")
  local matched
  matched=$(echo "$scan_result" | awk '/^MATCHED_START/{found=1; next} /^MATCHED_END/{found=0} found')
  local missing
  missing=$(echo "$scan_result" | awk '/^MISSING_START/{found=1; next} /^MISSING_END/{found=0} found')

  # Build JSON
  local json_file
  json_file="$HANDOFFS_DIR/$(date +%Y-%m-%d)-${from_slug}-to-${to_slug}.json"

  python3 -c "
import json, os

matched_lines = '''$matched'''.strip().split('\n') if '''$matched'''.strip() else []
missing_lines = '''$missing'''.strip().split('\n') if '''$missing'''.strip() else []

artifacts = []

for line in matched_lines:
    parts = line.split('|')
    if len(parts) >= 2:
        artifacts.append({'name': parts[0], 'file': parts[1] if len(parts) > 1 else 'found', 'status': 'provided'})

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
print('  记录: ' + '$json_file')
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

  [[ -z "$id" ]] && die "--handoff <id> is required"

  local json_file
  json_file=$(find "$HANDOFFS_DIR" -name "*.json" -exec python3 -c "import json; d=json.load(open('{}')); print('{}' if d.get('id')==$id else '')" 2>/dev/null \; 2>/dev/null | head -1)

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
    count=$((count + 1))
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

  [[ -z "$id" ]] && die "--handoff <id> is required"
  [[ -z "$as" ]] && die "--as <agent> is required"

  local as_slug
  as_slug="$(resolve_agent "$as")"
  [[ -n "$as_slug" ]] || die "Unknown agent: $as"

  # Find handoff file by ID
  local json_file=""
  for f in "$HANDOFFS_DIR"/*.json; do
    [[ -f "$f" ]] || continue
    local fid
    fid=$(python3 -c "import json; print(json.load(open('$f'))['id'])" 2>/dev/null)
    if [[ "$fid" == "$id" ]]; then
      json_file="$f"
      break
    fi
  done

  [[ -f "$json_file" ]] || die "Handoff #$id not found"

  echo "接收交接 #$id ..."
  python3 -c "
import json, sys
with open('$json_file') as f:
    d = json.load(f)
if d['to'] != '$as_slug':
    print(f'警告: 交接目标为 {d[\"to\"]}，但你以 $as_slug 身份接收')
d['status'] = 'accepted'
d['accepted_by'] = '$as_slug'
with open('$json_file', 'w') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
print(f'交接 #{d[\"id\"]} 已接收 — $as_slug 开始工作')
" 2>/dev/null || {
    ok "交接 #$id 已标记为接收"
  }
}

cmd_list() {
  local mode=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --contracts) mode="contracts"; shift;;
      --handoffs) mode="handoffs"; shift;;
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

cmd_run() {
  local pipeline="" path="" dry_run=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --pipeline) pipeline="$2"; shift 2;;
      --path) path="$2"; shift 2;;
      --dry-run) dry_run=true; shift;;
      --list) ls "$REPO_ROOT/pipelines/"*.yml 2>/dev/null | while read f; do
                local name; name=$(python3 -c "import yaml; print(yaml.safe_load(open('$f'))['name'])" 2>/dev/null)
                local desc; desc=$(python3 -c "import yaml; print(yaml.safe_load(open('$f')).get('description',''))" 2>/dev/null)
                echo "  $(basename "$f" .yml) — $name"
                [[ -n "$desc" ]] && echo "    $desc"
              done; return;;
      *) shift;;
    esac
  done

  [[ -n "$pipeline" ]] || die "--pipeline <name> is required"
  [[ -n "$path" ]] || die "--path <dir> is required"
  [[ -d "$path" ]] || die "--path must be a directory: $path"

  local pipeline_file="$REPO_ROOT/pipelines/${pipeline}.yml"
  [[ -f "$pipeline_file" ]] || die "Pipeline not found: $pipeline (looked for $pipeline_file)"

  echo "============================================"
  echo "  流水线: $pipeline"
  echo "============================================"
  echo ""

  if $dry_run; then
    echo "[DRY-RUN 模式 — 不会创建实际交接]"
    echo ""
  fi

  # Read phases from YAML
  local phase_count; phase_count=$(python3 -c "
import yaml
d = yaml.safe_load(open('$pipeline_file'))
print(len(d['phases']))
" 2>/dev/null)

  for ((i=0; i<phase_count-1; i++)); do
    local current_phase next_phase current_agents next_agents
    current_phase=$(python3 -c "import yaml; d=yaml.safe_load(open('$pipeline_file')); print(d['phases'][$i]['phase'])" 2>/dev/null)
    next_phase=$(python3 -c "import yaml; d=yaml.safe_load(open('$pipeline_file')); print(d['phases'][$((i+1))]['phase'])" 2>/dev/null)
    current_agents=$(python3 -c "import yaml; d=yaml.safe_load(open('$pipeline_file')); print(' '.join(d['phases'][$i]['agents']))" 2>/dev/null)
    next_agents=$(python3 -c "import yaml; d=yaml.safe_load(open('$pipeline_file')); print(' '.join(d['phases'][$((i+1))]['agents']))" 2>/dev/null)

    echo "━━━ 阶段: $current_phase → $next_phase ━━━"
    echo "  当前: $current_agents"
    echo "  产出后交给: $next_agents"
    echo ""
    echo "  请在 $path 目录中准备好 $current_phase 阶段的交付物"
    echo "  完成后按 Enter 继续（或输入 'skip' 跳过此阶段）..."

    if ! $dry_run; then
      read -r input
      [[ "$input" == "skip" ]] && { echo "  已跳过"; echo ""; continue; }
    fi

    echo ""
    echo "  正在创建交接..."

    # Auto-handoff: each current agent → each next agent
    local all_ready=true
    for from_agent in $current_agents; do
      for to_agent in $next_agents; do
        if $dry_run; then
          echo "    [DRY-RUN] $from_agent → $to_agent"
        else
          echo "    $from_agent → $to_agent"
          # Use the handoff logic inline
          local from_slug to_slug
          from_slug="$(resolve_agent "$from_agent")"
          to_slug="$(resolve_agent "$to_agent")"

          [[ -n "$from_slug" ]] || { echo "      [!!] 未知 Agent: $from_agent"; continue; }
          [[ -n "$to_slug" ]] || { echo "      [!!] 未知 Agent: $to_agent"; continue; }

          local id; id=$(next_id)
          local date; date=$(date -Iseconds)

          # Get receiver's requirements
          local reqs; reqs=$(get_requires "$to_slug" | grep "|${from_slug}|" || get_requires "$to_slug")

          # Scan artifacts
          local scan_result; scan_result=$(scan_artifacts "$path" "$reqs")
          local matched; matched=$(echo "$scan_result" | awk '/^MATCHED_START/{found=1; next} /^MATCHED_END/{found=0} found')
          local missing; missing=$(echo "$scan_result" | awk '/^MISSING_START/{found=1; next} /^MISSING_END/{found=0} found')

          local req_missing; req_missing=$(echo "$missing" | grep -c '|True$' 2>/dev/null || echo 0)

          # Build JSON record
          local json_file="$HANDOFFS_DIR/$(date +%Y-%m-%d)-${pipeline}-${from_slug}-to-${to_slug}.json"

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
    'id': $id, 'from': '$from_slug', 'to': '$to_slug',
    'timestamp': '$date', 'pipeline': '$pipeline',
    'phase_from': '$current_phase', 'phase_to': '$next_phase',
    'path': '$path', 'artifacts': artifacts,
    'checklist': {'required_total': req_total, 'required_provided': req_provided, 'required_missing': req_missing},
    'status': 'ready' if req_missing == 0 else 'incomplete', 'accepted_by': None
}
os.makedirs('$HANDOFFS_DIR', exist_ok=True)
with open('$json_file', 'w') as f:
    json.dump(record, f, indent=2, ensure_ascii=False)
print(f'      状态: {record[\"status\"]}')
print(f'      完整度: {req_provided}/{req_total}')
if req_missing > 0:
    print(f'      [!!] 缺失 {req_missing} 项')
    for a in artifacts:
        if a['status'] == 'missing':
            print(f'           - {a[\"name\"]}')
" 2>/dev/null

          if [[ "$req_missing" -gt 0 ]]; then
            all_ready=false
          fi
        fi
      done
    done

    if ! $all_ready && ! $dry_run; then
      echo ""
      echo "  ⚠️  存在缺失项。请补充后按 Enter 重试（或输入 'skip' 跳过）..."
      read -r input
      [[ "$input" == "skip" ]] && { echo "  已跳过"; echo ""; continue; }
    fi

    echo ""
    echo "  ✓ 阶段 $current_phase → $next_phase 完成"
    echo ""
  done

  echo "============================================"
  echo "  流水线完成: $pipeline"
  echo "============================================"
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
  run)     cmd_run "$@";;
  --help|-h|help)
    sed -n '3,12p' "$0" | sed 's/^# \{0,1\}//'
    ;;
  *) die "Unknown command: $CMD. Valid: handoff, check, status, accept, list, run";;
esac
