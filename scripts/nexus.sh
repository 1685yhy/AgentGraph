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
#   guild decide   --agent <name> --type <type> --topic <topic> [options]
#   guild context  [show|check]
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
  awk -v slug="$slug" '
    $0 ~ "^  " slug ":" { in_contract=1; next }
    in_contract && /^  [a-z]/ && $0 !~ "^  " slug ":" { in_contract=0; next }
    in_contract && /^    requires:/ { in_req=1; next }
    in_contract && /^    delivers:/ { in_req=0; next }
    in_req && /^      - from:/ { sub(/.*from: "/, ""); sub(/".*/, ""); current_from=$0; next }
    in_req && /^          - name:/ { sub(/.*name: "/, ""); sub(/".*/, ""); current_name=$0; next }
    in_req && /^            required:/ {
      sub(/.*required: /, ""); gsub(/"/, "");
      if ($0 == "true") r="True"; else r="False";
      if (current_from != "") print current_from "|" current_name "|" r
    }
  ' "$CONTRACTS"
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
  date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

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

  # Context check: are there relevant decisions this handoff should follow?
  echo ""
  echo "  上下文检查..."

  local relevant=0
  for f in "$REPO_ROOT/context/decisions"/*.json; do
    [[ -f "$f" ]] || continue
    local dec_agent; dec_agent=$(grep -o '"agent": "[^"]*"' "$f" | head -1 | cut -d'"' -f4)
    local dec_topic; dec_topic=$(grep -o '"topic": "[^"]*"' "$f" | head -1 | cut -d'"' -f4)
    local dec_status; dec_status=$(grep -o '"status": "[^"]*"' "$f" | tail -1 | cut -d'"' -f4)

    # If the decision maker is the sender or receiver of this handoff
    if [[ "$dec_agent" == "$from_slug" || "$dec_agent" == "$to_slug" ]] && [[ "$dec_status" == "active" ]]; then
      ((relevant++)) 2>/dev/null || true
      echo "    📋 相关决策: #$(grep -o '"id": [0-9]*' "$f" | head -1 | awk '{print $2}') [$dec_agent] $dec_topic"
    fi
  done

  [[ $relevant -gt 0 ]] && echo "    → 建议确认交付物是否遵循以上决策" || echo "    (无相关决策)"
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
      awk '
        /^  [a-z]/ {
          if (slug != "") print slug ": 产出 " del_count " 项, 需求 " req_count " 项"
          slug=$1; gsub(/:$/, "", slug); del_count=0; req_count=0
        }
        /delivers:/ { in_del=1; in_req=0; next }
        /requires:/ { in_req=1; in_del=0; next }
        in_del && /- name:/ { del_count++ }
        in_req && /- name:/ { req_count++ }
        END { if (slug != "") print slug ": 产出 " del_count " 项, 需求 " req_count " 项" }
      ' "$CONTRACTS"
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
      --list) for f in "$REPO_ROOT/pipelines/"*.yml; do
                [[ -f "$f" ]] || continue
                local name; name=$(grep -m1 '^name:' "$f" | sed 's/^name: *//')
                local desc; desc=$(grep -m1 '^description:' "$f" | sed 's/^description: *//')
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

  # Read phases from pipeline YAML
  local phase_count; phase_count=$(grep -c '^  - phase:' "$pipeline_file")

  for ((i=0; i<phase_count-1; i++)); do
    local current_phase next_phase current_agents next_agents
    current_phase=$(awk -v n=$((i+1)) '/^  - phase:/{count++; if(count==n){sub(/.*phase: /,""); print; exit}}' "$pipeline_file")
    next_phase=$(awk -v n=$((i+2)) '/^  - phase:/{count++; if(count==n){sub(/.*phase: /,""); print; exit}}' "$pipeline_file")
    current_agents=$(awk -v n=$((i+1)) '/^  - phase:/{count++} count==n && /agents:/{gsub(/.*agents: \[|\]/,""); gsub(/,/," "); print; exit}' "$pipeline_file")
    next_agents=$(awk -v n=$((i+2)) '/^  - phase:/{count++} count==n && /agents:/{gsub(/.*agents: \[|\]/,""); gsub(/,/," "); print; exit}' "$pipeline_file")

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
          local date; date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

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

    # Auto context check after phase
    if ! $dry_run; then
      echo ""
      echo "  正在运行上下文检查..."
      "$0" context check 2>/dev/null | head -10
    fi

    echo ""
  done

  echo "============================================"
  echo "  流水线完成: $pipeline"
  echo "============================================"
}

# ── cmd_decide ────────────────────────────────────────────────────────

cmd_decide() {
  local agent="" type="" topic="" summary="" rationale="" constraints="" authority=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --agent) agent="$2"; shift 2;;
      --type) type="$2"; shift 2;;
      --topic) topic="$2"; shift 2;;
      --summary) summary="$2"; shift 2;;
      --rationale) rationale="$2"; shift 2;;
      --constraints) constraints="$2"; shift 2;;
      --authority) authority="$2"; shift 2;;
      *) shift;;
    esac
  done

  [[ -n "$agent" ]] || die "--agent is required"
  [[ -n "$type" ]] || die "--type is required (api-design, data-model, naming, scope, architecture, deployment, ux, brand)"
  [[ -n "$topic" ]] || die "--topic is required"
  [[ -n "$summary" ]] || die "--summary is required"

  local agent_slug; agent_slug="$(resolve_agent "$agent")"
  [[ -n "$agent_slug" ]] || die "Unknown agent: $agent"

  # Auto-fill authority from agent's decision authority section
  [[ -z "$authority" ]] && authority="$agent_slug"

  # PREVENTIVE CHECK: Calculate impact scope
  echo "记录决策: $agent_slug / $type / $topic"
  echo ""
  echo "=== 影响分析 ==="

  # Check which agents depend on this agent (from guild-contracts.yml)
  local affected=""
  local affected_count=0
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local downstream; downstream=$(echo "$line" | awk -F'|' '{print $1}')
    local item; item=$(echo "$line" | awk -F'|' '{print $2}')
    if [[ -n "$downstream" && "$downstream" != "$agent_slug" ]]; then
      if [[ -z "$(echo "$affected" | grep "$downstream")" ]]; then
        affected="$affected $downstream"
        ((affected_count++)) || true
      fi
    fi
  done < <(awk -v agent="$agent_slug" '
    /^  [a-z]/ { current=$1; gsub(/:$/,"",current) }
    /- from:/ && $0 ~ agent { found=1; print current }
  ' "$CONTRACTS" 2>/dev/null)

  if [[ -n "$affected" ]]; then
    echo "  此决策影响以下 Agent："
    for a in $affected; do
      echo "    - $a"
    done
    echo ""
    echo "  建议：通知所有受影响方。"
    echo "  是否继续记录？(Enter/Y = 继续, N = 取消)"
    read -r confirm
    [[ "$confirm" == "N" || "$confirm" == "n" ]] && { echo "已取消"; return 0; }
  else
    echo "  未检测到直接影响（基于现有契约）。"
  fi

  # Create decision record
  local id; id=$(date +%s)
  local timestamp; timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local slug_topic; slug_topic=$(echo "$topic" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//')
  local filename="${id}-${agent_slug}-${slug_topic}.json"
  local filepath="$REPO_ROOT/context/decisions/$filename"

  # Parse affected list for JSON array
  local affected_json="["
  local first=true
  for a in $affected; do
    $first && first=false || affected_json+=", "
    affected_json+="\"$a\""
  done
  affected_json+="]"

  cat > "$filepath" << JSONEOF
{
  "id": $id,
  "agent": "$agent_slug",
  "timestamp": "$timestamp",
  "decision": {
    "type": "$type",
    "topic": "$topic",
    "summary": "$summary",
    "rationale": "$rationale",
    "constraints": "$constraints",
    "authority": "$authority"
  },
  "impact": {
    "affects": $affected_json,
    "breaking_changes": [],
    "notified": [],
    "confirmed": []
  },
  "traceability": [],
  "status": "active",
  "superseded_by": null
}
JSONEOF

  # Update index
  local idx="$REPO_ROOT/context/index.json"
  local tmpidx="${idx}.tmp"
  python3 -c "
import json
with open('$idx') as f:
    idx = json.load(f)
idx['updated'] = '$timestamp'
idx['decisions'].append({
    'id': $id,
    'agent': '$agent_slug',
    'type': '$type',
    'topic': '$topic',
    'file': '$filename',
    'status': 'active'
})
with open('$tmpidx', 'w') as f:
    json.dump(idx, f, indent=2, ensure_ascii=False)
" 2>/dev/null && mv "$tmpidx" "$idx" || {
    ok "索引更新跳过（python3 不可用）。决策已保存至: $filepath"
    return 0
  }

  echo ""
  ok "决策 #$id 已记录: $agent_slug / $type / $topic"
  ok "文件: $filename"
  [[ -n "$affected" ]] && echo "  受影响方: $affected"
}

# ── cmd_context ────────────────────────────────────────────────────────

cmd_context() {
  local sub="${1:-show}"; shift || true

  case "$sub" in
    show)
      echo "=== 决策图谱 ==="
      echo ""

      local idx="$REPO_ROOT/context/index.json"
      [[ -f "$idx" ]] || { echo "  暂无决策记录。使用 guild decide 创建第一条。"; return 0; }

      # Group by type
      echo "按类型分组："
      local types; types=$(python3 -c "
import json
idx = json.load(open('$idx'))
types = {}
for d in idx['decisions']:
    t = d['type']
    if t not in types: types[t] = []
    types[t].append(d)
for t in sorted(types.keys()):
    print(f'{t}:{len(types[t])}')
" 2>/dev/null)

      if [[ -n "$types" ]]; then
        echo "$types" | while IFS=':' read -r t count; do
          echo "  $t ($count 条)"
          # List decisions of this type
          python3 -c "
import json
idx = json.load(open('$idx'))
for d in idx['decisions']:
    if d['type'] == '$t':
        print(f'    #{d[\"id\"]} [{d[\"agent\"]}] {d[\"topic\"]} ({d[\"status\"]})')
" 2>/dev/null
        done
      else
        # Fallback: list all from files
        echo "  (使用文件列表)"
        for f in "$REPO_ROOT/context/decisions"/*.json; do
          [[ -f "$f" ]] || continue
          local id; id=$(grep -o '"id": [0-9]*' "$f" | head -1 | awk '{print $2}')
          local agent; agent=$(grep -o '"agent": "[^"]*"' "$f" | head -1 | cut -d'"' -f4)
          local topic; topic=$(grep -o '"topic": "[^"]*"' "$f" | head -1 | cut -d'"' -f4)
          local status; status=$(grep -o '"status": "[^"]*"' "$f" | tail -1 | cut -d'"' -f4)
          echo "    #$id [$agent] $topic ($status)"
        done
      fi
      ;;

    check)
      echo "=== 冲突检查 ==="
      echo ""

      local idx="$REPO_ROOT/context/index.json"
      [[ -f "$idx" ]] || { echo "  暂无决策。"; return 0; }

      local conflicts=0

      # Check 1: Decisions on same topic by different agents
      echo "1. 同主题多决策："
      local check1_output; check1_output=$(python3 -c "
import json
from collections import defaultdict
idx = json.load(open('$idx'))
topics = defaultdict(list)
for d in idx['decisions']:
    if d['status'] == 'active':
        topics[d['topic']].append(d)
found = 0
for topic, decs in topics.items():
    if len(decs) > 1:
        agents = set(d['agent'] for d in decs)
        if len(agents) > 1:
            found += 1
            print(f'  ⚠️  冲突: {topic}')
            for d in decs:
                print(f'      #{d[\"id\"]} [{d[\"agent\"]}]: {d[\"topic\"]}')
print(f'CONFLICT_COUNT={found}')
" 2>/dev/null) || {
        echo "  (无法运行冲突检查 — python3 不可用)"
        check1_output="CONFLICT_COUNT=0"
      }

      # Print check output (excluding the CONFLICT_COUNT marker)
      echo "$check1_output" | grep -v "^CONFLICT_COUNT="
      local conflict_count; conflict_count=$(echo "$check1_output" | grep "^CONFLICT_COUNT=" | cut -d= -f2)
      conflict_count=${conflict_count:-0}
      if [[ "$conflict_count" -gt 0 ]]; then
        conflicts=$conflict_count
      fi

      # Check 2: Handoff traceability
      echo ""
      echo "2. 决策追溯："
      local total_trace=0
      for f in "$REPO_ROOT/context/decisions"/*.json; do
        [[ -f "$f" ]] || continue
        local traces; traces=$(grep -c '"handoff_id"' "$f" 2>/dev/null || echo 0)
        ((total_trace += traces)) 2>/dev/null || true
      done
      echo "  总决策数: $(ls "$REPO_ROOT/context/decisions"/*.json 2>/dev/null | wc -l)"
      echo "  已追溯的交付物: $total_trace"

      echo ""
      [[ $conflicts -gt 0 ]] && echo "  ⚠️  发现潜在冲突，运行 guild resolve 处理。" || echo "  ✓ 未检测到冲突。"
      ;;

    *)
      echo "用法: guild context [show|check]"
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
  echo "  guild decide    — 记录结构化决策 (ADR)"
  echo "  guild context   — 显示/检查决策图谱和冲突"
  echo "  guild run       — 执行流水线"
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
  decide)  cmd_decide "$@";;
  context) cmd_context "$@";;
  --help|-h|help)
    sed -n '3,12p' "$0" | sed 's/^# \{0,1\}//'
    ;;
  *) die "Unknown command: $CMD. Valid: handoff, check, status, accept, list, run, decide, context";;
esac
