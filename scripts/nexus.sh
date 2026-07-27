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

# shellcheck source=graph-generator.sh
. "$SCRIPT_DIR/graph-generator.sh"

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

# ── Load modules ─────────────────────────────────────────────────────
_AG_MODULE_SOURCING=1
for _ag_module in "$SCRIPT_DIR/modules"/*.sh; do
  [[ -f "$_ag_module" ]] || continue
  . "$_ag_module"
done
unset _AG_MODULE_SOURCING _ag_module

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
  ci-test)   bash "$SCRIPT_DIR/ci-test.sh";;
	  plan)      generate_graph "$@";;
	  build)     build_product "$@";;
  --help|-h|help)
    sed -n '3,14p' "$0" | sed 's/^# \{0,1\}//'
    ;;
  *) die "Unknown command: $CMD. Valid: graph, handoff, check, status, accept, verify, feedback, changelog, cleanup, list, run, decide, context, inbox, read, resolve, gate, plan, build, self-test, test, ci-test";;
esac
