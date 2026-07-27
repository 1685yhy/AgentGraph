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
