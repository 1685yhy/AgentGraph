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
  awk -F'"' '/"file":/ { print $4 }' "$config"
}

# get_agent_slugs <config_json> — list agent slugs from guild.config.json.
get_agent_slugs() {
  local config="$1"
  awk -F'"' '/"slug":/ { print $4 }' "$config"
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
