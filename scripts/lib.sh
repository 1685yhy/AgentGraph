#!/usr/bin/env bash
#
# lib.sh — shared pure-bash helpers for AgentGraph scripts.
# Bash 3.2+ compatible. No external dependencies.
# Groups: frontmatter parsers, slug helpers, terminal helpers.

# ── JSON helpers ─────────────────────────────────────────────────────

# json_get — read a single top-level field from a JSON file
# Usage: json_get <file> <field> [default]
# Returns: the field value (string/number), or default
json_get() {
  local file="$1" field="$2" default="${3:-}"
  # Use node if available (fast path)
  if command -v node &>/dev/null; then
    local val
    val=$(node -e "const d=JSON.parse(require('fs').readFileSync('$file','utf8'));console.log(d['$field']===undefined?'$default':String(d['$field']))" 2>/dev/null)
    if [[ $? -eq 0 && -n "$val" ]]; then
      echo "$val"
      return
    fi
  fi
  # Pure bash fallback — works for simple string/number values
  local val
  val=$(grep -o "\"${field}\"[[:space:]]*:[[:space:]]*[^\",}\n]*" "$file" 2>/dev/null | head -1 | sed 's/.*:[[:space:]]*//' | tr -d '"' | tr -d ',' | xargs)
  echo "${val:-$default}"
}

# json_validate — check if a file is valid JSON
json_validate() {
  local file="$1"
  # node fast path
  if command -v node &>/dev/null; then
    node -e "JSON.parse(require('fs').readFileSync('$file','utf8'))" 2>/dev/null && return 0 || return 1
  fi
  return 1
}

# js_syntax_check — validate JS/TS syntax
js_syntax_check() {
  local file="$1"
  command -v node &>/dev/null || { echo "  (node not available — skip JS syntax check)"; return 0; }
  node --check "$file" 2>&1 && return 0 || return 1
}

# ── Frontmatter / slug helpers ────────────────────────────────────

# get_field <field> <file> — value of a YAML frontmatter field (first match).
get_field() {
  local field="$1" file="$2"
  awk -v f="$field" '
    /^---$/ { fm++; next }
    fm == 1 && $0 ~ "^" f ": " { sub("^" f ": ", ""); print; exit }
  ' "$file"
}

# get_body <file> — file contents with the leading frontmatter block stripped.
get_body() {
  awk 'BEGIN{fm=0} /^---$/{fm++; next} fm>=2{print}' "$1"
}

# slugify <string> — "Frontend Engineer" -> "frontend-engineer"
slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//'
}

# agent_slug <file> — slug derived from the file's `name:` frontmatter.
agent_slug() {
  local name; name="$(get_field name "$1")"
  [[ -n "$name" ]] && slugify "$name"
}

# is_agent_file <file> — true if the file starts with a YAML frontmatter fence.
is_agent_file() {
  [[ -f "$1" ]] && [[ "$(head -1 "$1")" == "---" ]]
}

# get_agent_files <config_json> — list agent files from guild.config.json.
# Uses awk to parse the JSON (no jq dependency).
get_agent_files() {
  local config="$1"
  awk -F'"' '/"file":/ { print $12 }' "$config"
}

# get_agent_slugs <config_json> — list agent slugs from guild.config.json.
get_agent_slugs() {
  local config="$1"
  awk -F'"' '/"slug":/ { print $4 }' "$config"
}

# ── Inbox helpers ─────────────────────────────────────────────────

# add_inbox_item <agent> <type> <from> <meta> <summary> <action>
# Creates a per-message JSON file in context/inbox/<agent>/ — no python3 needed.
add_inbox_item() {
  local agent="$1" type="$2" from="$3" meta="$4" summary="$5" action="$6"
  local inbox_dir="$REPO_ROOT/context/inbox/${agent}"
  mkdir -p "$inbox_dir"

  local timestamp; timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local msg_id="msg-$(date +%s)-$((RANDOM % 1000))"
  local msg_file="$inbox_dir/${msg_id}.json"

  cat > "$msg_file" << JSONEOF
{
  "id": "$msg_id",
  "agent": "$agent",
  "type": "$type",
  "from": "$from",
  "timestamp": "$timestamp",
  "summary": "$summary",
  "action": "$action",
  "meta": "$meta",
  "read": false
}
JSONEOF
  echo "    📨 已通知 $agent"
}

# count_unread <agent-slug> — number of unread inbox messages
count_unread() {
  local agent="$1"
  local inbox_dir="$REPO_ROOT/context/inbox/${agent}"
  local count=0
  for f in "$inbox_dir"/*.json; do
    [[ -f "$f" ]] || continue
    grep -q '"read": false' "$f" 2>/dev/null && count=$((count + 1))
  done
  echo $count
}

# mark_all_read <agent-slug> — mark all inbox messages as read
mark_all_read() {
  local agent="$1"
  local inbox_dir="$REPO_ROOT/context/inbox/${agent}"
  for f in "$inbox_dir"/*.json; do
    [[ -f "$f" ]] || continue
    sed -i 's/"read": false/"read": true/' "$f" 2>/dev/null
  done
}

# ── Terminal helpers ──────────────────────────────────────────────

if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-}" != "dumb" ]]; then
  C_GREEN=$'\033[0;32m'
  C_YELLOW=$'\033[1;33m'
  C_RED=$'\033[0;31m'
  C_BOLD=$'\033[1m'
  C_RESET=$'\033[0m'
else
  C_GREEN=''; C_YELLOW=''; C_RED=''; C_BOLD=''; C_RESET=''
fi

ok()   { printf "${C_GREEN}[OK]${C_RESET}  %s\n" "$*"; }
warn() { printf "${C_YELLOW}[!!]${C_RESET}  %s\n" "$*"; }
err()  { printf "${C_RED}[ERR]${C_RESET} %s\n" "$*" >&2; }

# die <msg> — print error and exit 1.
die() { err "$*"; exit 1; }

# ── Contract helpers (Phase 2a) ──────────────────────────────────

# yaml_escape <string> — escape double-quote and backslash for YAML.
yaml_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# parse_contract <agent_file> — extract structured contract from section 13.
# Outputs YAML fragment to stdout.
# Produces cleaner item names by extracting text before —— (Chinese em dash),
# truncating long names, sanitizing markdown formatting, and escaping YAML special chars.
# Handles role-grouped delivery paragraphs (**对XX交付**：content).
parse_contract() {
  local file="$1"
  local body; body="$(get_body "$file")"
  local slug; slug="$(agent_slug "$file")"

  # Extract section 13 (after "## 13." heading, until next ## heading or EOF)
  local section13
  section13=$(echo "$body" | awk '/^## 13\./{found=1; next} /^## /{if(found) exit} found{print}')

  # If no section 13 found, output empty contracts
  if [[ -z "$section13" ]]; then
    echo "  ${slug}:"
    echo "    delivers: []"
    echo "    requires: []"
    return
  fi

  echo "  ${slug}:"
  echo "    delivers:"

  # Extract deliverables:
  #   Pattern 1 — Bullet items after "我向下游交付/我交付/I deliver" header
  #   Pattern 2 — Role-grouped delivery paragraphs (**对XX交付**：content) split by 。
  echo "$section13" | awk -v q='"' '
    BEGIN { in_del = 0 }

    # short_name: extract concise name from a description string
    function short_name(s,    idx) {
      if (index(s, "——") > 0) {
        idx = index(s, "——")
        s = substr(s, 1, idx - 1)
      }
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      if (length(s) > 60)
        s = substr(s, 1, 57) "..."
      return s
    }

    # yaml_escape: escape double-quotes and backslashes for YAML double-quoted strings
    function yaml_escape(s) {
      gsub(/\\/, "\\\\", s)
      gsub(/"/, "\\" q, s)
      return s
    }

    # Enter/exit delivery section
    /我向下游交付|我交付|I deliver/ { in_del = 1; next }
    /^\*\*我需要|我需要上游提供|I require/ { in_del = 0; next }
    in_del == 0 { next }

    # Pattern 1: Bullet items (e.g., "- 包含问题陈述和成功标准的 PRD")
    /^- / {
      item = $0
      sub(/^- [[:space:]]*/, "", item)
      gsub(/\*\*/, "", item)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", item)
      if (length(item) < 2) next

      name = short_name(item)
      if (length(name) < 2) name = item

      printf "      - name: %s%s%s\n        description: %s%s%s\n", \
        q, yaml_escape(name), q, q, yaml_escape(item), q
      next
    }

    # Pattern 2: Role-grouped delivery paragraphs (e.g., "**对设计团队交付**：")
    /^\*\*对[^*]+\*\*[：:]/ {
      line = $0
      sub(/^\*\*对[^*]+\*\*[：:][[:space:]]*/, "", line)
      gsub(/\*\*/, "", line)
      if (length(line) < 4) next

      n = split(line, sentences, "。")
      for (i = 1; i <= n; i++) {
        s = sentences[i]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
        if (length(s) < 4) continue

        sname = short_name(s)
        if (length(sname) < 2) sname = s

        printf "      - name: %s%s%s\n        description: %s%s%s\n", \
          q, yaml_escape(sname), q, q, yaml_escape(s), q
      }
      next
    }
  '

  echo "    requires:"

  # Extract requirements (lines after "我需要上游提供" with "- **Role**：description" format)
  echo "$section13" | awk -v q='"' '
    BEGIN { in_rq = 0 }

    function short_name(s,    idx) {
      if (index(s, "——") > 0) {
        idx = index(s, "——")
        s = substr(s, 1, idx - 1)
      }
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      if (length(s) > 60)
        s = substr(s, 1, 57) "..."
      return s
    }

    function yaml_escape(s) {
      gsub(/\\/, "\\\\", s)
      gsub(/"/, "\\" q, s)
      return s
    }

    # Enter/exit requires section
    # NOTE: DO NOT use bare "|我需要" as a trigger — it matches descriptions
    # containing "我需要" (e.g., 叙事设计师的描述: "我需要知道故事中的世界规则")
    # anchored to line start) to handle agents using "**我需要：**" format
    /^\*\*我需要|我需要上游提供|I require/ { in_rq = 1; next }
    /我向下游交付|我交付|I deliver/ { in_rq = 0; next }
    in_rq == 0 { next }

    # Match: "- **Role Name**：description"
    /^- [[:space:]]*\*\*/ {
      if (match($0, /\*\*[^*]+\*\*/)) {
        role = substr($0, RSTART, RLENGTH)
        gsub(/\*\*/, "", role)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", role)

        desc = substr($0, RSTART + RLENGTH)
        sub(/^[：:][[:space:]]*/, "", desc)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", desc)
        gsub(/\*\*/, "", desc)

        name = short_name(desc)
        if (length(name) < 2) name = desc
        if (length(name) > 60) name = substr(name, 1, 57) "..."
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)

        if (length(role) > 1 && length(role) < 60 && length(name) > 0) {
          printf "      - from: %s%s%s\n        items:\n", q, yaml_escape(role), q
          printf "          - name: %s%s%s\n            description: %s%s%s\n            required: true\n", \
            q, yaml_escape(name), q, q, yaml_escape(desc), q
        }
      }
      next
    }
  '
}

# ── Agent resolution ──────────────────────────────────────────────────
# resolve_agent <name-or-slug> — normalize agent name to slug
# Supports: exact slug, partial match, abbreviation (pm→product-manager)
# Uses CONFIG from nexus.sh or falls back to REPO_ROOT/guild.config.json
resolve_agent() {
  local input="$1"
  local config="${CONFIG:-$REPO_ROOT/guild.config.json}"
  local slug

  # Try direct slug match
  if grep -q "\"slug\": \"$input\"" "$config"; then
    echo "$input"
    return
  fi

  # Try slugify
  slug=$(echo "$input" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//')
  if grep -q "\"slug\": \"$slug\"" "$config"; then
    echo "$slug"
    return
  fi

  # Try partial match on slug
  local match
  match=$(awk -F'"' '/"slug":/{print $4}' "$config" | grep "$slug" | head -1)
  if [[ -n "$match" ]]; then
    echo "$match"
    return
  fi

  # Try abbreviation: first letter of each hyphen-separated segment
  local all_slugs
  all_slugs=$(awk -F'"' '/"slug":/{print $4}' "$config")
  while IFS= read -r s; do
    [[ -z "$s" ]] && continue
    local abbr=""
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

# resolve_by_display_name <display-name> — map agent display name to slug
# e.g., "UI 设计师" → "ui-designer", "前端工程师" → "frontend-engineer"
resolve_by_display_name() {
  local display="$1"
  local config="${CONFIG:-$REPO_ROOT/guild.config.json}"

  # Build mapping: iterate over all agent .md files, read their 'short:' field
  local agents_dir="${REPO_ROOT}/agents"
  for md_file in "$agents_dir"/*/*.md "$agents_dir"/*/*/*.md; do
    [[ -f "$md_file" ]] || continue
    local short; short=$(grep "^short:" "$md_file" 2>/dev/null | head -1 | sed 's/^short:[[:space:]]*//')
    [[ "$short" != "$display" ]] && continue
    # Extract slug from filename: agents/design/ui-designer.md → ui-designer
    local slug; slug=$(basename "$md_file" .md)
    echo "$slug"
    return 0
  done

  echo ""
}

# ── Display name / slug mapping ──────────────────────────────────────

# build_display_name_slug_map — outputs "display_name|slug" lines for all agents.
# E.g., "产品经理|product-manager"
build_display_name_slug_map() {
  local agents_dir="${REPO_ROOT}/agents"
  for md_file in "$agents_dir"/*/*.md "$agents_dir"/*/*/*.md; do
    [[ -f "$md_file" ]] || continue
    local short; short=$(grep "^short:" "$md_file" 2>/dev/null | head -1 | sed 's/^short:[[:space:]]*//; s/[[:space:]]*$//')
    [[ -z "$short" ]] && continue
    local slug; slug=$(basename "$md_file" .md)
    echo "${short}|${slug}"
  done
}

# get_requires_filtered <downstream-slug> <upstream-slug-or-display>
# Gets requirements for downstream that come from upstream agent only.
# Maps upstream display names (e.g., "产品经理") to slugs (e.g., "product-manager").
# Outputs: filtered lines (from|name|required) plus a final __IGNORED__:<count> line.
get_requires_filtered() {
  local downstream="$1" upstream_input="$2"
  local all_reqs; all_reqs=$(get_requires "$downstream")
  [[ -z "$all_reqs" ]] && { echo "__IGNORED__:0"; return; }

  # Build display name -> slug mapping
  local name_map; name_map=$(build_display_name_slug_map)

  # Resolve upstream_input to a display name
  local upstream_display=""
  if echo "$upstream_input" | grep -qE '^[a-z0-9][a-z0-9-]*$'; then
    # Looks like a slug — find its display name
    local match; match=$(echo "$name_map" | grep "|${upstream_input}$" | head -1)
    [[ -n "$match" ]] && upstream_display=$(echo "$match" | cut -d'|' -f1)
  else
    upstream_display="$upstream_input"
  fi

  # Count total requirement lines (lines containing a pipe delimiter)
  local total=0
  while IFS= read -r line; do
    [[ "$line" == *"|"* ]] && total=$((total + 1))
  done <<< "$all_reqs"

  if [[ -n "$upstream_display" ]]; then
    # Filter: only show requirements from this upstream agent
    # Chinese display names have no special regex meaning in BRE mode
    local filtered
    filtered=$(echo "$all_reqs" | grep "^${upstream_display}|" || true)
    if [[ -n "$filtered" ]]; then
      local filt_count=0
      while IFS= read -r line; do
        [[ "$line" == *"|"* ]] && filt_count=$((filt_count + 1))
      done <<< "$filtered"
      local ignored=$((total - filt_count))
      echo "$filtered"
      echo "__IGNORED__:${ignored}"
      return
    fi

    # Try partial match (e.g., "前端工程师/Unity开发者" ≈ "前端工程师")
    local partial
    partial=$(echo "$all_reqs" | grep -i "$(echo "$upstream_display" | grep -oP '^[^/]+')" || true)
    if [[ -n "$partial" ]]; then
      local part_count=0
      while IFS= read -r line; do
        [[ "$line" == *"|"* ]] && part_count=$((part_count + 1))
      done <<< "$partial"
      local ignored=$((total - part_count))
      echo "$partial"
      echo "__IGNORED__:${ignored}"
      return
    fi
  fi

  # Fallback: return all requirements
  echo "$all_reqs"
  echo "__IGNORED__:0"
}

# ── Agent Loader — make agents AI-executable ─────────────────────────

agent_file() {
  local slug="$1"
  for f in "$REPO_ROOT"/agents/*/*.md "$REPO_ROOT"/agents/*/*/*.md; do
    [[ -f "$f" ]] || continue
    [[ "$(basename "$f" .md)" == "$slug" ]] && { echo "$f"; return 0; }
  done
  echo ""
}

agent_frontmatter() {
  local slug="$1" field="$2"
  local file; file=$(agent_file "$slug")
  [[ -z "$file" ]] && { echo ""; return; }
  awk -v f="$field" '
    /^---$/ { fm=!fm; next }
    fm && $0 ~ "^"f":" { sub(/^[^:]+:[[:space:]]*/,""); gsub(/"/,""); print; exit }
  ' "$file"
}

agent_prompt() {
  local slug="$1"
  local file; file=$(agent_file "$slug")
  [[ -z "$file" ]] && { err "Unknown agent: $slug"; return 1; }
  local name emoji desc
  name=$(agent_frontmatter "$slug" "name")
  emoji=$(agent_frontmatter "$slug" "emoji")
  desc=$(agent_frontmatter "$slug" "description")
  echo "${emoji} ${name} — ${desc}"
  echo ""
  awk '/^## [0-9]+\./{section=$0;next} section!=""{print}' "$file"
}

agent_task() {
  local slug="$1" task="$2"
  local name emoji
  name=$(agent_frontmatter "$slug" "name")
  emoji=$(agent_frontmatter "$slug" "emoji")
  cat << TASK
# ${emoji} ${name} — 任务派发

${task}

---
TASK
  agent_prompt "$slug" 2>/dev/null
  echo ""
  echo "---"
  echo "请以 ${name} 的身份完成以上任务。"
}

agent_list() {
  echo "可调用 Agent (40个):"
  echo ""
  for f in "$REPO_ROOT"/agents/*/*.md "$REPO_ROOT"/agents/*/*/*.md; do
    [[ -f "$f" ]] || continue
    local slug emoji short
    slug=$(basename "$f" .md)
    emoji=$(grep "^emoji:" "$f" 2>/dev/null | head -1 | sed 's/^emoji:[[:space:]]*//')
    short=$(grep "^short:" "$f" 2>/dev/null | head -1 | sed 's/^short:[[:space:]]*//')
    printf "  %-30s %s %s\n" "$slug" "$emoji" "${short:-}"
  done
}

# ── Agent Dispatch — actually execute agents ─────────────────────────

dispatch_agent() {
  local slug="$1" task="$2"
  local file; file=$(agent_file "$slug")
  [[ -z "$file" ]] && { err "Unknown agent: $slug"; return 1; }
  local name emoji short role
  name=$(agent_frontmatter "$slug" "name")
  emoji=$(agent_frontmatter "$slug" "emoji")
  role=$(agent_frontmatter "$slug" "role")
  short=$(agent_frontmatter "$slug" "short")
  local dispatch_file="$REPO_ROOT/context/dispatches/$(date +%Y%m%d-%H%M%S)-${slug}.json"
  mkdir -p "$REPO_ROOT/context/dispatches"
  node -e "require('fs').writeFileSync('$dispatch_file',JSON.stringify({agent:'$slug',name:'$name',task:'$task',timestamp:new Date().toISOString(),status:'dispatched'},null,2))" 2>/dev/null || true
  cat << DISPATCH
╔══════════════════════════════════════════╗
║  Agent Dispatch: ${emoji} ${name}
║  Role: ${role}
║  Task: ${task}
║  Record: $(basename "$dispatch_file")
╚══════════════════════════════════════════╝

$(agent_prompt "$slug" 2>/dev/null)

---

## 📋 当前任务
${task}

## 📤 输出要求
请以 ${name} 的身份完成此任务。输出你的工作成果、决策理由和下游Agent需要知道的信息。
DISPATCH
}

chain_graph() {
  local task="$1"
  [[ -z "$task" ]] && { err "Usage: guild chain <task>"; return 1; }

  echo "╔══════════════════════════════════════════╗"
  echo "║  AgentGraph Chain Execution Plan        ║"
  echo "╚══════════════════════════════════════════╝"
  echo ""
  echo "  Task: ${task}"
  echo ""

  local type; type=$(classify_task_fallback "$task")
  local features; features=$(detect_features "$task")
  local agents; agents=$(select_agents "$type" "$features")
  local gates; gates=$(select_gates "$type")

  echo "  Type: ${type}  |  Agents: $(echo "$agents" | wc -w)  |  Gates: ${gates}"
  echo ""

  local deps; deps=$(resolve_dependencies "$agents" 2>/dev/null || echo "")
  local contracts_file="${CONTRACTS:-$REPO_ROOT/contracts/guild-contracts.yml}"
  local agent_count; agent_count=$(echo "$agents" | wc -w)
  local i=1
  local chain_ids=""

  for agent in $agents; do
    local name emoji
    name=$(agent_frontmatter "$agent" "name" 2>/dev/null || echo "$agent")
    emoji=$(agent_frontmatter "$agent" "emoji" 2>/dev/null || echo "")

    mkdir -p "$REPO_ROOT/context/dispatches"
    local dispatch_id; dispatch_id=$(next_dispatch_id)
    local dispatch_file="$REPO_ROOT/context/dispatches/${dispatch_id}.json"
    local timestamp; timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Resolve needs from upstream
    local needs_display=""
    while IFS='|' read -r ag dep; do
      [[ "$ag" == "$agent" ]] && {
        local dn; dn=$(agent_frontmatter "$dep" "name" 2>/dev/null || echo "$dep")
        needs_display="$needs_display $dn($dep)"
      }
    done <<< "$deps" 2>/dev/null || true
    local needs_str="(none)"
    needs_str=$(echo "$needs_display" | xargs 2>/dev/null || echo "(none)")
    [[ -z "$needs_str" ]] && needs_str="(none)"

    # Get deliverables from contracts
    local deliverables=""
    [[ -f "$contracts_file" ]] && deliverables=$(awk -v slug="$agent" '
      $0 ~ "^  " slug ":" { in_agent=1; next }
      in_agent && /^  [a-z]/ && $0 !~ "^  " slug ":" { exit }
      in_agent && /^    delivers:/ { in_del=1; next }
      in_agent && /^    requires:/ { in_del=0; next }
      in_del && /^      - name:/ {
        sub(/.*name: "/, ""); sub(/".*/, "");
        print $0
      }
    ' "$contracts_file" 2>/dev/null | head -3)

    # Get memory items for manifest
    local mem_items="[]"
    local mem_dir="$REPO_ROOT/context/memory/${agent}"
    if [[ -d "$mem_dir" ]] && command -v node &>/dev/null; then
      mem_items=$(node -e "
        const fs=require('fs');
        try {
          const files=fs.readdirSync('$mem_dir').filter(f=>f.endsWith('.json')).sort().reverse().slice(0,3);
          const mems=files.map(f=>{
            try{ const d=JSON.parse(fs.readFileSync('$mem_dir/'+f,'utf8')); return {task:(d.task||'').substring(0,120), summary:(d.summary||'').substring(0,200)}; }
            catch(e){ return null; }
          }).filter(Boolean);
          console.log(JSON.stringify(mems));
        } catch(e){ console.log('[]'); }
      " 2>/dev/null || echo "[]")
    fi

    # Write manifest via node with env vars (safe from shell escaping)
    AG_DISPATCH_ID="$dispatch_id" \
    AG_AGENT_SLUG="$agent" \
    AG_AGENT_NAME="$name" \
    AG_TASK="$task" \
    AG_TIMESTAMP="$timestamp" \
    AG_CHAIN_INDEX="$((i-1))" \
    AG_CHAIN_TOTAL="$agent_count" \
    AG_MEM_ITEMS="$mem_items" \
    AG_DISPATCH_FILE="$dispatch_file" \
    node -e '
      const fs = require("fs");
      const m = {
        id: process.env.AG_DISPATCH_ID,
        agent: process.env.AG_AGENT_SLUG,
        name: process.env.AG_AGENT_NAME,
        task: process.env.AG_TASK,
        status: "dispatched",
        timestamp: process.env.AG_TIMESTAMP,
        chain_index: Number(process.env.AG_CHAIN_INDEX || 0),
        chain_total: Number(process.env.AG_CHAIN_TOTAL || 0),
        context: {
          memory: JSON.parse(process.env.AG_MEM_ITEMS || "[]"),
          upstream_outputs: []
        },
        output: null
      };
      fs.writeFileSync(process.env.AG_DISPATCH_FILE, JSON.stringify(m, null, 2));
    ' 2>/dev/null || true

    chain_ids="$chain_ids $dispatch_id"

    # Print execution step
    echo "  ── Step ${i} ──────────────────────────────"
    echo "    ${emoji} ${name} (${agent})"
    echo "    ID:    ${dispatch_id}"
    echo "    Needs: ${needs_str}"
    if [[ -n "$deliverables" ]]; then
      local first_del=true
      while IFS= read -r dl; do
        [[ -z "$dl" ]] && continue
        if $first_del; then
          echo "    Delivers: ${dl}"
          first_del=false
        else
          echo "             ${dl}"
        fi
      done <<< "$deliverables"
    fi
    echo ""

    i=$((i + 1))
  done

  echo "  ── Execute Chain ──────────────────────────"
  for id in $chain_ids; do
    local a; a=$(json_get "$REPO_ROOT/context/dispatches/${id}.json" "agent" "?" 2>/dev/null)
    echo "    guild execute \"${a}\" \"<task>\"   # ${id}"
  done
  echo ""
  echo "  ── Complete Steps ─────────────────────────"
  for id in $chain_ids; do
    echo "    guild complete ${id} \"<summary>\""
  done
  echo "══════════════════════════════════════════"
}

# ── Dispatch ID generator ──────────────────────────────────────────
# Generates sequential dispatch IDs: d-YYYYMMDD-NNN
next_dispatch_id() {
  mkdir -p "$REPO_ROOT/context/dispatches"
  local date_prefix; date_prefix=$(date -u +"%Y%m%d")
  local max_seq=0
  for f in "$REPO_ROOT/context/dispatches"/d-${date_prefix}-*.json; do
    [[ -f "$f" ]] || continue
    local bname; bname=$(basename "$f" .json)
    local seq_str; seq_str="${bname##d-${date_prefix}-}"
    local seq_num=0
    [[ -n "$seq_str" ]] && seq_num=$(echo "$seq_str" | sed 's/^0*//')
    seq_num=${seq_num:-0}
    [[ "$seq_num" -gt "$max_seq" ]] && max_seq=$seq_num
  done
  local next=$((max_seq + 1))
  printf "d-%s-%03d" "$date_prefix" "$next"
}

# ── Agent Memory System ─────────────────────────────────────────────

# agent_memory_dir <slug> — get the memory directory for an agent
agent_memory_dir() {
  local slug="$1"
  echo "$REPO_ROOT/context/memory/${slug}"
}

# agent_memory_save <slug> <task> <output_summary>
# Saves agent work to context/memory/<slug>/
agent_memory_save() {
  local slug="$1" task="$2" summary="$3"
  local mem_dir; mem_dir="$REPO_ROOT/context/memory/${slug}"
  mkdir -p "$mem_dir"

  local timestamp; timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local file_stamp; file_stamp=$(date -u +"%Y-%m-%d-%H%M%S")
  local mem_file="$mem_dir/${file_stamp}.json"

  # Collect decisions from context/decisions/<slug>/ if they exist
  local decisions_json="[]"
  local dec_dir="$REPO_ROOT/context/decisions/${slug}"
  if [[ -d "$dec_dir" ]]; then
    decisions_json=$(node -e "
const fs=require('fs');
const dir='$dec_dir';
const files=fs.readdirSync(dir).filter(f=>f.endsWith('.json')).sort().slice(-3);
const decs=files.map(f=>{const d=JSON.parse(fs.readFileSync(dir+'/'+f,'utf8'));return d.topic||d.title||d.decision||'see file'});
console.log(JSON.stringify(decs));
" 2>/dev/null || echo "[]")
  fi

  # Escape task and summary for JSON using node if available
  local escaped_task escaped_summary
  if command -v node &>/dev/null; then
    escaped_task=$(echo "$task" | node -e "process.stdin.resume();let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>console.log(JSON.stringify(d.trim())));" 2>/dev/null || echo "\"$task\"")
    escaped_summary=$(echo "$summary" | node -e "process.stdin.resume();let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>console.log(JSON.stringify(d.trim())));" 2>/dev/null || echo "\"$summary\"")
  else
    escaped_task="\"$task\""
    escaped_summary="\"$summary\""
  fi

  cat > "$mem_file" << JSONEOF
{
  "slug": "${slug}",
  "task": ${escaped_task},
  "summary": ${escaped_summary},
  "timestamp": "${timestamp}",
  "decisions": ${decisions_json}
}
JSONEOF
  echo "$mem_file"
}

# agent_memory_load <slug> [limit]
# Loads recent memories for an agent, returns as formatted context
agent_memory_load() {
  local slug="$1" limit="${2:-5}"
  local mem_dir; mem_dir="$REPO_ROOT/context/memory/${slug}"

  if [[ ! -d "$mem_dir" ]]; then
    echo ""
    return
  fi

  # Use node to safely read and sort JSON memory files
  if command -v node &>/dev/null; then
    node -e "
const fs=require('fs');
const dir='$mem_dir';
let files;
try { files=fs.readdirSync(dir).filter(f=>f.endsWith('.json')).sort().reverse().slice(0,$limit); }
catch(e) { console.log(''); process.exit(0); }
if(files.length===0){ console.log(''); process.exit(0); }
const mems=files.map(f=>{
  try{ return JSON.parse(fs.readFileSync(dir+'/'+f,'utf8')); }
  catch(e){ return null; }
}).filter(Boolean);
console.log('--- Agent Memory: ' + '$slug' + ' (recent ' + mems.length + ' tasks) ---');
mems.forEach((m,i)=>{
  const d=(m.timestamp||'').substring(0,10);
  const task=(m.task||'').substring(0,120);
  const summary=(m.summary||'').substring(0,200);
  console.log((i+1)+'. ['+d+'] '+task);
  console.log('   Summary: '+summary);
  if(m.decisions&&m.decisions.length>0){
    console.log('   Decisions: '+m.decisions.join('; '));
  }
});
console.log('---');
" 2>/dev/null || true
  fi
}

# agent_memory_context <slug>
# Returns a concise summary string: "Agent X has completed N tasks. Recent: [summaries]"
agent_memory_context() {
  local slug="$1"
  local mem_dir; mem_dir="$REPO_ROOT/context/memory/${slug}"

  if [[ ! -d "$mem_dir" ]]; then
    echo "Agent ${slug} has no prior memory."
    return
  fi

  if command -v node &>/dev/null; then
    node -e "
const fs=require('fs');
const dir='$mem_dir';
let files;
try { files=fs.readdirSync(dir).filter(f=>f.endsWith('.json')).sort(); }
catch(e){ console.log('Agent ${slug} has no prior memory.'); process.exit(0); }
if(files.length===0){ console.log('Agent ${slug} has no prior memory.'); process.exit(0); }
const mems=files.map(f=>{
  try{ return JSON.parse(fs.readFileSync(dir+'/'+f,'utf8')); }
  catch(e){ return null; }
}).filter(Boolean);
const total=mems.length;
const recent=mems.slice(-3).map(m=>m.task||'').filter(Boolean);
const recentStr=recent.length>0?recent.join('; '):'none';
console.log('Agent ${slug} has completed '+total+' tasks. Recent: '+recentStr);
" 2>/dev/null || echo "Agent ${slug} has completed tasks."
  fi
}

# agent_prompt_with_memory <slug>
# Like agent_prompt but includes the agent's memory context
agent_prompt_with_memory() {
  local slug="$1"
  local prompt; prompt=$(agent_prompt "$slug" 2>/dev/null) || return 1
  local mem_ctx; mem_ctx=$(agent_memory_context "$slug" 2>/dev/null)

  echo "${prompt}"
  if [[ -n "$mem_ctx" && "$mem_ctx" != "Agent ${slug} has no prior memory." ]]; then
    echo ""
    echo "## \U0001f9e0 Memory Context"
    echo "${mem_ctx}"
    echo ""
    local loaded; loaded=$(agent_memory_load "$slug" 5 2>/dev/null)
    if [[ -n "$loaded" ]]; then
      echo "${loaded}"
    fi
  fi
}

# ── Agent Dispatch with Memory ────────────────────────────────────

dispatch_agent_with_memory() {
  local slug="$1" task="$2"
  local file; file=$(agent_file "$slug")
  [[ -z "$file" ]] && { err "Unknown agent: $slug"; return 1; }
  local name emoji short role
  name=$(agent_frontmatter "$slug" "name")
  emoji=$(agent_frontmatter "$slug" "emoji")
  role=$(agent_frontmatter "$slug" "role")
  short=$(agent_frontmatter "$slug" "short")

  # Generate structured dispatch manifest with proper ID
  mkdir -p "$REPO_ROOT/context/dispatches"
  local dispatch_id; dispatch_id=$(next_dispatch_id)
  local dispatch_file="$REPO_ROOT/context/dispatches/${dispatch_id}.json"
  local timestamp; timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Get recent memory items for manifest context
  local mem_items="[]"
  local mem_dir="$REPO_ROOT/context/memory/${slug}"
  if [[ -d "$mem_dir" ]] && command -v node &>/dev/null; then
    mem_items=$(node -e "
      const fs=require('fs');
      try {
        const files=fs.readdirSync('$mem_dir').filter(f=>f.endsWith('.json')).sort().reverse().slice(0,3);
        const mems=files.map(f=>{
          try{ const d=JSON.parse(fs.readFileSync('$mem_dir/'+f,'utf8')); return {task:(d.task||'').substring(0,120), summary:(d.summary||'').substring(0,200)}; }
          catch(e){ return null; }
        }).filter(Boolean);
        console.log(JSON.stringify(mems));
      } catch(e){ console.log('[]'); }
    " 2>/dev/null || echo "[]")
  fi

  # Write structured manifest via node with env vars (safe from shell escaping)
  AG_DISPATCH_ID="$dispatch_id" \
  AG_AGENT_SLUG="$slug" \
  AG_AGENT_NAME="$name" \
  AG_TASK="$task" \
  AG_TIMESTAMP="$timestamp" \
  AG_MEM_ITEMS="$mem_items" \
  AG_DISPATCH_FILE="$dispatch_file" \
  node -e '
    const fs = require("fs");
    const m = {
      id: process.env.AG_DISPATCH_ID,
      agent: process.env.AG_AGENT_SLUG,
      name: process.env.AG_AGENT_NAME,
      task: process.env.AG_TASK,
      status: "dispatched",
      timestamp: process.env.AG_TIMESTAMP,
      context: {
        memory: JSON.parse(process.env.AG_MEM_ITEMS || "[]"),
        upstream_outputs: []
      },
      output: null
    };
    fs.writeFileSync(process.env.AG_DISPATCH_FILE, JSON.stringify(m, null, 2));
  ' 2>/dev/null || {
    # Fallback: plain JSON
    cat > "$dispatch_file" << JSONEOF
{
  "id": "${dispatch_id}",
  "agent": "${slug}",
  "name": "${name}",
  "task": "${task}",
  "status": "dispatched",
  "timestamp": "${timestamp}",
  "context": { "memory": ${mem_items}, "upstream_outputs": [] },
  "output": null
}
JSONEOF
  }

  # Auto-save memory with the task as both task and summary placeholder
  agent_memory_save "$slug" "$task" "(dispatched -- pending completion)" > /dev/null 2>&1 || true

  cat << DISPATCH
╔══════════════════════════════════════════╗
║  Agent Dispatch: ${emoji} ${name}
║  ID:    ${dispatch_id}
║  Role:  ${role}
║  Task:  ${task}
╚══════════════════════════════════════════╝

$(agent_prompt_with_memory "$slug" 2>/dev/null)

---

## 📋 当前任务
${task}

## 📤 输出要求
请以 ${name} 的身份完成此任务。输出你的工作成果、决策理由和下游Agent需要知道的信息。

---
Dispatch ID: ${dispatch_id}
完成后执行: guild complete ${dispatch_id} "<summary>"
DISPATCH
}

# ── Agent Execution (structured dispatch — execute flow) ────────────

# execute_agent <slug> "<task>" [--input <json_array>]
# Full execution workflow: creates manifest with status=running, loads memory,
# includes upstream outputs, outputs full execution context
execute_agent() {
  local slug="$1" task="$2" upstream_inputs="[]"
  shift 2 2>/dev/null || true

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --input) upstream_inputs="$2"; shift 2;;
      *) shift;;
    esac
  done

  local file; file=$(agent_file "$slug")
  [[ -z "$file" ]] && { err "Unknown agent: $slug"; return 1; }
  local name emoji role
  name=$(agent_frontmatter "$slug" "name")
  emoji=$(agent_frontmatter "$slug" "emoji")
  role=$(agent_frontmatter "$slug" "role")

  # Generate manifest
  mkdir -p "$REPO_ROOT/context/dispatches"
  local dispatch_id; dispatch_id=$(next_dispatch_id)
  local dispatch_file="$REPO_ROOT/context/dispatches/${dispatch_id}.json"
  local timestamp; timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Get memory items
  local mem_items="[]"
  local mem_dir="$REPO_ROOT/context/memory/${slug}"
  if [[ -d "$mem_dir" ]] && command -v node &>/dev/null; then
    mem_items=$(node -e "
      const fs=require('fs');
      try {
        const files=fs.readdirSync('$mem_dir').filter(f=>f.endsWith('.json')).sort().reverse().slice(0,5);
        const mems=files.map(f=>{
          try{ const d=JSON.parse(fs.readFileSync('$mem_dir/'+f,'utf8')); return {task:(d.task||'').substring(0,120), summary:(d.summary||'').substring(0,200)}; }
          catch(e){ return null; }
        }).filter(Boolean);
        console.log(JSON.stringify(mems));
      } catch(e){ console.log('[]'); }
    " 2>/dev/null || echo "[]")
  fi

  # Write manifest (status=running)
  AG_DISPATCH_ID="$dispatch_id" \
  AG_AGENT_SLUG="$slug" \
  AG_AGENT_NAME="$name" \
  AG_TASK="$task" \
  AG_TIMESTAMP="$timestamp" \
  AG_MEM_ITEMS="$mem_items" \
  AG_UPSTREAM="$upstream_inputs" \
  AG_DISPATCH_FILE="$dispatch_file" \
  node -e '
    const fs = require("fs");
    const m = {
      id: process.env.AG_DISPATCH_ID,
      agent: process.env.AG_AGENT_SLUG,
      name: process.env.AG_AGENT_NAME,
      task: process.env.AG_TASK,
      status: "running",
      timestamp: process.env.AG_TIMESTAMP,
      context: {
        memory: JSON.parse(process.env.AG_MEM_ITEMS || "[]"),
        upstream_outputs: JSON.parse(process.env.AG_UPSTREAM || "[]")
      },
      output: null
    };
    fs.writeFileSync(process.env.AG_DISPATCH_FILE, JSON.stringify(m, null, 2));
  ' 2>/dev/null || true

  # Auto-save memory tracking
  agent_memory_save "$slug" "$task" "(executing -- id: ${dispatch_id})" > /dev/null 2>&1 || true

  # Output execution context
  echo "╔══════════════════════════════════════════╗"
  echo "║  Execute: ${emoji} ${name}"
  echo "║  ID:     ${dispatch_id}"
  echo "║  Role:   ${role}"
  echo "║  Status: running"
  echo "╚══════════════════════════════════════════╝"
  echo ""
  echo "── Manifest ──"
  cat "$dispatch_file" 2>/dev/null || echo "  (manifest at ${dispatch_file})"
  echo ""

  # Show upstream outputs if provided
  if [[ "$upstream_inputs" != "[]" && -n "$upstream_inputs" ]]; then
    echo "── Upstream Outputs ──"
    echo "$upstream_inputs" | node -e "
      process.stdin.resume();
      let d='';
      process.stdin.on('data',c=>d+=c);
      process.stdin.on('end',()=>{
        try {
          const items=JSON.parse(d);
          items.forEach((item,i)=>{
            console.log('  '+(i+1)+'. '+(item.summary||item.id||JSON.stringify(item)));
          });
        } catch(e){ console.log('  '+d); }
      });
    " 2>/dev/null || echo "  $upstream_inputs"
    echo ""
  fi

  # Agent prompt with memory context
  agent_prompt_with_memory "$slug" 2>/dev/null

  echo ""
  echo "── Task ──"
  echo "$task"
  echo ""
  echo "───"
  echo "Execute the work above, then run: guild complete ${dispatch_id} \"<summary>\""

  echo "$dispatch_id" > /tmp/guild-last-dispatch.txt 2>/dev/null || true
}

# complete_dispatch <dispatch-id> "<summary>"
# Marks a dispatch as completed, saves output to agent memory
complete_dispatch() {
  local dispatch_id="$1" summary="$2"
  [[ -z "$dispatch_id" ]] && { err "Usage: guild complete <dispatch-id> \"<summary>\""; return 1; }
  [[ -z "$summary" ]] && { err "Summary is required"; return 1; }

  local dispatch_file="$REPO_ROOT/context/dispatches/${dispatch_id}.json"
  [[ -f "$dispatch_file" ]] || { err "Dispatch not found: ${dispatch_id} at ${dispatch_file}"; return 1; }

  # Read current manifest
  local slug task_str
  slug=$(json_get "$dispatch_file" "agent" "")
  task_str=$(json_get "$dispatch_file" "task" "")
  local name; name=$(agent_frontmatter "$slug" "name" 2>/dev/null || echo "$slug")
  local emoji; emoji=$(agent_frontmatter "$slug" "emoji" 2>/dev/null || echo "")

  [[ -z "$slug" ]] && { err "Invalid dispatch manifest: no agent field"; return 1; }

  # Update manifest to completed
  local timestamp; timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  AG_DISPATCH_ID="$dispatch_id" \
  AG_TIMESTAMP="$timestamp" \
  AG_SUMMARY="$summary" \
  AG_DISPATCH_FILE="$dispatch_file" \
  node -e '
    const fs = require("fs");
    const m = JSON.parse(fs.readFileSync(process.env.AG_DISPATCH_FILE, "utf8"));
    m.status = "completed";
    m.completed_at = process.env.AG_TIMESTAMP;
    m.output = process.env.AG_SUMMARY;
    fs.writeFileSync(process.env.AG_DISPATCH_FILE, JSON.stringify(m, null, 2));
  ' 2>/dev/null || {
    err "Failed to update dispatch manifest"
    return 1
  }

  # Save to agent memory
  agent_memory_save "$slug" "$task_str" "$summary" > /dev/null 2>&1 || true

  echo "╔══════════════════════════════════════════╗"
  echo "║  Dispatch Complete: ${emoji} ${name}"
  echo "║  ID:     ${dispatch_id}"
  echo "║  Status: completed"
  echo "╚══════════════════════════════════════════╝"
  echo ""
  echo "  Agent: ${slug}"
  echo "  Summary: ${summary}"
  echo ""
  ok "Dispatch ${dispatch_id} completed. Memory saved."
}

# cmd_status_dispatches [status-filter]
# List all dispatch manifests, optionally filtered by status
cmd_status_dispatches() {
  local filter="${1:-}"

  echo "Dispatches:"
  echo ""

  local count=0
  local dir="$REPO_ROOT/context/dispatches"
  mkdir -p "$dir"
  for f in "$dir"/d-*.json; do
    [[ -f "$f" ]] || continue
    local id agent status ts
    id=$(json_get "$f" "id" "")
    agent=$(json_get "$f" "agent" "")
    status=$(json_get "$f" "status" "")
    ts=$(json_get "$f" "timestamp" "")
    ts="${ts:0:19}"

    [[ -z "$id" ]] && continue
    [[ -n "$filter" && "$status" != "$filter" ]] && continue

    local icon
    case "${status}" in
      completed) icon="✅";;
      running)   icon="🔄";;
      dispatched) icon="📋";;
      failed)    icon="❌";;
      *)         icon="❓";;
    esac

    local output_suffix=""
    if [[ "$status" == "completed" ]]; then
      local output; output=$(json_get "$f" "output" "")
      [[ -n "$output" ]] && output_suffix="  Output: ${output:0:60}"
    fi

    echo "  ${icon} ${id}  ${agent}  (${status})  ${ts}${output_suffix}"
    count=$((count + 1))
  done

  if (( count == 0 )); then
    echo "  (no dispatches found)"
  fi
}

# ── Memory command handler (called from nexus.sh) ─────────────────

cmd_memory() {
  local slug="" all_flag=false save_flag=false save_task="" save_summary=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --all) all_flag=true; shift ;;
      --save) save_flag=true; save_task="$2"; save_summary="$3"; shift 3 ;;
      --help|-h) echo "Usage: guild memory <agent> [--save \"<task>\" \"<summary>\"] | --all"; return 0 ;;
      *) if [[ -z "$slug" ]]; then slug="$1"; shift; else die "Unknown argument: $1"; fi ;;
    esac
  done

  # --all: show all agents' activity summary
  if $all_flag; then
    echo ""
    echo "All Agent Memory Summaries:"
    echo ""
    local mem_root="$REPO_ROOT/context/memory"
    if [[ ! -d "$mem_root" ]]; then
      echo "  No memory data found."
      return 0
    fi
    local count=0
    for agent_dir in "$mem_root"/*/; do
      [[ -d "$agent_dir" ]] || continue
      local agent_slug; agent_slug=$(basename "$agent_dir")
      local ctx; ctx=$(agent_memory_context "$agent_slug" 2>/dev/null)
      echo "  ${agent_slug}:"
      echo "    ${ctx}"
      count=$((count + 1))
    done
    if [[ $count -eq 0 ]]; then
      echo "  No memory data found."
    fi
    return 0
  fi

  # Require an agent slug
  if [[ -z "$slug" ]]; then
    die "Usage: guild memory <agent> [--save \"<task>\" \"<summary>\"] | --all"
  fi

  # Resolve slug if needed
  local resolved; resolved=$(resolve_agent "$slug")
  if [[ -n "$resolved" ]]; then
    slug="$resolved"
  fi

  # --save: record a memory
  if $save_flag; then
    local mem_file; mem_file=$(agent_memory_save "$slug" "$save_task" "$save_summary")
    echo "  Memory saved: $(basename "$mem_file")"
    echo "  Agent: ${slug}"
    return 0
  fi

  # Default: show memory for a single agent
  local ctx; ctx=$(agent_memory_context "$slug" 2>/dev/null)
  echo "${ctx}"
  echo ""
  agent_memory_load "$slug" 10 2>/dev/null
}
