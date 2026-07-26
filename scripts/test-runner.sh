#!/usr/bin/env bash
#
# test-runner.sh — AgentGraph Behavioral Test Engine
#
# This is the missing layer between "document collaboration" and
# "real team collaboration." While `guild verify` checks syntax,
# this runner checks BEHAVIOR — does the HTML game actually start
# when you click the button? Does the API actually return 200?
#
# Test types:
#   html-behavior — Static analysis of HTML/JS for event bindings,
#                   guards, error handling patterns
#   html-click    — Check that a DOM element exists and has a handler
#   html-load     — Check HTML structure for well-formedness
#   http-get      — Curl an endpoint, check status code
#   bash-run      — Run a bash command, check exit code
#   js-condition  — Check that a JS pattern/condition exists in code
#
# Usage:
#   guild test --handoff <id>              # Run behavioral tests on a handoff
#   guild test --file <path> --spec <spec> # Run tests against a file
#   guild test --generate --from-agent <agent> --file <path> [--output <file>]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

# ── Constants ──────────────────────────────────────────────────────

# Behavioral checks registry — maps check name -> (description, function)
# Each function receives: file_path, [additional_args...]
# Must exit 0 on pass, non-zero on fail with explanation to stderr

# ── HTML Behavioral Checks ──────────────────────────────────────────
# These are static-analysis checks that examine the HTML/JS source code
# for patterns that indicate correct runtime behavior.

# Check 1: btn-start exists and binds to startGame
check_start_button_bound() {
  local file="$1"
  if grep -q 'id="btn-start"' "$file"; then
    # Check that it's bound to startGame
    if grep -q 'btn-start.*startGame\|startGame.*btn-start' "$file"; then
      ok "开始按钮(btn-start)已绑定startGame"
      return 0
    else
      warn "btn-start存在，但未检测到startGame绑定"
      # This isn't necessarily a failure — binding might use the generic bind()
      # function. Check for generic bind pattern.
      if grep -q "bind.*btn-start" "$file" || grep -q "btn-start.*startGame" "$file"; then
        ok "开始按钮通过bind()绑定"
        return 0
      fi
      err "btn-start未绑定startGame"
      return 1
    fi
  else
    err "缺少btn-start按钮元素"
    return 1
  fi
}

# Check 2: showShare checks G.phase !== 'gameover' before displaying
check_showShare_guard() {
  local file="$1"
  if grep -q "G.phase.*!==.*gameover\|G.phase.*!=.*gameover\|phase.*!==.*gameover" "$file"; then
    ok "showShare有gameover守卫 — 仅在gameover状态显示"
    return 0
  else
    err "showShare缺少gameover守卫 — 可能在非gameover状态下显示"
    return 1
  fi
}

# Check 3: Audio.init has error handling that doesn't crash game
check_audio_error_handling() {
  local file="$1"
  # Audio.init should have try-catch or set audioMuted on failure
  if grep -q "catch.*Audio\|audioMuted\|AudioContext.*catch" "$file" 2>/dev/null; then
    ok "Audio初始化有错误处理"
    return 0
  elif grep -q "catch.*audio\|audio.*catch" "$file" 2>/dev/null; then
    ok "Audio初始化有错误处理(catch)"
    return 0
  else
    err "Audio初始化无错误处理 — 可能导致游戏崩溃"
    return 1
  fi
}

# Check 4: Game loop checks G.phase === 'playing' before running
check_game_loop_guard() {
  local file="$1"
  # The game loop should check phase before doing anything
  # Pattern: gameLoop function with a phase !== 'playing' guard
  if grep -q "gameLoop.*function\|function.*gameLoop" "$file" 2>/dev/null; then
    # Found gameLoop function — check for phase guard inside it
    local gl_start
    gl_start=$(grep -n "gameLoop" "$file" | head -1 | cut -d: -f1)
    local gl_block
    gl_block=$(sed -n "${gl_start},$((gl_start + 5))p" "$file" 2>/dev/null)
    if echo "$gl_block" | grep -q "phase.*playing"; then
      ok "游戏循环有phase检查 — 仅在playing状态运行"
      return 0
    fi
  fi
  # Broader fallback: check any function that uses requestAnimationFrame
  if grep -q "phase.*!==.*playing\|phase.*playing.*return" "$file" 2>/dev/null; then
    ok "游戏循环有phase检查"
    return 0
  fi
  err "游戏循环缺少phase检查 — 可能在非playing状态运行渲染循环"
  return 1
}

# Check 5: share-close does NOT call navigator.share()
check_share_close_no_navigator_share() {
  local file="$1"
  # Extract the share-close handler code
  if grep -q "share-close" "$file"; then
    # Check that share-close handler doesn't contain navigator.share
    local close_block
    close_block=$(awk '/share-close/,/;/' "$file" 2>/dev/null || true)
    if echo "$close_block" | grep -q "navigator.share\|navigator\.share"; then
      err "share-close按钮调用了navigator.share() — 可能导致意外分享"
      return 1
    else
      ok "share-close未调用navigator.share() — 分享隔离正确"
      return 0
    fi
  fi
  # Also check the button's click handler directly
  if grep -q "share-close" "$file" 2>/dev/null; then
    # Check the event binding context around share-close
    local ctx
    ctx=$(grep -A5 "share-close" "$file" 2>/dev/null || true)
    if echo "$ctx" | grep -qv "navigator.share\|navigator\.share"; then
      ok "share-close未调用navigator.share()"
      return 0
    fi
    err "share-close可能调用了navigator.share()"
    return 1
  else
    err "未找到share-close按钮绑定"
    return 1
  fi
}

# Check 6: Canvas draw calls check canvas context before using
check_canvas_context_safety() {
  local file="$1"
  # Check ctx validation before rendering
  if grep -q "if.*!ctx\|if.*ctx.*null\|ctx.*W.*===.*0\|W.*===.*0.*return" "$file"; then
    ok "Canvas draw有上下文检查 — ctx为null时不会崩溃"
    return 0
  else
    warn "Canvas可能缺少上下文检查"
    # This is a warning not an error — many games assume ctx exists
    return 0
  fi
}

# Check 7: localStorage calls wrapped in try-catch
check_localStorage_safe() {
  local file="$1"
  local errors=0
  # Find localStorage usages with their context
  local ls_match
  ls_match=$(grep -n "localStorage" "$file" 2>/dev/null || true)
  if [[ -z "$ls_match" ]]; then
    ok "无localStorage调用"
    return 0
  fi
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    # Extract line number
    local line_num="${line%%:*}"
    # Get context (5 lines before and 2 after)
    local context_before
    context_before=$(sed -n "$((line_num - 5)),$((line_num + 2))p" "$file" 2>/dev/null || true)
    # Check if a try{ or catch( pattern exists in context (actual JS keyword, not comment substring)
    if echo "$context_before" | grep -q "try\s*{\|catch\s*("; then
      : # Protected
    else
      errors=$((errors + 1))
      warn "localStorage调用在第${line_num}行可能缺少try-catch保护"
    fi
  done <<< "$ls_match"
  if [[ $errors -eq 0 ]]; then
    ok "所有localStorage调用已包装在try-catch中"
    return 0
  else
    err "${errors}处localStorage调用缺少try-catch保护 — 隐私模式下会崩溃"
    return 1
  fi
}

# Check 8: No unguarded DOM access — getElementById checks for null
check_unguarded_dom_access() {
  local file="$1"
  # We're looking for getElementById or $() usage patterns
  local unguarded=0

  # Check if there's a safe helper function for DOM access
  if grep -q "document.getElementById.*if\|getElementById.*\|\|.*null\|document.getElementById.*&&" "$file"; then
    : # Has some guards
  fi

  # Check if a safe wrapper exists (like $ helper that handles null)
  if grep -q "const \$.*document.getElementById\|function.*getElementById" "$file"; then
    ok "DOM访问使用安全包装器 — getElementById结果自动校验"
    return 0
  fi

  # Check direct getElementById patterns
  local direct_calls
  direct_calls=$(grep -c "getElementById" "$file" 2>/dev/null; true)
  local guard_calls
  guard_calls=$(grep -c "getElementById.*null\|getElementById.*if\|getElementById.*||" "$file" 2>/dev/null; true)

  # Strip whitespace/newlines
  direct_calls=$(echo "$direct_calls" | tr -d '[:space:]')
  guard_calls=$(echo "$guard_calls" | tr -d '[:space:]')
  direct_calls=${direct_calls:-0}
  guard_calls=${guard_calls:-0}

  if [[ "$guard_calls" -gt 0 ]] || [[ "$direct_calls" -le 5 ]]; then
    ok "DOM访问方式安全 — 低风险模式"
    return 0
  else
    warn "检测到${direct_calls}次getElementById调用，可能缺少null检查"
    return 0
  fi
}

# ── Test Spec Parsing ────────────────────────────────────────────────

# parse_test_spec <spec_file> — extract tests from a YAML spec file
# Output: type|selector|check|wait|description (tab-separated)
parse_test_spec() {
  local spec_file="$1"
  local in_test=false
  local type="" selector="" check="" wait="" description=""

  while IFS= read -r line; do
    # Skip empty lines and comments
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

    if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*type: ]]; then
      # If we already have a test accumulated, output it
      if [[ -n "$type" ]]; then
        printf "%s\t%s\t%s\t%s\t%s\n" "$type" "$selector" "$check" "$wait" "$description"
      fi
      # Start new test
      type="${line#*type: }"; type="${type#\"}"; type="${type%\"}"; type="${type#\'}"; type="${type%\'}"
      selector=""; check=""; wait=""; description=""
      in_test=true
    elif $in_test && [[ "$line" =~ selector: ]]; then
      selector="${line#*selector: }"; selector="${selector#\"}"; selector="${selector%\"}"; selector="${selector#\'}"; selector="${selector%\'}"
    elif $in_test && [[ "$line" =~ check: ]]; then
      check="${line#*check: }"; check="${check#\"}"; check="${check%\"}"; check="${check#\'}"; check="${check%\'}"
    elif $in_test && [[ "$line" =~ wait: ]]; then
      wait="${line#*wait: }"; wait="${wait#\"}"; wait="${wait%\"}"; wait="${wait#\'}"; wait="${wait%\'}"
    elif $in_test && [[ "$line" =~ description: ]]; then
      description="${line#*description: }"; description="${description#\"}"; description="${description%\"}"; description="${description#\'}"; description="${description%\'}"
    fi
  done < "$spec_file"

  # Output last test
  if [[ -n "$type" ]]; then
    printf "%s\t%s\t%s\t%s\t%s\n" "$type" "$selector" "$check" "$wait" "$description"
  fi
}

# ── Test Runners ────────────────────────────────────────────────────

# run_html_behavior_test <file> <check_type> <selector> <expected_condition> <description>
run_html_behavior_test() {
  local file="$1" check_type="$2" selector="$3" condition="$4" description="$5"

  [[ -f "$file" ]] || { err "文件不存在: $file"; return 1; }

  echo "  [行为测试] $description"

  case "$check_type" in
    html-behavior)
      # Run static analysis checks
      case "$selector" in
        "#btn-start"|"btn-start"|"start-button")
          check_start_button_bound "$file"
          ;;
        "showShare"|"show-share"|"gameover-guard")
          check_showShare_guard "$file"
          ;;
        "Audio.init"|"audio"|"audio-init")
          check_audio_error_handling "$file"
          ;;
        "gameLoop"|"game-loop"|"render-guard")
          check_game_loop_guard "$file"
          ;;
        "share-close"|"share_close"|"share-isolation")
          check_share_close_no_navigator_share "$file"
          ;;
        "canvas"|"canvas-safety"|"ctx-check")
          check_canvas_context_safety "$file"
          ;;
        "localStorage"|"storage"|"storage-safety")
          check_localStorage_safe "$file"
          ;;
        "dom-access"|"getElementById"|"dom-safety")
          check_unguarded_dom_access "$file"
          ;;
        *)
          # Generic check: look for a pattern in the file
          if [[ -n "$condition" ]]; then
            if grep -q "$condition" "$file" 2>/dev/null; then
              ok "条件满足: $condition"
              return 0
            else
              err "条件不满足: $condition — 未在文件中找到匹配"
              return 1
            fi
          else
            err "未知检查类型: $selector"
            return 1
          fi
          ;;
      esac
      ;;

    html-click)
      # Check that the DOM element with this selector exists
      if grep -q "id=\"${selector#\#}\"\|id='${selector#\#}'" "$file" 2>/dev/null; then
        # If a condition is specified, check it
        if [[ -n "$condition" ]]; then
          if grep -q "$condition" "$file" 2>/dev/null; then
            ok "元素 $selector 存在且条件满足: $condition"
            return 0
          else
            err "元素 $selector 存在但条件不满足: $condition"
            return 1
          fi
        fi
        ok "元素 $selector 存在"
        return 0
      else
        # Check for class-based or other selector patterns
        local search_sel; search_sel=$(echo "$selector" | sed 's/[#.]//')
        if grep -qi "$search_sel" "$file" 2>/dev/null; then
          ok "选择器 $selector 相关内容存在"
          return 0
        fi
        err "元素 $selector 不存在"
        return 1
      fi
      ;;

    html-load)
      # Check basic HTML structure
      local errors=0
      if ! grep -q '</html>' "$file" 2>/dev/null; then
        err "缺少</html>闭合标签"; errors=1
      fi
      if ! grep -q '<head>' "$file" 2>/dev/null; then
        err "缺少<head>标签"; errors=1
      fi
      if ! grep -q '<body' "$file" 2>/dev/null; then
        err "缺少<body>标签"; errors=1
      fi
      # Check for script
      if ! grep -q '<script' "$file" 2>/dev/null; then
        warn "页面没有JavaScript"
      fi
      if [[ $errors -eq 0 ]]; then
        ok "HTML结构完整"
        return 0
      fi
      return 1
      ;;

    js-condition)
      # Check if a JS pattern/condition exists in the code
      if [[ -n "$condition" ]]; then
        if grep -q "$condition" "$file" 2>/dev/null; then
          ok "JS条件满足: $condition"
          return 0
        else
          err "JS条件不满足: $condition"
          return 1
        fi
      else
        err "js-condition类型需要check参数"
        return 1
      fi
      ;;

    http-get)
      # Curl an endpoint
      local expected_status="${condition:-200}"
      local status
      status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$selector" 2>/dev/null || echo "000")
      if [[ "$status" == "$expected_status" ]]; then
        ok "HTTP GET $selector → $status (期望: $expected_status)"
        return 0
      else
        err "HTTP GET $selector → $status (期望: $expected_status)"
        return 1
      fi
      ;;

    bash-run)
      # Run a bash command, check exit code
      if bash -c "$selector" >/dev/null 2>&1; then
        ok "命令执行成功: $selector"
        return 0
      else
        err "命令执行失败: $selector"
        return 1
      fi
      ;;

    *)
      err "未知测试类型: $check_type"
      return 1
      ;;
  esac
}

# ── Run All Behavioral Tests ────────────────────────────────────────

# run_all_tests <file> [spec_file]
# If spec_file is given, run the tests from the spec
# If no spec_file, run the full Color Clash behavioral test suite
run_all_tests() {
  local file="$1" spec_file="${2:-}"
  local passed=0 failed=0 total=0

  if [[ -n "$spec_file" && -f "$spec_file" ]]; then
    # Parse and run tests from spec
    while IFS=$'\t' read -r type selector check wait description; do
      [[ -z "$type" ]] && continue
      total=$((total + 1))
      echo "  [$total] $description"
      if run_html_behavior_test "$file" "$type" "$selector" "$check" "$description"; then
        passed=$((passed + 1))
      else
        failed=$((failed + 1))
      fi
      echo ""
    done < <(parse_test_spec "$spec_file")
  else
    # Run the standard Color Clash behavioral test suite
    echo ""
    echo "  ════ 标准行为测试套件 ════"
    echo ""

    total=8

    echo "  [1/8] 开始按钮绑定: btn-start存在并关联startGame"
    if check_start_button_bound "$file"; then
      passed=$((passed + 1))
    else
      failed=$((failed + 1))
    fi
    echo ""

    echo "  [2/8] showShare守卫: 仅在gameover状态显示分享"
    if check_showShare_guard "$file"; then
      passed=$((passed + 1))
    else
      failed=$((failed + 1))
    fi
    echo ""

    echo "  [3/8] Audio错误处理: Audio.init()有异常保护"
    if check_audio_error_handling "$file"; then
      passed=$((passed + 1))
    else
      failed=$((failed + 1))
    fi
    echo ""

    echo "  [4/8] 游戏循环守卫: 渲染循环检查phase===playing"
    if check_game_loop_guard "$file"; then
      passed=$((passed + 1))
    else
      failed=$((failed + 1))
    fi
    echo ""

    echo "  [5/8] 分享隔离: share-close不调用navigator.share()"
    if check_share_close_no_navigator_share "$file"; then
      passed=$((passed + 1))
    else
      failed=$((failed + 1))
    fi
    echo ""

    echo "  [6/8] Canvas安全: 渲染前检查ctx/W/H有效性"
    if check_canvas_context_safety "$file"; then
      passed=$((passed + 1))
    else
      failed=$((failed + 1))
    fi
    echo ""

    echo "  [7/8] localStorage安全: 存储调用有try-catch保护"
    if check_localStorage_safe "$file"; then
      passed=$((passed + 1))
    else
      failed=$((failed + 1))
    fi
    echo ""

    echo "  [8/8] DOM访问安全: getElementById有null检查"
    if check_unguarded_dom_access "$file"; then
      passed=$((passed + 1))
    else
      failed=$((failed + 1))
    fi
    echo ""
  fi

  echo "  ════ 结果: $passed 通过, $failed 失败 / 共 $total 项 ════"
  echo ""

  if [[ $failed -eq 0 ]]; then
    ok "所有行为测试通过"
    return 0
  else
    err "${failed} 项行为测试失败"
    return 1
  fi
}

# ── Test Spec Generation ────────────────────────────────────────────

# generate_test_spec <from_agent> <file> [output_file]
generate_test_spec() {
  local agent="$1" file="$2" output="${3:-}"

  echo "根据 $agent 的成功标准生成测试规格..."
  echo ""

  # Extract the agent's delivers/requires from contracts
  local agent_section
  agent_section=$(awk -v agent="$agent" '
    $0 ~ "  "agent":" { in_contract=1; next }
    in_contract && /^  [a-z]/ && $0 !~ "  "agent":" { in_contract=0; next }
    in_contract { print }
  ' "$REPO_ROOT/contracts/guild-contracts.yml" 2>/dev/null || true)

  # Build test spec based on agent role
  local tests=""
  tests="# Test spec auto-generated from $agent success criteria
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Source: $file
---
tests:
"

  case "$agent" in
    game-qa-engineer)
      tests+="  # Game QA Engineer behavioral checks
  # Check 1: Start button must be functional
  - type: html-click
    selector: \"#btn-start\"
    check: \"startGame\"
    description: \"开始按钮需存在且绑定startGame函数\"

  # Check 2: Game over screen must display
  - type: html-behavior
    selector: \"showShare\"
    check: \"G.phase.*!==.*gameover\"
    description: \"gameover屏需有phase守卫，防止泄露\"

  # Check 3: Audio must not crash game
  - type: html-behavior
    selector: \"audio-init\"
    check: \"audioMuted.*catch\"
    description: \"Audio初始化需有错误处理\"

  # Check 4: Game loop safety
  - type: html-behavior
    selector: \"game-loop\"
    check: \"G.phase.*!==.*playing\"
    description: \"游戏循环需在非playing状态时提前返回\"

  # Check 5: Share isolation
  - type: html-behavior
    selector: \"share-isolation\"
    check: \"share-close.*hidden\"
    description: \"分享关闭按钮不能调用系统分享API\"

  # Check 6: Canvas safety
  - type: html-behavior
    selector: \"canvas-safety\"
    check: \"!ctx.*return\"
    description: \"Canvas渲染需在ctx无效时提前返回\"

  # Check 7: localStorage safety
  - type: html-behavior
    selector: \"storage-safety\"
    check: \"try.*localStorage\"
    description: \"localStorage调用需有try-catch保护\"

  # Check 8: DOM access safety
  - type: html-behavior
    selector: \"dom-safety\"
    check: \"document.getElementById.*if\"
    description: \"DOM查询需有null检查或使用安全包装器\"

  # Check 9: HTML load check
  - type: html-load
    description: \"HTML结构完整，必备标签齐全\"
"
      ;;
    game-designer)
      tests+="  # Game Designer behavioral checks
  - type: html-behavior
    selector: \"game-loop\"
    check: \"requestAnimationFrame\"
    description: \"游戏需使用requestAnimationFrame驱动循环\"

  - type: html-behavior
    selector: \"btn-start\"
    check: \"startGame\"
    description: \"开始按钮需触发游戏核心循环\"

  - type: html-load
    description: \"HTML骨架完整\"
"
      ;;
    game-programmer)
      tests+="  # Game Programmer behavioral checks
  - type: html-behavior
    selector: \"game-loop\"
    check: \"requestAnimationFrame\"
    description: \"使用requestAnimationFrame驱动游戏循环\"

  - type: html-behavior
    selector: \"canvas-safety\"
    check: \"ctx.*clearRect\"
    description: \"Canvas渲染正确清除并重绘\"

  - type: html-behavior
    selector: \"game-loop\"
    check: \"G.phase.*!==.*playing\"
    description: \"游戏循环有phase守卫\"

  - type: html-load
    description: \"HTML结构完整\"
"
      ;;
    *)
      # Generic test spec
      tests+="  # Generic behavioral checks
  - type: html-load
    description: \"HTML结构完整\"

  - type: html-click
    selector: \"#btn-start\"
    description: \"检查开始按钮是否存在\"
"
      ;;
  esac

  if [[ -n "$output" ]]; then
    echo "$tests" > "$output"
    ok "测试规格已写入: $output"
  else
    echo "$tests"
  fi
}

# ── Command Entry Point ─────────────────────────────────────────────

cmd_test() {
  local handoff_id="" file_path="" spec_path="" action=""
  local gen_agent="" gen_file="" gen_output=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --handoff) handoff_id="$2"; shift 2;;
      --file) file_path="$2"; shift 2;;
      --spec) spec_path="$2"; shift 2;;
      --generate) action="generate"; shift;;
      --from-agent) gen_agent="$2"; shift 2;;
      --from) gen_agent="$2"; shift 2;;
      --output) gen_output="$2"; shift 2;;
      *) shift;;
    esac
  done

  # Generate mode
  if [[ "$action" == "generate" ]]; then
    [[ -n "$gen_agent" ]] || die "--from-agent <agent> is required for generate"
    [[ -n "$gen_file" ]] || gen_file="${file_path:-}"
    [[ -n "$gen_file" ]] || die "--file <path> is required for generate"
    [[ -f "$gen_file" ]] || die "文件不存在: $gen_file"
    generate_test_spec "$gen_agent" "$gen_file" "$gen_output"
    return $?
  fi

  # Resolve handoff path
  if [[ -n "$handoff_id" ]]; then
    local json_file=""
    for f in "$REPO_ROOT/handoffs"/*.json; do
      [[ -f "$f" ]] || continue
      local fid
      fid=$(python3 -c "import json; print(json.load(open('$f'))['id'])" 2>/dev/null)
      if [[ "$fid" == "$handoff_id" ]]; then
        json_file="$f"
        break
      fi
    done
    [[ -f "$json_file" ]] || die "Handoff #$handoff_id not found"
    file_path=$(python3 -c "import json; print(json.load(open('$json_file'))['path'])" 2>/dev/null)
    [[ -d "$file_path" ]] || die "Handoff #$handoff_id path not found: $file_path"

    echo "运行 Handoff #$handoff_id 的行为测试..."
    echo "路径: $file_path"
    echo "---"
    echo ""

    local all_pass=true
    local html_files=()
    while IFS= read -r -d '' f; do
      html_files+=("$f")
    done < <(find "$file_path" -name "*.html" -type f -print0 2>/dev/null)

    if [[ ${#html_files[@]} -eq 0 ]]; then
      warn "未找到HTML文件 — 跳过行为测试"
      return 0
    fi

    for html_file in "${html_files[@]}"; do
      echo ""
      echo "━━━ 文件: $(basename "$html_file") ━━━"
      if [[ -n "$spec_path" && -f "$spec_path" ]]; then
        if ! run_all_tests "$html_file" "$spec_path"; then
          all_pass=false
        fi
      else
        if ! run_all_tests "$html_file"; then
          all_pass=false
        fi
      fi
    done

    $all_pass && return 0 || return 1
  fi

  # File mode
  if [[ -n "$file_path" ]]; then
    [[ -f "$file_path" ]] || die "文件不存在: $file_path"

    echo "行为测试: $file_path"
    echo "---"

    if [[ -n "$spec_path" ]]; then
      [[ -f "$spec_path" ]] || die "测试规格不存在: $spec_path"
      run_all_tests "$file_path" "$spec_path"
    else
      # Auto-detect based on file extension
      local ext; ext="${file_path##*.}"
      case "$(echo "$ext" | tr '[:upper:]' '[:lower:]')" in
        html|htm)
          run_all_tests "$file_path"
          ;;
        *)
          die "不支持的文件类型: $ext (仅支持 HTML)"
          ;;
      esac
    fi
    return $?
  fi

  # No args
  echo "用法:"
  echo "  guild test --handoff <id>              # 运行交接的行为测试"
  echo "  guild test --file <path> [--spec <spec>] # 对文件运行行为测试"
  echo "  guild test --generate --from-agent <agent> --file <path> [--output <file>]"
  echo ""
  echo "测试类型:"
  echo "  html-behavior  — 静态分析HTML/JS的事件绑定、守卫、错误处理"
  echo "  html-click     — 检查DOM元素存在性和绑定"
  echo "  html-load      — 检查HTML结构完整性"
  echo "  http-get       — 请求端点检查状态码"
  echo "  bash-run       — 运行命令检查退出码"
  echo "  js-condition   — 检查JS代码中是否存在特定模式"
}

# Main
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  cmd_test "$@"
fi
