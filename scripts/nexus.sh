#!/usr/bin/env bash
#
# nexus.sh — AgentGraph Handoff Engine CLI
#
# Usage:
#   guild handoff   --from <agent> --to <agent> --path <dir> [--message <msg>]
#   guild check     --handoff <id>
#   guild status    [--agent <name>] [--status incomplete|needs_fix|ready|accepted]
#   guild accept    --handoff <id> --as <agent>
#   guild verify    --type <type> --file <path> | --path <dir> | --handoff <id>
#   guild test      --file <path> [--spec <spec>] | --handoff <id>
#   guild test      --generate --from-agent <agent> --file <path> [--output <file>]
#   guild feedback  --handoff <id> --type bug|improvement --summary "..."
#   guild feedback  --list [--handoff <id>] [--status open|fixed]
#   guild feedback  --fix <fb-id> --handoff <id>
#   guild changelog [--since <version|date>]
#   guild list      [--contracts] [--handoffs]
#   guild decide    --agent <name> --type <type> --topic <topic> [options]
#   guild context   [show|check]
#   guild gate      --handoff <id> [--gate <1-5>] | --list
#
# guild is an alias: ln -s scripts/nexus.sh guild

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

# shellcheck source=test-runner.sh
. "$SCRIPT_DIR/test-runner.sh"

CONTRACTS="$REPO_ROOT/contracts/guild-contracts.yml"
HANDOFFS_DIR="$REPO_ROOT/handoffs"
CONFIG="$REPO_ROOT/guild.config.json"
FEEDBACK_DIR="$REPO_ROOT/context/feedback"

# ── Helpers ────────────────────────────────────────────────────────

# next_id — auto-increment handoff ID (with uniqueness validation)
next_id() {
  local max=0
  for f in "$HANDOFFS_DIR"/*.json; do
    [[ -f "$f" ]] || continue
    local id
    id=$(json_get "$f" "id" "0")
    (( id > max )) && max=$id
  done
  local candidate=$((max + 1))
  # Uniqueness validation: verify no existing handoff uses this ID
  while true; do
    local collision=0
    for f in "$HANDOFFS_DIR"/*.json; do
      [[ -f "$f" ]] || continue
      local existing_id
      existing_id=$(json_get "$f" "id" "0")
      if (( existing_id == candidate )); then
        collision=1
        break
      fi
    done
    if (( collision == 0 )); then
      echo "$candidate"
      return
    fi
    candidate=$((candidate + 1))
  done
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

# ── File type detection ─────────────────────────────────────────────

# detect_type <file> — return file type based on extension.
detect_type() {
  local file="$1"
  local ext="${file##*.}"
  case "$(echo "$ext" | tr '[:upper:]' '[:lower:]')" in
    html|htm) echo "html";;
    md|markdown) echo "md";;
    sh|bash) echo "sh";;
    json) echo "json";;
    yml|yaml) echo "yaml";;
    css) echo "css";;
    js|mjs|cjs) echo "js";;
    ts|tsx) echo "ts";;
    py) echo "py";;
    *) echo "";;
  esac
}

# verify_file <type> <path> — run quality checks on a single file.
verify_file() {
  local type="$1" path="$2"
  [[ -f "$path" ]] || { err "文件不存在: $path"; return 1; }
  [[ -s "$path" ]] || { err "空文件: $path"; return 1; }

  # UTF-8 validity check
  if ! iconv -f UTF-8 -t UTF-8 "$path" >/dev/null 2>&1; then
    err "不是有效的 UTF-8 编码"; return 1;
  fi

  # BOM check
  if head -1 "$path" | grep -q $'\xEF\xBB\xBF' 2>/dev/null; then
    err "包含 BOM 头（建议移除）"; return 1;
  fi

  case "$type" in
    html)
      local errors=0
      # <script> must have closing tag
      if grep -qi '<script' "$path" && ! grep -qi '</script>' "$path"; then
        err "缺少 </script> 闭合标签"; errors=1
      fi
      # viewport meta required for mobile
      if ! grep -qi 'viewport' "$path"; then
        err "缺少 viewport meta 标签（移动端适配必需）"; errors=1
      fi
      # console.error pattern check
      if grep -q 'console\.error' "$path"; then
        warn "检测到 console.error 调用"
      fi
      # event binding check
      if ! grep -q 'addEventListener\|onclick\|onchange\|onsubmit' "$path"; then
        warn "未检测到事件绑定（如果页面需要交互请确认）"
      fi

      # Extract inline JS and validate
      local js_content; js_content=$(sed -n '/<script>/,/<\/script>/p' "$path" | grep -v '<script>\|</script>')
      if [[ -n "$js_content" ]]; then
        # Run node --check if available
        if command -v node &>/dev/null; then
          echo "$js_content" > /tmp/_guild_verify.js
          if ! node --check /tmp/_guild_verify.js 2>/dev/null; then
            warn "JS 语法错误"
            node --check /tmp/_guild_verify.js 2>&1 | head -3
          else
            ok "JS 语法通过"
          fi
          rm -f /tmp/_guild_verify.js
        fi

        # Check DOM ID references: find getElementById('X') and verify X exists in HTML
        local js_ids; js_ids=$(echo "$js_content" | grep -oP "getElementById\s*\(\s*'[^']+'" | grep -oP "'[^']+'" | tr -d "'")
        for id in $js_ids; do
          if ! grep -q "id=\"$id\"\|id='$id'" "$path"; then
            warn "JS 引用了不存在的 DOM ID: '$id'"
          fi
        done
      fi

      [[ $errors -eq 0 ]] && return 0 || return 1
      ;;
    md)
      # Check frontmatter completeness
      if head -1 "$path" | grep -q '^---$'; then
        local fm_end; fm_end=$(tail -n+2 "$path" | grep -n '^---$' | head -1 | cut -d: -f1)
        if [[ -z "$fm_end" ]]; then
          warn "frontmatter 未闭合"
        fi
      fi
      # Check for broken local links
      while IFS= read -r link; do
        local url; url=$(printf '%s' "$link" | sed -n 's/.*\[[^]]*\](\([^)]*\)).*/\1/p')
        [[ -z "$url" ]] && continue
        echo "$url" | grep -qE '^https?://|^#|^/' && continue
        local base_dir; base_dir="$(dirname "$path")"
        if echo "$url" | grep -qE '\.md$|\.html$' && [[ ! -f "$base_dir/$url" ]]; then
          warn "可能断开的本地链接: $url"
        fi
      done < <(grep -oP '\[[^\]]+\]\([^)]+\)' "$path" 2>/dev/null || true)
      return 0
      ;;
    sh)
      local errors=0
      if ! bash -n "$path" 2>/dev/null; then
        err "bash 语法检查失败"; errors=1
      fi
      # Check for rm -rf with variable
      if grep -q 'rm -rf.*\$' "$path" 2>/dev/null; then
        warn "使用 rm -rf + 变量（请确认路径安全）"
      fi
      [[ $errors -eq 0 ]] && return 0 || return 1
      ;;
    json)
      if ! json_validate "$path"; then
        err "JSON 格式错误"; return 1
      fi
      return 0
      ;;
    yaml|yml)
      return 0
      ;;
    css)
      local opens; opens=$(grep -c '{' "$path" 2>/dev/null || echo 0)
      local closes; closes=$(grep -c '}' "$path" 2>/dev/null || echo 0)
      if [[ "$opens" -ne "$closes" ]]; then
        err "CSS 大括号不匹配（{ $opens / } $closes）"; return 1
      fi
      return 0
      ;;
    js|ts)
      if command -v node >/dev/null 2>&1; then
        if ! node --check "$path" 2>/dev/null; then
          err "JavaScript 语法错误"; return 1
        fi
      fi
      return 0
      ;;
    py)
      if command -v python3 >/dev/null 2>&1; then
        if ! python3 -c "import ast; ast.parse(open('$path').read())" 2>/dev/null; then
          err "Python 语法错误"; return 1
        fi
      fi
      return 0
      ;;
    *)
      return 0
      ;;
  esac
}

# verify_directory <path> — run verify on all files in a directory.
verify_directory() {
  local path="$1"
  local any_failed=false
  while IFS= read -r -d '' f; do
    local vtype; vtype=$(detect_type "$f")
    if [[ -n "$vtype" ]]; then
      if verify_file "$vtype" "$f"; then
        echo "    ✅ $(basename "$f"): 通过"
      else
        any_failed=true
        echo "    ❌ $(basename "$f"): 质量检查未通过"
      fi
    fi
  done < <(find "$path" -type f -print0 2>/dev/null)
  $any_failed && return 1 || return 0
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

  # Count stats and build artifacts array (pure bash — no python3)
  local req_total=0 req_provided=0 req_missing_count=0
  local artifacts_json=""
  local first_item=true

  # Parse matched items
  while IFS='|' read -r name source status; do
    [[ -z "$name" ]] && continue
    req_total=$((req_total + 1))
    req_provided=$((req_provided + 1))
    if $first_item; then first_item=false; else artifacts_json+=","; fi
    artifacts_json+="{\"name\":\"$name\",\"file\":\"$source\",\"status\":\"provided\"}"
  done <<< "$(echo -e "$matched" | grep -v '^$')"

  # Parse missing items
  while IFS='|' read -r from_name name required; do
    [[ -z "$name" ]] && continue
    req_total=$((req_total + 1))
    if $first_item; then first_item=false; else artifacts_json+=","; fi
    local req_bool="false"
    [[ "$required" == "True" ]] && req_bool="true"
    artifacts_json+="{\"name\":\"$name\",\"file\":null,\"status\":\"missing\",\"required\":$req_bool}"
    [[ "$required" == "True" ]] && req_missing_count=$((req_missing_count + 1))
  done <<< "$(echo -e "$missing" | grep -v '^$')"

  local new_status="incomplete"
  [[ $req_missing_count -eq 0 ]] && new_status="ready"

  mkdir -p "$HANDOFFS_DIR"

  # Build JSON with pure bash heredoc — NO python3
  cat > "$json_file" << JSONEOF
{
  "id": $id,
  "from": "$from_slug",
  "to": "$to_slug",
  "timestamp": "$date",
  "message": "$message",
  "path": "$path",
  "artifacts": [$artifacts_json],
  "checklist": {
    "required_total": $req_total,
    "required_provided": $req_provided,
    "required_missing": $req_missing_count
  },
  "status": "$new_status",
  "accepted_by": null
}
JSONEOF

  echo "  状态: $new_status"
  echo "  完整度: $req_provided/$req_total 项已提供"
  if [[ $req_missing_count -gt 0 ]]; then
    echo "  [!!] 缺失 $req_missing_count 项:"
    echo -e "$missing" | grep '|True$' | while IFS='|' read -r from_name name required; do
      echo "       - $name"
    done
  fi
  echo "  记录: $json_file"

  # Auto-verify deliverable quality (only if completeness passed)
  echo ""
  echo "  质量验证..."
  local verify_failed=false
  local is_ready; is_ready=false
  grep -q '"status": "ready"' "$json_file" 2>/dev/null && is_ready=true

  while IFS= read -r -d '' f; do
    local vtype; vtype=$(detect_type "$f")
    if [[ -n "$vtype" ]]; then
      if verify_file "$vtype" "$f"; then
        echo "    ✅ $(basename "$f"): 通过"
      else
        verify_failed=true
        echo "    ❌ $(basename "$f"): 质量检查未通过"
      fi
    fi
  done < <(find "$path" -type f -print0 2>/dev/null)

  if $verify_failed; then
    if $is_ready; then
      sed -i 's/"status": "ready"/"status": "needs_fix"/' "$json_file"
      is_ready=false
    fi
    echo ""
    echo "  ⚠️  状态已更新为 needs_fix（交付物存在但质量检查未通过）"
  else
    echo ""
    echo "  ✓ 质量验证通过"
  fi

  # Auto-notify receiver's inbox
  local status_text
  if $is_ready; then
    status_text="$from_slug 创建了交接 #$id，所有交付物已就绪"
  else
    if $verify_failed; then
      status_text="$from_slug 创建了交接 #$id，交付物存在但质量检查未通过"
    else
      status_text="$from_slug 创建了交接 #$id，存在缺失项待补充"
    fi
  fi
  add_inbox_item "$to_slug" "handoff_incoming" "$from_slug" \
    "handoff_id=$id" \
    "$status_text" \
    "检查交付物并运行 guild accept --handoff $id"
  echo "  📨 已通知 $to_slug"

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

  # Auto-detect conflicts
  local conflict_found=false
  for f in "$REPO_ROOT/context/decisions"/*.json; do
    [[ -f "$f" ]] || continue
    local dec_agent; dec_agent=$(grep -o '"agent": "[^"]*"' "$f" | head -1 | cut -d'"' -f4)
    local dec_topic; dec_topic=$(grep -o '"topic": "[^"]*"' "$f" | head -1 | cut -d'"' -f4)

    # Check if another agent has a decision on the same topic with different content
    for g in "$REPO_ROOT/context/decisions"/*.json; do
      [[ -f "$g" ]] || continue
      [[ "$f" == "$g" ]] && continue
      local g_agent; g_agent=$(grep -o '"agent": "[^"]*"' "$g" | head -1 | cut -d'"' -f4)
      local g_topic; g_topic=$(grep -o '"topic": "[^"]*"' "$g" | head -1 | cut -d'"' -f4)

      if [[ "$dec_topic" == "$g_topic" && "$dec_agent" != "$g_agent" ]]; then
        # Same topic, different agents — potential conflict
        if [[ "$dec_agent" == "$from_slug" || "$dec_agent" == "$to_slug" ]] || [[ "$g_agent" == "$from_slug" || "$g_agent" == "$to_slug" ]]; then
          $conflict_found && continue
          conflict_found=true
          echo ""
          warn "检测到潜在决策冲突: $dec_topic"
          echo "    $dec_agent vs $g_agent"
          echo "    建议: 运行 guild context check 查看详情"
          echo "    建议: 在继续交接前解决此冲突"
          # Auto-notify conflicting agents
          add_inbox_item "$dec_agent" "conflict_active" "$g_agent" \
            "topic=$dec_topic" \
            "与 $g_agent 在 $dec_topic 上存在矛盾决策" \
            "基于决策权重协商解决。运行 guild resolve --topic '$dec_topic'"
          add_inbox_item "$g_agent" "conflict_active" "$dec_agent" \
            "topic=$g_topic" \
            "与 $dec_agent 在 $g_topic 上存在矛盾决策" \
            "基于决策权重协商解决。运行 guild resolve --topic '$g_topic'"
        fi
      fi
    done
  done
}

cmd_check() {
  local id="" check_dups=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --handoff) id="$2"; shift 2;;
      --duplicates) check_dups=true; shift;;
      *) shift;;
    esac
  done

  # --duplicates mode: scan all handoffs for duplicate IDs
  if $check_dups; then
    if command -v node &>/dev/null; then
      node -e "
const fs = require('fs'), path = require('path');
const hdir = '$HANDOFFS_DIR';
const ids = {};
for (const fn of fs.readdirSync(hdir).filter(f => f.endsWith('.json')).sort()) {
  try { const d = JSON.parse(fs.readFileSync(path.join(hdir, fn), 'utf8')); (ids[d.id] = ids[d.id] || []).push(fn); } catch(e) {}
}
let dupFound = false;
for (const [idVal, fns] of Object.entries(ids).sort((a,b) => a[0]-b[0])) {
  if (fns.length > 1) { dupFound = true; console.log('  DUPLICATE ID #' + idVal + ': ' + fns.join('  ')); }
}
if (!dupFound) console.log('  No duplicate IDs found');
else { console.log(''); console.log('  Run \"guild cleanup\" to reset duplicate handoffs'); }
process.exit(dupFound ? 1 : 0);
"
    else
      err "node required for duplicate check"
      return 1
    fi
    return
  fi

  [[ -z "$id" ]] && die "--handoff <id> is required"

  # Find handoff file by ID (pure bash)
  local json_file=""
  for f in "$HANDOFFS_DIR"/*.json; do
    [[ -f "$f" ]] || continue
    local fid
    fid=$(json_get "$f" "id" "0")
    if [[ "$fid" == "$id" ]]; then
      json_file="$f"
      break
    fi
  done

  [[ -f "$json_file" ]] || die "Handoff #$id not found"

  # Display handoff details
  local d_id d_from d_to d_status d_timestamp d_provided d_total d_missing
  d_id=$(json_get "$json_file" "id")
  d_from=$(json_get "$json_file" "from")
  d_to=$(json_get "$json_file" "to")
  d_status=$(json_get "$json_file" "status")
  d_timestamp=$(json_get "$json_file" "timestamp")
  echo "交接 #${d_id}: ${d_from} → ${d_to}"
  echo "状态: ${d_status}"
  echo "时间: ${d_timestamp:0:19}"

  # Parse checklist via node or bash
  if command -v node &>/dev/null; then
    node -e "
const d=JSON.parse(require('fs').readFileSync('$json_file','utf8'));
const c=d.checklist||{};
console.log('完整度: '+c.required_provided+'/'+c.required_total+' 项');
if((c.required_missing||0)>0){console.log('缺失项:');for(const a of(d.artifacts||[])){if(a.status==='missing')console.log('  - '+a.name)}}
else{console.log('所有必需项已满足 ✓')}
"
  else
    cat "$json_file"
  fi
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
    id=$(json_get "$f" "id")
    from=$(json_get "$f" "from")
    to=$(json_get "$f" "to")
    status=$(json_get "$f" "status")
    timestamp=$(json_get "$f" "timestamp")
    timestamp="${timestamp:0:19}"

    [[ -n "$id" ]] || continue

    # Filter
    [[ -n "$agent" && "$from" != "$agent" && "$to" != "$agent" ]] && continue
    [[ -n "$status_filter" && "$status" != "$status_filter" ]] && continue

    local icon
    case "$status" in
      ready) icon="✅";;
      incomplete) icon="⚠️";;
      needs_fix) icon="🔧";;
      accepted) icon="✔️";;
      *) icon="📋";;
    esac

    echo "  $icon #$id: $from → $to ($status) — $timestamp"
    count=$((count + 1))
  done

  if (( count == 0 )); then
    echo "  (无交接记录)"
  fi

  # Check for stale handoffs (older than 7 days, incomplete or needs_fix)
  local stale_count=0
  for f in "$HANDOFFS_DIR"/*.json; do
    [[ -f "$f" ]] || continue
    local sid sstatus sts
    sid=$(json_get "$f" "id")
    sstatus=$(json_get "$f" "status")
    sts=$(json_get "$f" "timestamp")
    sts="${sts:0:19}"
    [[ -n "$sid" ]] || continue
    [[ "$sstatus" == "incomplete" || "$sstatus" == "needs_fix" ]] || continue
    local septokh
    septokh=$(date -d "$(echo "$sts" | tr 'T' ' ')" +%s 2>/dev/null || echo 0)
    local now_epoch
    now_epoch=$(date +%s)
    local age_days=$(( (now_epoch - septokh) / 86400 ))
    if (( age_days >= 7 )); then
      stale_count=$((stale_count + 1))
    fi
  done

  if (( stale_count > 0 )); then
    echo ""
    echo "  ⚠  Warning: $stale_count stale handoff(s) found (older than 7 days, incomplete/needs_fix)."
    echo "     Run 'guild cleanup' to review or 'guild cleanup --stale' to archive."
  fi
}

# ── cmd_gate ──────────────────────────────────────────────────────────

# Usage: guild gate --handoff <id> [--gate <1-5>]
#        guild gate --list

cmd_gate() {
  local handoff="" gate_num=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --handoff) handoff="$2"; shift 2;;
      --gate) gate_num="$2"; shift 2;;
      --list) list_gates; return;;
      *) shift;;
    esac
  done

  [[ -n "$handoff" ]] || die "--handoff <id> is required"

  # Find handoff file by ID
  local json_file=""
  for f in "$HANDOFFS_DIR"/*.json; do
    [[ -f "$f" ]] || continue
    local fid
    fid=$(json_get "$f" "id")
    if [[ "$fid" == "$handoff" ]]; then
      json_file="$f"
      break
    fi
  done
  [[ -f "$json_file" ]] || die "Handoff #$handoff not found"

  local path from to
  path=$(json_get "$json_file" "path")
  from=$(json_get "$json_file" "from")
  to=$(json_get "$json_file" "to")

  echo "╔══════════════════════════════════════╗"
  echo "║  Quality Gates: Handoff #$handoff"
  echo "║  $from -> $to"
  echo "╚══════════════════════════════════════╝"
  echo ""

  local passed=0 failed=0
  local gates=("completeness" "syntax" "behavior" "playability" "agent-standards")

  for gate in "${gates[@]}"; do
    [[ -n "$gate_num" && "$gate" != "$gate_num" ]] && continue

    echo "-- Gate: $gate --"

    case "$gate" in
      completeness)
        local missing=0
        # Count missing required artifacts using node
        if command -v node &>/dev/null; then
          missing=$(node -e "const d=JSON.parse(require('fs').readFileSync('$json_file','utf8'));let m=0;for(const a of(d.artifacts||[])){if(a.status==='missing'&&a.required!==false)m++}console.log(m)" 2>/dev/null) || missing=0
        fi
        if [[ "$missing" -eq 0 ]]; then
          echo "  [OK] 所有必需交付物已提供"
          passed=$((passed + 1))
        else
          echo "  [FAIL] $missing 项缺失"
          failed=$((failed + 1))
        fi
        ;;

      syntax)
        local syntax_ok=true
        if [[ -d "$path" ]]; then
          while IFS= read -r -d '' f; do
            local vtype; vtype=$(detect_type "$f")
            if [[ -n "$vtype" ]]; then
              if ! verify_file "$vtype" "$f" 2>/dev/null; then
                syntax_ok=false
                echo "  [FAIL] $(basename "$f"): 语法验证失败"
              fi
            fi
          done < <(find "$path" -type f -print0 2>/dev/null)
        fi
        if $syntax_ok; then
          echo "  [OK] 所有文件语法验证通过"
          passed=$((passed + 1))
        else
          failed=$((failed + 1))
        fi
        ;;

      behavior)
        if [[ -x "$REPO_ROOT/scripts/test-runner.sh" && -d "$path" ]]; then
          local behavior_ok=true
          while IFS= read -r -d '' f; do
            if [[ "$(detect_type "$f")" == "html" ]]; then
              local test_output
              test_output=$(run_all_tests "$f" 2>&1) || behavior_ok=false
              echo "$test_output" | sed 's/^/  /'
            fi
          done < <(find "$path" -name "*.html" -type f -print0 2>/dev/null)
          if $behavior_ok; then
            echo "  [OK] 行为测试通过"
            passed=$((passed + 1))
          else
            echo "  [FAIL] 行为测试未全部通过"
            failed=$((failed + 1))
          fi
        else
          echo "  [SKIP] 行为测试不可用（无HTML文件或test-runner不可达）"
        fi
        ;;

      playability)
        local play_ok=true
        local html_files=0
        while IFS= read -r -d '' f; do
          if [[ "$(detect_type "$f")" == "html" ]]; then
            html_files=$((html_files + 1))
            local file_content; file_content=$(cat "$f")

            echo "  检查: $(basename "$f")"

            # Check 1: Tutorial/onboarding
            if [[ $(echo "$file_content" | grep -ci 'tutorial\|教程\|引导\|hint\|提示.*点击\|点击.*提示\|instruction\|指导' || true) -gt 0 ]]; then
              echo "    [OK] 有教程或引导提示"
            else
              echo "    [WARN] 缺少教程或引导提示"
            fi

            # Check 2: Audio init on user gesture
            if [[ $(echo "$file_content" | grep -c 'AudioContext.*click\|audioCtx.*click\|initAudio\|audio.*init.*click\|addEventListener.*click.*audio\|用户手势.*音频\|click.*AudioContext' || true) -gt 0 ]]; then
              echo "    [OK] 音效在用户手势时初始化"
            else
              if [[ $(echo "$file_content" | grep -c 'new.*AudioContext\|new.*webkitAudioContext' || true) -gt 0 ]]; then
                echo "    [WARN] AudioContext在构造时创建(非用户手势) — 可能静音"
              fi
            fi

            # Check 3: No blocking UI before core interaction
            if [[ $(echo "$file_content" | grep -c 'startGame\|btn-start.*click\|开始.*addEventListener\|core.*start\|play.*addEventListener' || true) -gt 0 ]]; then
              echo "    [OK] 核心功能 ≤1 次交互可达"
            else
              echo "    [WARN] 核心功能可能需要多次交互才能触达"
            fi

            # Check 4: Error state visible
            if [[ $(echo "$file_content" | grep -ci 'error\|错误\|失败\|start-error\|error-message\|err-msg\|error-state' || true) -gt 0 ]]; then
              echo "    [OK] 有错误状态展示"
            else
              echo "    [WARN] 缺少用户可见的错误状态"
            fi

            # Check 5: Mobile ready
            if [[ $(echo "$file_content" | grep -c 'viewport.*width=device-width' || true) -gt 0 ]]; then
              echo "    [OK] 移动端适配"
            else
              echo "    [FAIL] 缺少viewport meta标签"
              play_ok=false
            fi
          fi
        done < <(find "$path" -type f -print0 2>/dev/null)

        if [[ $html_files -eq 0 ]]; then
          # Check for non-HTML deliverables (APIs, documents)
          local doc_files=0
          while IFS= read -r -d '' f; do
            local vtype; vtype=$(detect_type "$f")
            case "$vtype" in
              md|json|yaml|yml)
                doc_files=$((doc_files + 1))
                local doc_content; doc_content=$(cat "$f")
                if echo "$doc_content" | grep -qi 'problem\|问题.*定义\|背景.*挑战\|为什么.*做'; then
                  echo "    [OK] 有清晰的问题陈述"
                else
                  echo "    [WARN] 缺少清晰的问题陈述"
                fi
                if echo "$doc_content" | grep -qi '指标\|metric\|KPIs\|成功率\|转化率\|目标'; then
                  echo "    [OK] 有成功指标"
                else
                  echo "    [WARN] 缺少可衡量的成功指标"
                fi
                if echo "$doc_content" | grep -qi '范围.*不\|不.*做\|out of scope\|不做\|非目标' 2>/dev/null; then
                  echo "    [OK] 定义了范围边界"
                else
                  echo "    [WARN] 未定义"不做什么"的范围边界"
                fi
                break
                ;;
            esac
          done < <(find "$path" -type f -print0 2>/dev/null)
          if [[ $doc_files -gt 0 ]]; then
            echo "  [OK] 文档类交付物检查完成"
          else
            echo "  [SKIP] 无可检查的文件类型"
          fi
        fi

        if $play_ok; then
          passed=$((passed + 1))
        else
          failed=$((failed + 1))
        fi
        ;;

      agent-standards)
        echo "  Agent标准检查 (from: $from, to: $to):"
        local agent_ok=true

        for agent_slug in "$from" "$to"; do
          # Find agent file from config using node
          local agent_file=""
          if command -v node &>/dev/null; then
            agent_file=$(node -e "
const d=JSON.parse(require('fs').readFileSync('$CONFIG','utf8'));
for(const a of(d.agents||[])){if(a.slug==='$agent_slug'){console.log('$REPO_ROOT/'+a.file);break}}
" 2>/dev/null)
          fi

          [[ -f "$agent_file" ]] || { echo "  [SKIP] $agent_slug: 未找到Agent定义文件"; continue; }

          # Extract section 9 (success metrics)
          local metrics
          metrics=$(awk '/^## 9\. 成功指標|^## 9\. 成功指标/{found=1; next} /^## 10\./{found=0} found' "$agent_file" 2>/dev/null)
          [[ -z "$metrics" ]] && { echo "  [SKIP] $agent_slug: 无成功指标定义"; continue; }

          echo "  -- $agent_slug 成功指标 --"

          # Metric: 中文内容 (game-qa-engineer)
          if echo "$metrics" | grep -qi '中文\|Chinese\|中文内容\|所有.*文字'; then
            for f in $(find "$path" -name "*.html" -type f 2>/dev/null); do
              if grep -qP '[\x{4e00}-\x{9fff}]' "$f" 2>/dev/null; then
                echo "    [OK] [$agent_slug] 包含中文内容"
              else
                echo "    [WARN] [$agent_slug] HTML文件缺少中文内容"
              fi
            done
          fi

          # Metric: 无console.error
          if echo "$metrics" | grep -qi 'console.error\|零错误\|zero error\|console.error'; then
            for f in $(find "$path" -name "*.html" -type f 2>/dev/null); do
              if grep -q 'console\.error' "$f" 2>/dev/null; then
                echo "    [FAIL] [$agent_slug] 包含console.error调用"
                agent_ok=false
              else
                echo "    [OK] [$agent_slug] 无console.error调用"
              fi
            done
          fi

          # Metric: AudioContext on user gesture (game-audio-engineer)
          if echo "$metrics" | grep -qi '音频.*触发\|Audio.*user gesture\|音频延迟\|audio.*click\|用户手势'; then
            for f in $(find "$path" -name "*.html" -type f 2>/dev/null); do
              if grep -q 'new AudioContext' "$f" 2>/dev/null; then
                if grep -q 'addEventListener.*click\|onclick\|touchstart.*AudioContext\|AudioContext.*click' "$f" 2>/dev/null; then
                  echo "    [OK] [$agent_slug] AudioContext由用户手势初始化"
                else
                  echo "    [WARN] [$agent_slug] AudioContext可能在构造时创建"
                fi
              fi
            done
          fi

          # Metric: 所有用户可见文字必须有中文 (game-qa-engineer)
          if echo "$metrics" | grep -qi '中文\|Chinese\|所有.*用户.*可见'; then
            for f in $(find "$path" -name "*.html" -type f 2>/dev/null); do
              if grep -qP '[\x{4e00}-\x{9fff}]' "$f" 2>/dev/null; then
                echo "    [OK] [$agent_slug] HTML包含中文字符"
              else
                echo "    [WARN] [$agent_slug] HTML未检测到中文字符"
              fi
            done
          fi

          # Metric: 延迟 < 20ms / 性能预算 (game-audio-engineer)
          if echo "$metrics" | grep -qi '延迟.*20\|latency\|performance budget\|内存占用\|memory.*budget'; then
            echo "    [INFO] [$agent_slug] 性能指标(延迟/内存/音效数) — 需运行时验证"
          fi
        done

        if $agent_ok; then
          echo "  [OK] 所有Agent标准检查通过"
          passed=$((passed + 1))
        else
          echo "  [FAIL] 部分Agent标准未满足"
          failed=$((failed + 1))
        fi
        ;;
    esac
    echo ""
  done

  echo "══════════════════════════════════"
  echo "  Gate结果: $passed 通过, $failed 失败"
  if [[ $failed -eq 0 ]]; then
    echo "  [OK] 所有质量门禁通过 — 可以接受"
  else
    echo "  [FAIL] $failed 个门禁未通过 — 拒绝接受"
  fi
  echo "══════════════════════════════════"

  # Return non-zero if any gate failed
  [[ $failed -eq 0 ]]
}

# ── list_gates ─────────────────────────────────────────────────────────

list_gates() {
  echo "质量门禁 (Quality Gates):"
  echo ""
  echo "  1. completeness     — 所有必需交付物已提供"
  echo "  2. syntax           — 所有文件语法验证通过"
  echo "  3. behavior         — 行为测试通过(事件绑定/守卫/错误处理)"
  echo "  4. playability      — 可玩性检查(教程/音效/UX流程/移动端)"
  echo "  5. agent-standards  — 相关Agent的成功标准逐条验证"
  echo ""
  echo "用法: guild gate --handoff <id> [--gate <1-5>]"
}

# ── cmd_accept ─────────────────────────────────────────────────────────

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
    fid=$(json_get "$f" "id")
    if [[ "$fid" == "$id" ]]; then
      json_file="$f"
      break
    fi
  done

  [[ -f "$json_file" ]] || die "Handoff #$id not found"

  echo "接收交接 #$id ..."
  echo ""

  # ── Precondition: status must be "ready" ──
  local current_status
  current_status=$(json_get "$json_file" "status")

  if [[ "$current_status" == "accepted" ]]; then
    err "无法接收: 交接已被接收"
    return 1
  fi

  # ── Guild Gate: run all 5 quality gates ──
  echo "━━━ 质量门禁检查 ━━━"
  echo ""
  if ! cmd_gate --handoff "$id"; then
    echo ""
    err "无法接收: 质量门禁未通过"
    echo "→ 请修复后重新 handoff"
    return 1
  fi
  echo "━━━ 门禁检查通过 ━━━"
  echo ""

  # ── Additional check: open critical bugs on this handoff ──
  local reject_reasons=""
  if [[ -d "$FEEDBACK_DIR" ]]; then
    local open_criticals=""
    for ff in "$FEEDBACK_DIR"/fb-*.json; do
      [[ -f "$ff" ]] || continue
      local fb_hid fb_sev fb_status fb_summary fb_id
      fb_hid=$(json_get "$ff" "handoff_id")
      fb_sev=$(json_get "$ff" "severity")
      fb_status=$(json_get "$ff" "status")
      fb_summary=$(json_get "$ff" "summary")
      fb_id=$(json_get "$ff" "id")

      if [[ "$fb_hid" == "$id" && "$fb_status" == "open" && "$fb_sev" == "critical" ]]; then
        open_criticals="${open_criticals}  - $fb_id ($fb_summary)\n"
      fi
    done
    if [[ -n "$open_criticals" ]]; then
      reject_reasons="${reject_reasons}有关联的未解决关键 bug:\n${open_criticals}"
    fi
  fi

  if [[ -n "$reject_reasons" ]]; then
    err "无法接收:"
    echo -e "$reject_reasons"
    echo "→ 请修复后重新 handoff"
    return 1
  fi

  # ── All gates passed — proceed with accept ──
  local accept_ok=false
  if command -v node &>/dev/null; then
    node -e "
const fs=require('fs');
let d=JSON.parse(fs.readFileSync('$json_file','utf8'));
if(d.to!=='$as_slug'){console.log('警告: 交接目标为 '+d.to+'，但你以 $as_slug 身份接收')}
d.status='accepted'; d.accepted_by='$as_slug';
fs.writeFileSync('$json_file',JSON.stringify(d,null,2)+'\n','utf8');
console.log('交接 #'+d.id+' 已接收 — $as_slug 开始工作');
" 2>/dev/null && accept_ok=true
  fi
  $accept_ok || ok "交接 #$id 已标记为接收"
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
  local pipeline="" path="" dry_run=false auto_yes=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --pipeline) pipeline="$2"; shift 2;;
      --path) path="$2"; shift 2;;
      --dry-run) dry_run=true; shift;;
      --yes) auto_yes=true; shift;;
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
    if $auto_yes; then
      echo "  (全自动模式 - 跳过用户提示)"
    else
      echo "  完成后按 Enter 继续（或输入 'skip' 跳过此阶段）..."
      if ! $dry_run; then
        read -r input
        [[ "$input" == "skip" ]] && { echo "  已跳过"; echo ""; continue; }
      fi
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

          # Write matched/missing to temp files for safe data transfer
          local mtmp; mtmp=$(mktemp); local mtmp2; mtmp2=$(mktemp)
          echo "$matched" > "$mtmp"
          echo "$missing" > "$mtmp2"

          if command -v node &>/dev/null; then
            node -e "
const fs=require('fs');
const matched=fs.readFileSync('$mtmp','utf8').trim().split('\n').filter(l=>l);
const missing=fs.readFileSync('$mtmp2','utf8').trim().split('\n').filter(l=>l);
const artifacts=[];
for(const l of matched){const p=l.split('|');if(p.length>=2)artifacts.push({name:p[0],file:'found',status:'provided'})}
for(const l of missing){const p=l.split('|');if(p.length>=3)artifacts.push({name:p[1],file:null,status:'missing',required:p[2]==='True'})}
const rt=artifacts.length,rp=artifacts.filter(a=>a.status==='provided').length;
const rm=artifacts.filter(a=>a.status==='missing'&&a.required!==false).length;
const rec={id:$id,from:'$from_slug',to:'$to_slug',timestamp:'$date',pipeline:'$pipeline',phase_from:'$current_phase',phase_to:'$next_phase',path:'$path',artifacts:artifacts,checklist:{required_total:rt,required_provided:rp,required_missing:rm},status:rm===0?'ready':'incomplete',accepted_by:null};
fs.mkdirSync('$HANDOFFS_DIR',{recursive:true});
fs.writeFileSync('$json_file',JSON.stringify(rec,null,2)+'\n','utf8');
console.log('      状态: '+rec.status);
console.log('      完整度: '+rp+'/'+rt);
if(rm>0){console.log('      [!!] 缺失 '+rm+' 项');for(const a of artifacts){if(a.status==='missing')console.log('           - '+a.name)}}
" 2>/dev/null
          fi
          rm -f "$mtmp" "$mtmp2"

          if [[ "$req_missing" -gt 0 ]]; then
            all_ready=false
          fi
        fi
      done
    done

    if ! $all_ready && ! $dry_run; then
      echo ""
      if ! $auto_yes; then
        echo "  ⚠️  存在缺失项。请补充后按 Enter 重试（或输入 'skip' 跳过）..."
        read -r input
        [[ "$input" == "skip" ]] && { echo "  已跳过"; echo ""; continue; }
      else
        echo "  (全自动模式 - 跳过缺失项检查)"
      fi
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

  # Show inbox summary
  echo ""
  echo "=== 收件箱摘要 ==="
  local any_inbox=false
  for d in "$REPO_ROOT/context/inbox"/*/; do
    [[ -d "$d" ]] || continue
    local a; a=$(basename "$d")
    local unread; unread=$(count_unread "$a")
    if [[ "$unread" -gt 0 ]]; then
      echo "  $a: $unread 未读"
      any_inbox=true
    fi
  done
  $any_inbox || echo "  所有收件箱为空"
}

# ── cmd_graph ──────────────────────────────────────────────────────────

# Usage: guild graph run   --graph <name> --path <dir> [--dry-run] [--yes]
#        guild graph status [--graph <name>]
#        guild graph show   <name>
#        guild graph list

cmd_graph() {
  local sub="${1:-run}"; shift || true

  case "$sub" in
    run)
      local graph="" path="" dry_run=false auto_yes=false
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --graph) graph="$2"; shift 2;;
          --path) path="$2"; shift 2;;
          --dry-run) dry_run=true; shift;;
          --yes) auto_yes=true; shift;;
          *) shift;;
        esac
      done
      [[ -n "$graph" ]] || die "--graph <name> is required"
      [[ -d "$path" ]] || die "--path must be a directory: $path"

      local graph_file="$REPO_ROOT/graphs/${graph}.yml"
      [[ -f "$graph_file" ]] || die "Graph not found: $graph"

      echo "╔══════════════════════════════════════════╗"
      echo "║  Graph Engine: $graph"
      echo "╚══════════════════════════════════════════╝"

      # Source and run graph engine
      source "$REPO_ROOT/scripts/graph-engine.sh"
      # Temp disable errexit/nounset for graph engine (it has its own error handling)
      set +euo pipefail
      run_graph "$graph_file" "$path" "$dry_run" "$auto_yes"
      local graph_rc=$?
      set -euo pipefail
      return $graph_rc
      ;;

    resume)
      local graph="" path="" auto_yes=false
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --graph) graph="$2"; shift 2;;
          --path) path="$2"; shift 2;;
          --yes) auto_yes=true; shift;;
          *) shift;;
        esac
      done
      [[ -n "$graph" ]] || die "--graph <name> is required"
      [[ -d "$path" ]] || die "--path must be a directory: $path"

      local graph_file="$REPO_ROOT/graphs/${graph}.yml"
      [[ -f "$graph_file" ]] || die "Graph not found: $graph"

      echo "╔══════════════════════════════════════════╗"
      echo "║  Graph Engine: $graph (恢复模式)"
      echo "╚══════════════════════════════════════════╝"

      source "$REPO_ROOT/scripts/graph-engine.sh"
      set +euo pipefail
      parse_graph "$graph_file" || return 1
      resume_graph "$graph" "$path" "$auto_yes"
      local graph_rc=$?
      set -euo pipefail
      return $graph_rc
      ;;

    status)
      local graph_name="${1:-}"
      # Show graph execution state
      if [[ -n "$graph_name" ]]; then
        local state_basename="$graph_name"
        local graph_file="$REPO_ROOT/graphs/${graph_name}.yml"
        if [[ -f "$graph_file" ]]; then
          state_basename=$(basename "$graph_file" .yml)
          state_basename=$(basename "$state_basename" .yaml)
        fi
        local state_file="/tmp/guild-graph-${state_basename}-state.json"
        # Fallback: try raw name
        [[ -f "$state_file" ]] || state_file="/tmp/guild-graph-${graph_name}-state.json"
        [[ -f "$state_file" ]] || { echo "图 \"$graph_name\" 无运行中的状态"; return 0; }
        if command -v node &>/dev/null; then
          node -e "
const d=JSON.parse(require('fs').readFileSync('$state_file','utf8'));
console.log('图状态: ${graph_name}');
console.log('迭代: '+d.current_iteration||0);console.log();
const icons={'pending':'⏳','running':'🔄','completed':'✅','failed':'❌','timeout':'⌛','exhausted':'💀'};
for(const[k,n]of Object.entries(d.nodes)){console.log('  '+(icons[n.status]||'⬜')+' '+k+': '+n.status)}
" 2>/dev/null || cat "$state_file"
        else
          cat "$state_file"
        fi
      else
        # List all running graph states
        local found=false
        for f in /tmp/guild-graph-*-state.json; do
          [[ -f "$f" ]] || continue
          found=true
          local gname; gname=$(basename "$f" | sed 's/guild-graph-//;s/-state.json//')
          echo "  图: $gname"
          if command -v node &>/dev/null; then
            node -e "
const d=JSON.parse(require('fs').readFileSync('$f','utf8'));
const ns=Object.values(d.nodes||{});
const done=ns.filter(n=>n.status==='completed').length;
const failed=ns.filter(n=>n.status==='failed').length;
console.log('    节点: '+done+'/'+ns.length+' 完成, '+failed+' 失败');
console.log('    迭代: '+(d.current_iteration||0));
" 2>/dev/null
          fi
        done
        $found || echo "  无运行中的图"
      fi
      ;;

    show)
      local graph="${1:-}"
      [[ -n "$graph" ]] || die "usage: guild graph show <name>"
      local graph_file="$REPO_ROOT/graphs/${graph}.yml"
      [[ -f "$graph_file" ]] || die "Graph not found: $graph"

      echo "=== Graph: $graph ==="
      echo ""
      echo "Nodes:"
      grep -E '^  [a-z]' "$graph_file" | sed 's/://;s/^/  /'
      echo ""
      echo "Edges:"
      grep -A1 '^edges:' "$graph_file" | tail -n +2
      ;;

    list)
      echo "可用图:"
      local any=false
      for f in "$REPO_ROOT/graphs"/*.yml; do
        [[ -f "$f" ]] || continue
        any=true
        local name; name=$(grep '^name:' "$f" | head -1 | sed 's/name: *//')
        local desc; desc=$(grep '^description:' "$f" | head -1 | sed 's/description: *//')
        echo "  $(basename "$f" .yml) — $name"
        [[ -n "$desc" ]] && echo "    $desc"
      done
      $any || echo "  (无图定义)"
      ;;

    *)
      echo "用法: guild graph [run|status|show|list]"
      echo ""
      echo "  run    — 执行图"
      echo "  status — 查看图执行状态"
      echo "  show   — 显示图结构"
      echo "  list   — 列出可用图"
      ;;
  esac
}

# ── cmd_verify ───────────────────────────────────────────────────────

# Usage: guild verify --type <type> --file <path>
#        guild verify --path <dir>
#        guild verify --handoff <id>

cmd_verify() {
  local verify_type="" file_path="" dir_path="" handoff_id=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --type) verify_type="$2"; shift 2;;
      --file) file_path="$2"; shift 2;;
      --path) dir_path="$2"; shift 2;;
      --handoff) handoff_id="$2"; shift 2;;
      *) shift;;
    esac
  done

  # Resolve handoff path
  if [[ -n "$handoff_id" ]]; then
    local json_file=""
    for f in "$HANDOFFS_DIR"/*.json; do
      [[ -f "$f" ]] || continue
      local fid
      fid=$(json_get "$f" "id")
      if [[ "$fid" == "$handoff_id" ]]; then
        json_file="$f"
        break
      fi
    done
    [[ -f "$json_file" ]] || die "Handoff #$handoff_id not found"
    dir_path=$(json_get "$json_file" "path")
    [[ -d "$dir_path" ]] || die "Handoff #$handoff_id path not found: $dir_path"
  fi

  if [[ -n "$file_path" ]]; then
    # Single file verify
    [[ -n "$verify_type" ]] || verify_type=$(detect_type "$file_path")
    [[ -n "$verify_type" ]] || die "Cannot detect type for $file_path. Use --type."
    echo "验证: $file_path"
    echo "  类型: $verify_type"
    if verify_file "$verify_type" "$file_path"; then
      ok "通过"
      return 0
    else
      return 1
    fi
  elif [[ -n "$dir_path" ]]; then
    # Directory verify
    echo "验证目录: $dir_path"
    echo ""
    if verify_directory "$dir_path"; then
      echo ""
      ok "目录验证通过"
      return 0
    else
      echo ""
      err "目录验证存在未通过项"
      return 1
    fi
  else
    die "需要 --type --file <path>, --path <dir>, 或 --handoff <id>"
  fi
}

# ── cmd_feedback ──────────────────────────────────────────────────────

# Usage: guild feedback --handoff <id> --type bug|improvement --summary "..." [--severity low|medium|high|critical] [--repro "..."]
#        guild feedback --list [--handoff <id>] [--status open|fixed]
#        guild feedback --fix <feedback-id> --handoff <new-handoff-id>

cmd_feedback() {
  local handoff_id="" fb_type="" severity="medium" summary="" repro=""
  local list_mode=false list_status="" fix_id="" fix_handoff=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --handoff) handoff_id="$2"; shift 2;;
      --type) fb_type="$2"; shift 2;;
      --severity) severity="$2"; shift 2;;
      --summary) summary="$2"; shift 2;;
      --repro) repro="$2"; shift 2;;
      --list) list_mode=true; shift;;
      --status) list_status="$2"; shift 2;;
      --fix) fix_id="$2"; shift 2;;
      *) shift;;
    esac
  done

  # List mode
  if $list_mode; then
    mkdir -p "$FEEDBACK_DIR"
    echo "=== 反馈列表 ==="
    echo ""
    local count=0
    for f in "$FEEDBACK_DIR"/fb-*.json; do
      [[ -f "$f" ]] || continue
      local id hid type severity summary status created
      id=$(json_get "$f" "id")
      hid=$(json_get "$f" "handoff_id")
      type=$(json_get "$f" "type")
      severity=$(json_get "$f" "severity")
      summary=$(json_get "$f" "summary")
      status=$(json_get "$f" "status")
      created=$(json_get "$f" "created")
      created="${created:0:19}"

      [[ -n "$id" ]] || continue
      [[ -n "$handoff_id" && "$hid" != "$handoff_id" ]] && continue
      [[ -n "$list_status" && "$status" != "$list_status" ]] && continue

      local icon
      case "$type" in
        bug) icon="🐛";;
        improvement) icon="💡";;
        *) icon="📋";;
      esac

      local sev_icon
      case "$severity" in
        critical) sev_icon="🔴";;
        high) sev_icon="🟠";;
        medium) sev_icon="🟡";;
        low) sev_icon="🟢";;
        *) sev_icon="⚪";;
      esac

      echo "  $icon $id [$sev_icon$severity] $summary"
      echo "    Handoff #$hid | 状态: $status | $created"
      echo ""
      count=$((count + 1))
    done
    [[ $count -eq 0 ]] && echo "  (无反馈记录)"
    return 0
  fi

  # Fix/link mode
  if [[ -n "$fix_id" ]]; then
    [[ -n "$fix_handoff" ]] || { handoff_id="${handoff_id:-}"; fix_handoff="$handoff_id"; }
    [[ -n "$fix_handoff" ]] || die "--handoff <new-handoff-id> is required with --fix"

    local fb_file="$FEEDBACK_DIR/$fix_id.json"
    [[ -f "$fb_file" ]] || die "反馈 $fix_id 不存在"

    local fix_ok=false
    if command -v node &>/dev/null; then
      node -e "
const fs=require('fs'),d=JSON.parse(fs.readFileSync('$fb_file','utf8'));
d.status='fixed';d.linked_fix_handoff='$fix_handoff';d.resolved=new Date().toISOString().replace(/\.[0-9]+Z/,'Z');
fs.writeFileSync('$fb_file',JSON.stringify(d,null,2)+'\n','utf8');
console.log('反馈 $fix_id 已标记为已修复（关联 Handoff #$fix_handoff）');
" 2>/dev/null && fix_ok=true
    fi
    $fix_ok || ok "反馈 $fix_id 已链接"
    return
  fi

  # Create mode
  [[ -n "$handoff_id" ]] || die "--handoff <id> is required"
  [[ -n "$fb_type" ]] || die "--type <bug|improvement> is required"
  [[ -n "$summary" ]] || die "--summary is required"

  mkdir -p "$FEEDBACK_DIR"

  local max=0
  for f in "$FEEDBACK_DIR"/fb-*.json; do
    [[ -f "$f" ]] || continue
    local num; num=$(basename "$f" .json | sed 's/fb-//')
    ((10#$num > max)) && max=$((10#$num))
  done
  local fb_id_num=$((max + 1))
  local fb_id
  fb_id=$(printf "fb-%03d" $fb_id_num)
  local date; date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local fb_file="$FEEDBACK_DIR/$fb_id.json"

  cat > "$fb_file" << JSONEOF
{
  "id": "$fb_id",
  "handoff_id": $handoff_id,
  "type": "$fb_type",
  "severity": "$severity",
  "summary": "$summary",
  "repro_steps": "$repro",
  "status": "open",
  "linked_fix_handoff": null,
  "created": "$date",
  "resolved": null
}
JSONEOF

  ok "反馈已记录: $fb_id ($summary)"
  echo "  文件: $fb_file"
}

# ── cmd_changelog ──────────────────────────────────────────────────────

# Usage: guild changelog [--since <version|date>]

cmd_changelog() {
  local since=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --since) since="$2"; shift 2;;
      *) shift;;
    esac
  done

  local -a handoff_files=()
  for f in "$HANDOFFS_DIR"/*.json; do
    [[ -f "$f" ]] || continue
    local status
    status=$(json_get "$f" "status")
    [[ "$status" != "accepted" ]] && continue
    handoff_files+=("$f")
  done

  if [[ ${#handoff_files[@]} -eq 0 ]]; then
    echo "暂无已接受的交接记录。"
    return
  fi

  # Sort by timestamp
  local sorted
  sorted=$(for f in "${handoff_files[@]}"; do
    if command -v node &>/dev/null; then
      node -e "
const d=JSON.parse(require('fs').readFileSync('$f','utf8'));
console.log(d.timestamp+' '+d.id+' '+d.from+' '+d.to+' '+(d.message||''));
" 2>/dev/null
    fi
  done | sort)

  echo "变更日志"
  echo "========"
  echo ""

  local count=0
  local version_minor=0

  while IFS=' ' read -r ts id from to msg; do
    [[ -z "$ts" ]] && continue
    count=$((count + 1))
    if (( count % 5 == 1 )); then
      version_minor=$((version_minor + 1))
      local date_str; date_str=$(echo "$ts" | cut -d'T' -f1)
      echo ""
      echo "v0.${version_minor}.0 ($date_str)"
      echo "------------------------------"
    fi

    # Check if this handoff is linked to any feedback
    local fb_ref=""
    for ff in "$FEEDBACK_DIR"/fb-*.json; do
      [[ -f "$ff" ]] || continue
      local linked
      linked=$(json_get "$ff" "linked_fix_handoff")
      if [[ -n "$linked" ]]; then
        # Check if linked handoff id matches this handoff's id as string
        local h_id_str="$id"
        if [[ "$linked" == "$h_id_str" ]]; then
          local fb_summary
          fb_summary=$(json_get "$ff" "summary")
          local fb_id_name
          fb_id_name=$(json_get "$ff" "id")
          fb_ref="$fb_id_name: $fb_summary"
          break
        fi
      fi
    done

    if [[ -n "$fb_ref" ]]; then
      echo "  ✅ 修复: $fb_ref"
      [[ -n "$msg" ]] && echo "     $msg"
      echo "     [handoff #$id]"
    else
      local display_msg="${msg:-交付完成}"
      echo "  ✅ $from → $to: $display_msg [handoff #$id]"
    fi
  done <<< "$sorted"
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
        affected_count=$((affected_count + 1))
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
  local idx_ok=false
  if command -v node &>/dev/null; then
    node -e "
const fs=require('fs');
const idx=JSON.parse(fs.readFileSync('$idx','utf8'));
idx.updated='$timestamp';
idx.decisions.push({id:$id,agent:'$agent_slug',type:'$type',topic:'$topic',file:'$filename',status:'active'});
fs.writeFileSync('$tmpidx',JSON.stringify(idx,null,2)+'\n','utf8');
" 2>/dev/null && idx_ok=true
  fi
  if $idx_ok; then
    mv "$tmpidx" "$idx"
  else
    ok "索引更新跳过。决策已保存至: $filepath"
    return 0
  fi

  echo ""
  ok "决策 #$id 已记录: $agent_slug / $type / $topic"
  ok "文件: $filename"
  if [[ -n "$affected" ]]; then echo "  受影响方: $affected"; fi

  # Auto-notify affected agents about this decision
  if [[ -n "$affected" ]]; then
    echo "  📨 正在通知受影响方..."
    for a in $affected; do
      add_inbox_item "$a" "decision_relevant" "$agent_slug"         "topic=$topic"         "$agent_slug 做出了关于 $topic 的决策: $summary"         "确认你的工作是否受此决策影响"
      echo "    → 已通知 $a"
    done
  fi
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
      local types=""
      if command -v node &>/dev/null; then
        types=$(node -e "
const idx=JSON.parse(require('fs').readFileSync('$idx','utf8'));
const types={};
for(const d of(idx.decisions||[])){if(!types[d.type])types[d.type]=[];types[d.type].push(d)}
for(const t of Object.keys(types).sort())console.log(t+':'+types[t].length);
" 2>/dev/null)
      fi

      if [[ -n "$types" ]]; then
        echo "$types" | while IFS=':' read -r t count; do
          echo "  $t ($count 条)"
          # List decisions of this type
          if command -v node &>/dev/null; then
            node -e "
const idx=JSON.parse(require('fs').readFileSync('$idx','utf8'));
for(const d of(idx.decisions||[])){if(d.type==='$t')console.log('    #'+d.id+' ['+d.agent+'] '+d.topic+' ('+d.status+')')}
" 2>/dev/null
          fi
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
      local check1_output="CONFLICT_COUNT=0"
      if command -v node &>/dev/null; then
        check1_output=$(node -e "
const idx=JSON.parse(require('fs').readFileSync('$idx','utf8'));
const topics={};
for(const d of(idx.decisions||[])){if(d.status==='active'){if(!topics[d.topic])topics[d.topic]=[];topics[d.topic].push(d)}}
let found=0;
for(const[t,decs]of Object.entries(topics)){
  if(decs.length>1){const agents=new Set(decs.map(d=>d.agent));if(agents.size>1){
    found++;console.log('  ⚠️  冲突: '+t);
    for(const d of decs)console.log('      #'+d.id+' ['+d.agent+']: '+d.topic);
  }}
}
console.log('CONFLICT_COUNT='+found);
" 2>/dev/null) || check1_output="CONFLICT_COUNT=0"
      else
        echo "  (无法运行冲突检查 — node required)"
      fi

      # Print check output (excluding the CONFLICT_COUNT marker)
      echo "$check1_output" | grep -v "^CONFLICT_COUNT="
      local conflict_count; conflict_count=$(echo "$check1_output" | grep "^CONFLICT_COUNT=" | cut -d= -f2)
      conflict_count=${conflict_count:-0}
      if [[ "$conflict_count" -gt 0 ]]; then
        conflicts=$conflict_count
        # Auto-notify conflicting agents from context check
        local conflict_notify_done=false
        for f in "$REPO_ROOT/context/decisions"/*.json; do
          [[ -f "$f" ]] || continue
          local dec_agent; dec_agent=$(grep -o '"agent": "[^"]*"' "$f" | head -1 | cut -d'"' -f4)
          local dec_topic; dec_topic=$(grep -o '"topic": "[^"]*"' "$f" | head -1 | cut -d'"' -f4)
          for g in "$REPO_ROOT/context/decisions"/*.json; do
            [[ -f "$g" ]] || continue
            [[ "$f" == "$g" ]] && continue
            local g_agent; g_agent=$(grep -o '"agent": "[^"]*"' "$g" | head -1 | cut -d'"' -f4)
            local g_topic; g_topic=$(grep -o '"topic": "[^"]*"' "$g" | head -1 | cut -d'"' -f4)
            if [[ "$dec_topic" == "$g_topic" && "$dec_agent" != "$g_agent" ]]; then
              $conflict_notify_done && continue
              conflict_notify_done=true
          add_inbox_item "$dec_agent" "conflict_active" "$g_agent" \
            "topic=$dec_topic" \
            "与 $g_agent 在 $dec_topic 上存在矛盾决策" \
            "基于决策权重协商解决。运行 guild resolve --topic '$dec_topic'"
          add_inbox_item "$g_agent" "conflict_active" "$dec_agent" \
            "topic=$g_topic" \
            "与 $dec_agent 在 $g_topic 上存在矛盾决策" \
            "基于决策权重协商解决。运行 guild resolve --topic '$g_topic'"
            fi
          done
        done
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

# ── cmd_inbox ──────────────────────────────────────────────────────

cmd_inbox() {
  local agent="" unread_only=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --agent) agent="$2"; shift 2;;
      --unread) unread_only=true; shift;;
      *) shift;;
    esac
  done

  if [[ -n "$agent" ]]; then
    local agent_slug; agent_slug="$(resolve_agent "$agent")"
    local inbox_dir="$REPO_ROOT/context/inbox/${agent_slug}"
    if [[ ! -d "$inbox_dir" ]] || [[ -z "$(ls "$inbox_dir"/*.json 2>/dev/null)" ]]; then
      echo "  ${agent_slug} 收件箱为空"
      return 0
    fi

    local unread; unread=$(count_unread "$agent_slug")
    local total; total=$(ls "$inbox_dir"/*.json 2>/dev/null | wc -l)
    echo "=== ${agent_slug} 的收件箱 ==="
    echo "  未读: $unread / 总计: $total"
    echo ""

    for f in "$inbox_dir"/*.json; do
      [[ -f "$f" ]] || continue
      local is_read; is_read=$(grep -o '"read": [a-z]*' "$f" | cut -d' ' -f2)
      $unread_only && [[ "$is_read" == "true" ]] && continue

      local itype; itype=$(grep -o '"type": "[^"]*"' "$f" | head -1 | cut -d'"' -f4)
      local ifrom; ifrom=$(grep -o '"from": "[^"]*"' "$f" | head -1 | cut -d'"' -f4)
      local isummary; isummary=$(grep -o '"summary": "[^"]*"' "$f" | head -1 | cut -d'"' -f4)
      local iaction; iaction=$(grep -o '"action": "[^"]*"' "$f" | head -1 | cut -d'"' -f4)

      local icon="📌"
      case "$itype" in
        handoff_incoming) icon="📨";;
        conflict_active) icon="⚠️";;
        decision_relevant) icon="📋";;
      esac

      local read_mark="🔵"
      [[ "$is_read" == "true" ]] && read_mark="  "

      echo "$read_mark $icon [$ifrom] $isummary"
      echo "      → $iaction"
      echo ""
    done
  else
    echo "=== 所有收件箱 ==="
    local any=false
    for d in "$REPO_ROOT/context/inbox"/*/; do
      [[ -d "$d" ]] || continue
      local a; a=$(basename "$d")
      local unread; unread=$(count_unread "$a")
      if [[ "$unread" -gt 0 ]]; then
        echo "  $a: $unread 未读"
        any=true
      fi
    done
    $any || echo "  所有收件箱为空"
  fi
}

# ── cmd_read ──────────────────────────────────────────────────────

cmd_read() {
  local agent="" all=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --agent) agent="$2"; shift 2;;
      --all) all=true; shift;;
      *) shift;;
    esac
  done

  [[ -n "$agent" ]] || die "--agent is required"
  local agent_slug; agent_slug="$(resolve_agent "$agent")"
  local inbox_dir="$REPO_ROOT/context/inbox/${agent_slug}"
  [[ -d "$inbox_dir" ]] || { echo "  收件箱为空"; return 0; }

  mark_all_read "$agent_slug"
  ok "已标记 ${agent_slug} 的所有消息为已读"
}

# ── cmd_resolve ────────────────────────────────────────────────────

cmd_resolve() {
  local topic=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --topic) topic="$2"; shift 2;;
      *) shift;;
    esac
  done

  [[ -n "$topic" ]] || die "--topic is required"

  echo "=== 冲突解决: $topic ==="

  # Find conflicting decisions
  local parties=""
  for f in "$REPO_ROOT/context/decisions"/*.json; do
    [[ -f "$f" ]] || continue
    local t; t=$(grep -o '"topic": "[^"]*"' "$f" | head -1 | cut -d'"' -f4)
    [[ "$t" == "$topic" ]] || continue
    local a; a=$(grep -o '"agent": "[^"]*"' "$f" | head -1 | cut -d'"' -f4)
    local s; s=$(grep -o '"summary": "[^"]*"' "$f" | head -1 | cut -d'"' -f4)
    echo "  $a: $s"
    parties="$parties $a"
  done

  if [[ -z "$parties" ]]; then
    echo "  未找到与主题“$topic”相关的决策"
    return 0
  fi

  echo ""
  echo "  决策权重分析:"

  # Determine authority based on topic keywords
  local authority=""
  case "$topic" in
    *api*|*API*|*schema*|*database*|*db*|*model*|*endpoint*|*auth*|*认证*|*api*)
      # api-design, backend related
      if echo "$parties" | grep -q "backend-architect"; then
        authority="backend-architect"
      fi
      ;;
    *ui*|*UX*|*design*|*component*|*style*|*layout*|*interface*|*ui*|*设计*)
      if echo "$parties" | grep -q "ui-designer"; then
        authority="ui-designer"
      elif echo "$parties" | grep -q "creative-director"; then
        authority="creative-director"
      fi
      ;;
    *game*|*mechanic*|*gameplay*|*循环*|*game*)
      if echo "$parties" | grep -q "game-designer"; then
        authority="game-designer"
      fi
      ;;
    *scope*|*feature*|*priority*|*prd*|*范围*|*功能*)
      if echo "$parties" | grep -q "product-manager"; then
        authority="product-manager"
      fi
      ;;
    *security*|*auth*|*permission*|*安全*)
      if echo "$parties" | grep -q "security-engineer"; then
        authority="security-engineer"
      fi
      ;;
  esac

  if [[ -n "$authority" ]]; then
    echo "  → 此领域拥有最终决策权的 Agent: $authority"
    echo "  建议: 由 $authority 做出最终裁决"
    echo "  处理方式:"
    echo "    1. $authority 运行 guild decide 记录最终决策"
    echo "    2. 受影响方确认并更新自己的工作"
  else
    echo "  警告: 无法自动确定此领域的决策权威"
    echo "  建议: 由 PM 协调决策或运行 guild decide --authority <agent> 人工指定"
  fi

  echo ""
  echo "  受影响方应被通知最终决定"
}

# ── cmd_cleanup ──────────────────────────────────────────────────────

# Usage: guild cleanup [--stale]
cmd_cleanup() {
  local stale_mode=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --stale) stale_mode=true; shift;;
      *) shift;;
    esac
  done

  # Gather stuck handoffs (incomplete or needs_fix)
  local -a stale_items=()
  for f in "$HANDOFFS_DIR"/*.json; do
    [[ -f "$f" ]] || continue
    local sid sfrom sto sstatus sts
    sid=$(json_get "$f" "id")
    sfrom=$(json_get "$f" "from")
    sto=$(json_get "$f" "to")
    sstatus=$(json_get "$f" "status")
    sts=$(json_get "$f" "timestamp")
    sts="${sts:0:19}"
    [[ -n "$sid" ]] || continue
    [[ "$sstatus" == "incomplete" || "$sstatus" == "needs_fix" ]] || continue
    local septokh
    septokh=$(date -d "$(echo "$sts" | tr 'T' ' ')" +%s 2>/dev/null || echo 0)
    local now_epoch
    now_epoch=$(date +%s)
    local age_days=$(( (now_epoch - septokh) / 86400 ))
    stale_items+=("$sid|$sfrom|$sto|$sstatus|$age_days|$f")
  done

  if [[ ${#stale_items[@]} -eq 0 ]]; then
    echo "  No stale handoffs found."
    return 0
  fi

  if $stale_mode; then
    local archive_dir="$HANDOFFS_DIR/.archive"
    mkdir -p "$archive_dir"
    echo "Archiving stale handoffs:"
    for entry in "${stale_items[@]}"; do
      local sid sfrom sto sstatus age_days fpath
      IFS='|' read -r sid sfrom sto sstatus age_days fpath <<< "$entry"
      mv "$fpath" "$archive_dir/"
      echo "  Archived #$sid: $sfrom → $sto ($sstatus, ${age_days}d old)"
    done
  else
    echo "Stale handoffs (incomplete/needs_fix):"
    for entry in "${stale_items[@]}"; do
      local sid sfrom sto sstatus age_days fpath
      IFS='|' read -r sid sfrom sto sstatus age_days fpath <<< "$entry"
      if (( age_days >= 7 )); then
        echo "  ⚠ #$sid: $sfrom → $sto ($sstatus, ${age_days}d old)"
      else
        echo "    #$sid: $sfrom → $sto ($sstatus, ${age_days}d old)"
      fi
    done
    echo ""
    echo "Run 'guild cleanup --stale' to archive them."
  fi
}

# ── Main ────────────────────────────────────────────────────────────

if [[ $# -eq 0 ]]; then
  echo "AgentGraph Handoff Engine"
  echo ""
  echo "Commands:"
  echo "  guild graph     — 图引擎 (run/status/show/list)"
  echo "  guild handoff   — 创建交接 (Agent A → Agent B)"
  echo "  guild check     — 检查交接完整性"
  echo "  guild status    — 查看所有交接状态"
  echo "  guild accept    — 接收交接并开始工作（自动运行质量门禁）"
  echo "  guild verify    — 验证交付物质量（按文件类型检查）"
  echo "  guild feedback  — 记录/列出/链接 bug 和改进反馈"
  echo "  guild changelog — 基于已接受的交接生成变更日志"
  echo "  guild list      — 列出契约或交接记录"
  echo "  guild decide    — 记录结构化决策 (ADR)"
  echo "  guild context   — 显示/检查决策图谱和冲突"
  echo "  guild run       — 执行流水线"
  echo "  guild inbox     — 查看 Agent 收件箱"
  echo "  guild read      — 标记收件箱消息为已读"
  echo "  guild resolve   — 基于决策权重自动解决冲突"
  echo "  guild cleanup   — 查看/清理过期交接（--stale 执行归档）"
  echo "  guild gate      — 运行质量门禁 (completeness/syntax/behavior/playability/agent-standards)"
  echo "  guild test      — 运行交付物行为测试（超越静态验证）"
  echo ""
  echo "Run 'guild <command> --help' for details."
  exit 0
fi

CMD="$1"
shift

case "$CMD" in
  graph)     cmd_graph "$@";;
  handoff)   cmd_handoff "$@";;
  check)     cmd_check "$@";;
  status)    cmd_status "$@";;
  accept)    cmd_accept "$@";;
  verify)    cmd_verify "$@";;
  feedback)  cmd_feedback "$@";;
  changelog) cmd_changelog "$@";;
  cleanup)   cmd_cleanup "$@";;
  list)      cmd_list "$@";;
  run)       cmd_run "$@";;
  decide)    cmd_decide "$@";;
  context)   cmd_context "$@";;
  inbox)     cmd_inbox "$@";;
  read)      cmd_read "$@";;
  resolve)   cmd_resolve "$@";;
  test)      cmd_test "$@";;
  gate)      cmd_gate "$@";;
  self-test) bash "$SCRIPT_DIR/self-test.sh";;
  --help|-h|help)
    sed -n '3,14p' "$0" | sed 's/^# \{0,1\}//'
    ;;
  *) die "Unknown command: $CMD. Valid: graph, handoff, check, status, accept, verify, feedback, changelog, cleanup, list, run, decide, context, inbox, read, resolve, gate, self-test, test";;
esac
