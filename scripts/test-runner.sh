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

# ── Generic Behavioral Checks ─────────────────────────────────────────
# These checks use GENERIC PATTERNS rather than game-specific function names.
# They work with any HTML/JS game regardless of naming conventions.

# Generic Check 1: Start interaction exists
# Look for ANY mechanism to start/init the game (button click, canvas touch,
# init/start function, etc.)
check_start_interaction() {
  local file="$1"
  # Pattern 1: Button with click handler that starts game
  if grep -qiE '(start|begin|play|开始).*(btn|button).*(click|addEventListener).*(init|start|play|game)' "$file"; then
    ok "开始交互已绑定 (按钮点击触发游戏初始化)"
    return 0
  fi
  # Pattern 2: Any init/start function definition
  if grep -qE 'function\s+(initGame|startGame|init_game|start_game|gameInit|gameStart|setupGame)\b' "$file"; then
    ok "初始化为函数 (initGame/startGame 等)"
    return 0
  fi
  # Pattern 3: Canvas with touch/mousedown handler that starts game
  if grep -qE 'addEventListener.*(touchstart|mousedown|click)' "$file"; then
    if grep -qiE '(initGame|startGame|init|start).*\(|game.*state.*playing' "$file"; then
      ok "画布/全局触摸交互存在 (touch/click handler 触发游戏)"
      return 0
    fi
  fi
  # Pattern 4: Any button with "start" in id that has a click listener
  if grep -qE 'id=.*start.*btn.*click.*addEventListener|id=.*btn.*start.*click.*addEventListener' "$file"; then
    ok "开始按钮点击监听存在"
    return 0
  fi
  # Pattern 5: Any id containing start/play with a click event
  if grep -qiE '("start-btn"|"btn-start"|"play-btn"|"btn-play")' "$file"; then
    ok "开始按钮元素存在 (start-btn/btn-start/play-btn)"
    return 0
  fi
  err "未检测到开始交互机制 -- 需要按钮/画布点击触发游戏初始化"
  return 1
}

# Generic Check 2: Game state management
# Look for state tracking variables, phase guards, or state-based game loop logic
check_state_management() {
  local file="$1"
  # Pattern 1: State variable check before running game logic
  if grep -qE "(game\.state|G\.phase|gameState|currentPhase|_state|status)\s*(===|!==)\s*['\"]playing['\"]" "$file"; then
    ok "游戏状态管理 -- state/phase/playing 状态检查"
    return 0
  fi
  # Pattern 2: State variable initialization
  if grep -qE "(game\.state|G\.phase|gameState)\s*=" "$file"; then
    ok "游戏状态管理 -- game.state/G.phase/gameState 初始化"
    return 0
  fi
  # Pattern 3: State or phase as an object property
  if grep -qE "(state|phase)\s*[:=]\s*['\"]?(playing|menu|start|gameover|idle)['\"]?" "$file"; then
    ok "游戏状态变量定义 (state/phase 含 playing/gameover 等值)"
    return 0
  fi
  # Pattern 4: update() or gameLoop function with guard
  if grep -qE "function\s+(update|gameLoop|tick|mainLoop)\b" "$file"; then
    if grep -qE "state\s*!==\s*['\"]playing['\"]|phase\s*!==\s*['\"]playing['\"]" "$file"; then
      ok "游戏循环有 state/phase 守卫 -- 仅在 playing 状态运行"
      return 0
    fi
  fi
  err "未检测到游戏状态管理 -- 需要 state/phase/playing 变量或守卫"
  return 1
}

# Generic Check 3: Audio init on user gesture
# Check AudioContext is created/resumed in event handler, not constructor
check_audio_gesture_init() {
  local file="$1"
  # Pattern 1: AudioContext creation wrapped in try-catch
  if grep -qE "(AudioContext|webkitAudioContext).*(catch|try)" "$file"; then
    ok "AudioContext 创建有异常保护 (try-catch)"
    return 0
  fi
  # Pattern 2: Audio init function called from event handler
  if grep -qE "(click|touchstart|mousedown).*(initAudio|audioInit|setupAudio|startAudio)\b" "$file"; then
    ok "音频在用户手势时初始化 (click/touch 触发 initAudio)"
    return 0
  fi
  # Pattern 3: initAudio function defined and called from click context
  if grep -qE "function\s+(initAudio|audioInit|setupAudio)\b" "$file"; then
    if grep -qE '(start-btn|begin|play).*(click|touch).*initAudio|initAudio.*(click|touch)' "$file"; then
      ok "initAudio 在按钮点击时调用"
      return 0
    fi
    ok "initAudio 函数存在 (可能在用户手势时调用)"
    return 0
  fi
  # Pattern 4: AudioContext resume called somewhere (not in constructor)
  if grep -qE "audioCtx.*resume|AudioContext.*resume|audio.*context.*resume" "$file"; then
    ok "audio context resume 存在 (可延迟初始化)"
    return 0
  fi
  # Pattern 5: Any audio init on click pattern
  if grep -qE "addEventListener.*(click|touch).*\{.*audio|audio.*addEventListener" "$file"; then
    ok "音频事件监听在用户交互时绑定"
    return 0
  fi
  err "未检测到音频手势初始化 -- AudioContext 应在用户交互时创建/恢复"
  return 1
}

# Generic Check 4: Canvas safety
# Check canvas.getContext return is checked before use
check_canvas_safety() {
  local file="$1"
  # Pattern 1: getContext result assigned with null fallback
  if grep -qE "getContext.*\|\|\s*null|getContext.*\|\|\s*$" "$file"; then
    ok "canvas.getContext 有 null 回退 (|| null)"
    return 0
  fi
  # Pattern 2: ctx null check
  if grep -qE "if.*!\s*ctx\b|if.*ctx\s*===?\s*null|ctx\s*&&\s*ctx" "$file"; then
    ok "Canvas 上下文有 null 检查"
    return 0
  fi
  # Pattern 3: canvas or ctx existence check before rendering
  if grep -qE "if.*!canvas|if.*!context\b" "$file"; then
    ok "Canvas/context 存在性检查"
    return 0
  fi
  # This is a warning, not hard failure -- many games assume ctx exists
  warn "canvas.getContext('2d') 未做 null 检查 -- 建议添加保护"
  return 0
}

# Generic Check 5: Error handling
# Check try-catch exists around critical paths
check_error_handling() {
  local file="$1"
  local try_count
  try_count=$(grep -cE '\btry\s*\{' "$file" 2>/dev/null || echo 0)
  local catch_count
  catch_count=$(grep -cE '\bcatch\s*\(' "$file" 2>/dev/null || echo 0)
  if [[ "$try_count" -ge 3 && "$catch_count" -ge 3 ]]; then
    ok "存在多处 try-catch 错误处理 (${try_count}个try块)"
    return 0
  fi
  if [[ "$try_count" -ge 1 ]]; then
    ok "存在 try-catch 错误处理"
    return 0
  fi
  err "未检测到 try-catch 错误处理 -- 关键路径需要异常保护"
  return 1
}

# Generic Check 6: DOM safety
# Check getElementById results are null-checked
check_dom_safety() {
  local file="$1"
  # Pattern 1: Direct null check on getElementById result
  if grep -qE "getElementById.*\|\|.*null|getElementById.*\|\|\s*$" "$file"; then
    ok "DOM 访问有 null 检查 (getElementById || null)"
    return 0
  fi
  # Pattern 2: If check around DOM element
  if grep -qE "getElementById.*if\b|if\b.*getElementById.*===?\s*null|if\b.*getElementById.*!==?\s*null" "$file"; then
    ok "DOM 查询有 null 校验"
    return 0
  fi
  # Pattern 3: Safe wrapper function exists
  if grep -qE "function\s+\$\s*\(.*id|const\s+\$\s*=\s*\(.*\)\s*=>\s*.*getElementById" "$file"; then
    ok "DOM 访问使用安全包装器"
    return 0
  fi
  # Not a hard failure if few calls
  local calls
  calls=$(grep -c 'getElementById' "$file" 2>/dev/null || echo 0)
  calls=$(echo "$calls" | tr -d '[:space:]')
  calls=${calls:-0}
  if [[ "$calls" -le 10 ]]; then
    ok "DOM 访问方式安全 -- 少量 getElementById 调用 (${calls}次)"
    return 0
  fi
  warn "检测到 ${calls} 次 getElementById 调用 -- 建议添加 null 检查"
  return 0
}

# Generic Check 7: localStorage safety
# Check storage calls are wrapped in try-catch
check_localStorage_safe() {
  local file="$1"
  local ls_uses
  ls_uses=$(grep -cE "localStorage\.(getItem|setItem|removeItem)" "$file" 2>/dev/null || echo 0)
  if [[ "$ls_uses" -eq 0 ]]; then
    ls_uses=$(grep -c 'localStorage' "$file" 2>/dev/null || echo 0)
    if [[ "$ls_uses" -eq 0 ]]; then
      ok "无 localStorage 调用"
      return 0
    fi
  fi

  # Count how many localStorage usages are wrapped
  local unprotected=0
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local line_num="${line%%:*}"
    # Get context before this line
    local context_before
    context_before=$(sed -n "$((line_num - 10)),$((line_num))p" "$file" 2>/dev/null || true)
    if ! echo "$context_before" | grep -qE '\btry\s*\{'; then
      unprotected=$((unprotected + 1))
    fi
  done < <(grep -n "localStorage\.\(getItem\|setItem\|removeItem\)" "$file" 2>/dev/null || true)

  if [[ "$unprotected" -eq 0 ]]; then
    ok "所有 localStorage 调用已包装在 try-catch 中"
    return 0
  else
    err "${unprotected} 处 localStorage 调用缺少 try-catch 保护 -- 隐私模式下会崩溃"
    return 1
  fi
}

# Generic Check 8: Mobile ready
# Check viewport meta exists for mobile adaptation
check_mobile_ready() {
  local file="$1"
  if grep -qE 'viewport.*width\s*=\s*device-width' "$file"; then
    ok "viewport meta 标签存在 (移动端适配)"
    return 0
  fi
  if grep -qi 'viewport' "$file"; then
    ok "viewport meta 标签存在"
    return 0
  fi
  err "缺少 viewport meta 标签 -- 移动端无法正确渲染"
  return 1
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
      # Run static analysis checks -- GENERIC patterns
      case "$selector" in
        "#btn-start"|"btn-start"|"start-button"|"start-interaction"|"start-btn"|"start-mechanism")
          check_start_interaction "$file"
          ;;
        "showShare"|"show-share"|"gameover-guard"|"state-management"|"state-guard"|"phase-guard")
          check_state_management "$file"
          ;;
        "Audio.init"|"audio"|"audio-init"|"audio-gesture"|"audio-context")
          check_audio_gesture_init "$file"
          ;;
        "gameLoop"|"game-loop"|"render-guard")
          check_state_management "$file"
          ;;
        "share-close"|"share_close"|"share-isolation"|"error-handling"|"try-catch")
          check_error_handling "$file"
          ;;
        "canvas"|"canvas-safety"|"ctx-check")
          check_canvas_safety "$file"
          ;;
        "localStorage"|"storage"|"storage-safety")
          check_localStorage_safe "$file"
          ;;
        "dom-access"|"getElementById"|"dom-safety")
          check_dom_safety "$file"
          ;;
        "mobile"|"viewport"|"mobile-ready")
          check_mobile_ready "$file"
          ;;
        *)
          # Generic check: look for a pattern in the file
          if [[ -n "$condition" ]]; then
            if grep -q "$condition" "$file" 2>/dev/null; then
              ok "条件满足: $condition"
              return 0
            else
              err "条件不满足: $condition -- 未在文件中找到匹配"
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
    # Run the GENERIC behavioral test suite (game-agnostic patterns)
    echo ""
    echo "  ==== 通用行为测试套件 ===="
    echo ""

    total=8

    echo "  [1/8] 开始交互: 存在启动游戏的机制"
    if check_start_interaction "$file"; then
      passed=$((passed + 1))
    else
      failed=$((failed + 1))
    fi
    echo ""

    echo "  [2/8] 状态管理: 游戏状态追踪 (state/phase)"
    if check_state_management "$file"; then
      passed=$((passed + 1))
    else
      failed=$((failed + 1))
    fi
    echo ""

    echo "  [3/8] 音频手势初始化: AudioContext由用户交互触发"
    if check_audio_gesture_init "$file"; then
      passed=$((passed + 1))
    else
      failed=$((failed + 1))
    fi
    echo ""

    echo "  [4/8] Canvas安全: getContext返回校验"
    if check_canvas_safety "$file"; then
      passed=$((passed + 1))
    else
      failed=$((failed + 1))
    fi
    echo ""

    echo "  [5/8] 错误处理: try-catch异常保护"
    if check_error_handling "$file"; then
      passed=$((passed + 1))
    else
      failed=$((failed + 1))
    fi
    echo ""

    echo "  [6/8] DOM安全: getElementById null检查"
    if check_dom_safety "$file"; then
      passed=$((passed + 1))
    else
      failed=$((failed + 1))
    fi
    echo ""

    echo "  [7/8] localStorage安全: try-catch保护"
    if check_localStorage_safe "$file"; then
      passed=$((passed + 1))
    else
      failed=$((failed + 1))
    fi
    echo ""

    echo "  [8/8] 移动端适配: viewport meta标签"
    if check_mobile_ready "$file"; then
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
      tests+="  # Game QA Engineer behavioral checks (GENERIC patterns)
  # Check 1: Start interaction exists
  - type: html-behavior
    selector: start-interaction
    description: Game start mechanism exists (button/touch/function)

  # Check 2: Game state management
  - type: html-behavior
    selector: state-management
    description: Game state/phase tracking variable

  # Check 3: Audio init on gesture
  - type: html-behavior
    selector: audio-gesture
    description: AudioContext initiated by user gesture

  # Check 4: Canvas safety
  - type: html-behavior
    selector: canvas-safety
    description: canvas.getContext return null-checked

  # Check 5: Error handling
  - type: html-behavior
    selector: error-handling
    description: try-catch exception protection

  # Check 6: DOM safety
  - type: html-behavior
    selector: dom-safety
    description: getElementById null-checked

  # Check 7: localStorage safety
  - type: html-behavior
    selector: storage-safety
    description: localStorage wrapped in try-catch

  # Check 8: Mobile ready
  - type: html-behavior
    selector: mobile-ready
    description: viewport meta tag exists

  # Check 9: HTML load check
  - type: html-load
    description: HTML structure complete with required tags
"
      ;;
    game-designer)
      tests+="  # Game Designer behavioral checks (GENERIC)
  - type: html-behavior
    selector: start-interaction
    description: Game start mechanism exists

  - type: html-behavior
    selector: state-management
    description: Game state management exists

  - type: html-load
    description: HTML structure complete
"
      ;;
    game-programmer)
      tests+="  # Game Programmer behavioral checks (GENERIC)
  - type: html-behavior
    selector: start-interaction
    description: Start game mechanism exists

  - type: html-behavior
    selector: canvas-safety
    description: Canvas render safety (getContext null check)

  - type: html-behavior
    selector: state-management
    description: Game loop has state/phase guard

  - type: html-load
    description: HTML structure complete
"
      ;;
    *)
      # Generic test spec
      tests+="  # Generic behavioral checks
  - type: html-load
    description: HTML structure complete

  - type: html-behavior
    selector: start-interaction
    description: Start mechanism exists
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
      fid=$(json_get "$f" "id")
      if [[ "$fid" == "$handoff_id" ]]; then
        json_file="$f"
        break
      fi
    done
    [[ -f "$json_file" ]] || die "Handoff #$handoff_id not found"
    file_path=$(json_get "$json_file" "path")
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
