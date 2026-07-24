#!/usr/bin/env bash
#
# lib.sh — shared pure-bash helpers for AgentGuild scripts.
# Bash 3.2+ compatible. No external dependencies.
# Groups: frontmatter parsers, slug helpers, terminal helpers.

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
# Appends a notification item to an agent's inbox JSON file.
add_inbox_item() {
  local agent="$1" type="$2" from="$3" meta="$4" summary="$5" action="$6"
  local inbox_dir="$REPO_ROOT/context/inbox"
  mkdir -p "$inbox_dir"

  local inbox_file="$inbox_dir/${agent}.json"
  local timestamp; timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local msg_id="msg-$(date +%s)-$((RANDOM % 1000))"

  if [[ -f "$inbox_file" ]]; then
    python3 -c "
import json
d = json.load(open('$inbox_file'))
d['unread'] = d.get('unread', 0) + 1
d['updated'] = '$timestamp'
d['items'].append({
    'id': '$msg_id',
    'type': '$type',
    'from': '$from',
    'timestamp': '$timestamp',
    'summary': '$summary',
    'action': '$action',
    'meta': '$meta',
    'read': False
})
with open('$inbox_file', 'w') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
" 2>/dev/null || true
  else
    cat > "$inbox_file" << JSONEOF
{
  "agent": "$agent",
  "updated": "$timestamp",
  "unread": 1,
  "items": [
    {
      "id": "$msg_id",
      "type": "$type",
      "from": "$from",
      "timestamp": "$timestamp",
      "summary": "$summary",
      "action": "$action",
      "meta": "$meta",
      "read": false
    }
  ]
}
JSONEOF
  fi
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
parse_contract() {
  local file="$1"
  local body; body="$(get_body "$file")"
  local slug; slug="$(agent_slug "$file")"

  # Extract section 13 (after "## 13." heading, until next ## heading or EOF)
  local section13; section13=$(echo "$body" | awk '/^## 13\./{found=1; next} /^## /{if(found) exit} found{print}')

  echo "  ${slug}:"
  echo "    delivers:"

  # Extract deliverables.
  # Matches both "**我向下游交付：**" and "**我交付：**" (and English fallback).
  echo "$section13" | awk '
    /我向下游交付|我交付|I deliver/ { in_delivers=1; next }
    /我需要上游提供|我需要|I require/ { in_delivers=0; next }
    in_delivers && /^- / {
      sub(/^- /, "")
      gsub(/\*\*/, "")
      sub(/[：:].*/, "")
      sub(/:.*/, "")
      gsub(/^[[:space:]]+|[[:space:]]+$/, "")
      if (length > 3 && length < 80)
        printf "      - name: \"%s\"\n        description: \"%s\"\n", $0, $0
    }
  '

  echo "    requires:"

  # Extract requirements.
  # Matches both "**我需要上游提供：**" and "**我需要：**" (and English fallback).
  # Lines are like: `- **Role Name**：description`
  echo "$section13" | awk '
    BEGIN { in_rq = 0 }
    /我需要上游提供|我需要|I require/ { in_rq = 1; next }
    /我向下游交付|我交付|I deliver/ { in_rq = 0; next }
    in_rq && /^- .*\*\*/ {
      # Extract role name between ** markers
      if (match($0, /\*\*[^*]+\*\*/)) {
        role = substr($0, RSTART, RLENGTH)
        gsub(/\*\*/, "", role)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", role)

        # Extract description after the closing **
        desc = substr($0, RSTART + RLENGTH)
        sub(/^[：:][[:space:]]*/, "", desc)
        sub(/^[[:space:]]+|[[:space:]]+$/, "", desc)
        gsub(/\*\*/, "", desc)

        if (length(role) > 1 && length(role) < 60 && length(desc) > 0) {
          printf "      - from: \"%s\"\n        items:\n", role
          printf "          - name: \"%s\"\n            description: \"%s\"\n            required: true\n", desc, desc
        }
      }
      next
    }
  '
}
