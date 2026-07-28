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

# ── Agent Loader — make agents AI-executable ─────────────────────────
}

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
  echo "║  AgentGraph Chain — 全链路执行计划      ║"
  echo "╚══════════════════════════════════════════╝"
  echo ""
  echo "  📋 任务: ${task}"
  echo ""
  local type; type=$(classify_task_fallback "$task")
  local features; features=$(detect_features "$task")
  local agents; agents=$(select_agents "$type" "$features")
  echo "  👥 Agent链 (${type}):"
  local i=1
  for agent in $agents; do
    local name emoji
    name=$(agent_frontmatter "$agent" "name" 2>/dev/null)
    emoji=$(agent_frontmatter "$agent" "emoji" 2>/dev/null)
    echo "    ${i}. ${emoji} ${name} ($agent) — guild dispatch $agent \"...\""
    i=$((i + 1))
  done
  echo ""
  echo "  🚪 Gate: $(select_gates "$type")"
  echo "══════════════════════════════════════════"
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
  local dispatch_file="$REPO_ROOT/context/dispatches/$(date +%Y%m%d-%H%M%S)-${slug}.json"
  mkdir -p "$REPO_ROOT/context/dispatches"
  node -e "require('fs').writeFileSync('$dispatch_file',JSON.stringify({agent:'$slug',name:'$name',task:'$task',timestamp:new Date().toISOString(),status:'dispatched'},null,2))" 2>/dev/null || true

  # Auto-save memory with the task as both task and summary placeholder
  agent_memory_save "$slug" "$task" "(dispatched -- pending completion)" > /dev/null 2>&1 || true

  cat << DISPATCH
╔══════════════════════════════════════════╗
║  Agent Dispatch: ${emoji} ${name}
║  Role: ${role}
║  Task: ${task}
║  Record: $(basename "$dispatch_file")
╚══════════════════════════════════════════╝

$(agent_prompt_with_memory "$slug" 2>/dev/null)

---

## 📋 当前任务
${task}

## 📤 输出要求
请以 ${name} 的身份完成此任务。输出你的工作成果、决策理由和下游Agent需要知道的信息。
DISPATCH
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
