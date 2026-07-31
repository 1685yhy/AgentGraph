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
. "$SCRIPT_DIR/research-engine.sh"
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
    in_contract && /^  [a-z]/ && $0 !~ "^  " slug ":" { in_contract=0; in_req=0; next }
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

# scan_artifacts <path> <requirements-list> — score deliverables against contract items
# Relevance scoring: filename match +3, content keyword match +1 each.
# Skips non-deliverable dirs (.git, node_modules, etc.) for performance and accuracy.
scan_artifacts() {
  local path="$1"
  local reqs="$2"
  local matched=""
  local missing=""

  # Pre-build set of exclusion args for find/grep
  local exclude_dirs=".git node_modules .venv venv __pycache__ .next dist build target"
  local exclude_files="*.pyc .DS_Store package-lock.json yarn.lock pnpm-lock.yaml"

  while IFS='|' read -r from name required; do
    [[ -z "$name" ]] && continue
    local score=0
    local match_type=""
    local found_file=""

    # Normalize name for matching
    local name_lower
    name_lower=$(echo "$name" | tr '[:upper:]' '[:lower:]')

    # Extract meaningful keywords: split Chinese text on punctuation, take 2-6 char segments;
	    # Extract meaningful keywords: Chinese 4-char substrings, English >=3 chars
	    local search_terms
	    search_terms=$(
	      {
	        # Chinese: split long sequences into 4-char windows
	        echo "$name_lower" \
	          | grep -oP '[\x{4e00}-\x{9fff}][\x{4e00}-\x{9fff}]+' \
	          | while IFS= read -r seq; do
	              if [[ ${#seq} -le 6 ]]; then
	                echo "$seq"
	              else
	                for ((i=0; i+3<=${#seq}; i++)); do
	                  echo "${seq:$i:4}"
	                done
	              fi
	            done
	        # English words >= 3 chars
	        echo "$name_lower" | grep -oP '[a-zA-Z]{3,}'
	        # From-agent name as keyword
	        echo "$from" | grep -oP '[\x{4e00}-\x{9fff}][\x{4e00}-\x{9fff}]+|[a-zA-Z]{3,}'
	      } | sort -u | tr '\n' ' '
	    )
	    # Fallback: no keywords extracted -- use first 8 chars
	    if [[ -z "${search_terms// /}" ]]; then
	      search_terms="${name_lower:0:8}"
	    fi

    # 1. Filename match (+3) — any keyword matches a deliverable filename
    for term in $search_terms; do
      [[ ${#term} -lt 2 ]] && continue
      local fargs=""
      for d in $exclude_dirs; do fargs="$fargs -not -path '*/${d}/*'"; done
      for f in $exclude_files; do fargs="$fargs -not -name '$f'"; done
      # shellcheck disable=SC2086
      found_file=$(eval find "'$path'" -maxdepth 5 -type f $fargs -iname "'*${term}*'" 2>/dev/null | head -1)
      if [[ -n "$found_file" ]]; then
        score=3
        match_type="found"
        break
      fi
    done

    # 2. Content keyword match (+1 per keyword found in deliverable files)
    if [[ $score -eq 0 ]]; then
      local kw_count=0
      for term in $search_terms; do
        [[ ${#term} -lt 2 ]] && continue
        local gargs=""
        for d in $exclude_dirs; do gargs="$gargs --exclude-dir=$d"; done
        # shellcheck disable=SC2086
        if grep -rqil "$term" "$path" $gargs 2>/dev/null; then
          kw_count=$((kw_count + 1))
        fi
      done
      if [[ $kw_count -gt 0 ]]; then
        score=$kw_count
        match_type="content_match"
      fi
    fi

    if [[ $score -gt 0 ]]; then
      matched="${matched}${name}|${match_type}|provided|${score}"
      [[ -n "$found_file" ]] && matched="${matched}|$(basename "$found_file")"
      matched="${matched}\n"
    else
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
  echo "  guild classify  — 识别需求类型 (自然语言 → 产品类型 + 置信度)"
  echo "  guild plan     — 生成完整执行计划 (类型 + 团队 + 流程 + 里程碑 + 风险)"
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
  echo "  guild fix       — 自动修复门禁失败 (--handoff <id> | --file <path>)"
  echo "  guild test      — 运行交付物行为测试（超越静态验证）"
	  echo "  guild test-runtime — 浏览器运行时测试（真实页面加载+截图）"
  echo "  guild memory    — 查看 Agent 记忆/历史 (guild memory <agent> | --all)"
  echo "  guild doctor    — 诊断系统健康状态"
  echo "  guild self-test [--quick] — 运行系统自测 (--quick 跳过慢测试)"
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
  status)
    if [[ "${1:-}" == "--dispatches" ]]; then
      shift
      cmd_status_dispatches "$@"
    else
      cmd_status "$@"
    fi
    ;;
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
  test-runtime) bash "$SCRIPT_DIR/runtime-test.sh" "$@";;
  gate)      cmd_gate "$@";;
  fix)       cmd_fix "$@";;
  self-test) bash "$SCRIPT_DIR/self-test.sh" "$@";;
  ci-test)   bash "$SCRIPT_DIR/ci-test.sh";;
  doctor)    cmd_doctor "$@";;
	  research)  cmd_research "$*";;
	  ideate)    cmd_ideate "$*";;
	  validate)  cmd_validate_concept "$*";;
	  preflight) cmd_preflight "$*";;
	  plan)      generate_graph "$@";;
	  prompt)    agent_prompt_with_memory "${1:-}";;
	  dispatch)  dispatch_agent_with_memory "$1" "$2";;
	  execute)   execute_agent "$@";;
	  complete)  complete_dispatch "${1:-}" "${2:-}";;
	  chain)     chain_graph "$*";;
	  init)      shift; init_template "$1" "$2";;
	  task)      agent_task "$1" "$2";;
	  agents)    agent_list;;
	  capabilities) capability_list;;
	  capability)  capability_show "$1";;
  classify)  cmd_classify "$*";;
	  templates)   ls -d "$REPO_ROOT"/templates/*/ | while read d; do basename "$d"; done;;
	  help)      ai_help "${1:-}";;
	  build)     build_product "$@";;
	  memory)    cmd_memory "$@";;
  --help|-h|help|--json)
    sed -n '3,14p' "$0" | sed 's/^# \{0,1\}//'
    ;;
	  *) ai_json_err "Unknown command: $CMD" "Run guild help --json for all commands";;
esac
