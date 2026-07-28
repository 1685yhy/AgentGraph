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

# ── Critical UX Checks (v2 — catches FruitMerge-class bugs) ──────────

# Check 9: Flow blocking — no overlay/dialog should block game start
check_flow_blocking() {
  local file="$1"
  local issues=0
  # Pattern: province/name/settings selection overlay shown BEFORE game starts
  if grep -qiE '(province|省份|select.*prov|choose.*prov)' "$file"; then
    if grep -qiE 'showProvince|selectProv|provinceSelect' "$file"; then
      # Check if province selection blocks game initialization
      if grep -qE 'init\(\)|startGame|generateTiles' "$file"; then
        local init_line; init_line=$(grep -n 'function init\|function startGame\|showProvince\|if.*province' "$file" | head -5)
        # If showProvinceSelect is called BEFORE game initialization, it's blocking
        if echo "$init_line" | grep -q 'province.*show\|showProvince.*init\|!province.*show'; then
          warn "检测到省份选择可能阻断游戏启动 — 建议: 首次进入先开始游戏, 结束后再问省份"
          issues=1
        fi
      fi
    fi
  fi
  # Pattern: any overlay visible on load
  if grep -qiE '(overlay|modal|dialog).*hidden.*false|display.*block.*overlay' "$file"; then
    warn "检测到页面加载时显示遮罩层 — 核心功能可能在遮罩后方不可达"
    issues=1
  fi
  [[ $issues -eq 0 ]] && { ok "核心流程无障碍 — 游戏启动无阻断"; return 0; }
  return 1
}

# Check 10: Touch target size — interactive elements ≥44px (Apple HIG)
check_touch_targets() {
  local file="$1"
  local small=0
  # Parse inline styles and CSS for width/height/min-width/min-height < 44px
  while IFS= read -r line; do
    if echo "$line" | grep -qE '(width|height|min-width|min-height)\s*:\s*(3[0-9]|2[0-9]|1[0-9]|[0-9])px'; then
      local val; val=$(echo "$line" | grep -oE '(width|height|min-width|min-height)\s*:\s*[0-9]+px' | grep -oE '[0-9]+' | head -1)
      if [[ -n "$val" && "$val" =~ ^[0-9]+$ && "$val" -lt 44 ]]; then
        small=$((small + 1))
      fi
    fi
    if echo "$line" | grep -qE 'padding\s*:\s*[0-7]px'; then
      small=$((small + 1))
    fi
  done < "$file"
  [[ $small -le 5 ]] && { ok "触摸目标尺寸合理 (≤5个小元素)" ; return 0; }
  warn "检测到 ${small} 个触摸目标可能过小(<44px) — 移动端难以点击"
  return 1
}

# Check 11: Handler validity — onclick/touch handlers reference existing functions
check_handler_validity() {
  local file="$1"
  local missing=0
  # Extract onclick="funcName(" patterns
  local handlers; handlers=$(grep -oP 'onclick\s*=\s*"\K[^"(]+' "$file" 2>/dev/null | sed 's/(.*//' | sort -u)
  for h in $handlers; do
    [[ -z "$h" ]] && continue
    # Check if function exists in script
    if ! grep -qE "function\s+$h\b|$h\s*=\s*function|$h\s*=\s*\(|$h\s*:\s*function|window\.$h\s*=" "$file"; then
      warn "onclick 处理器 '$h' 可能未定义 — 点击不会触发任何操作"
      missing=$((missing + 1))
    fi
  done
  [[ $missing -eq 0 ]] && { ok "所有事件处理器已定义"; return 0; }
  err "${missing} 个事件处理器未定义 — 按钮点击无响应"
  return 1
}

# Check 12: Core loop accessibility — ≤1 interaction to reach gameplay
check_core_loop_accessibility() {
  local file="$1"
  # Must have a clear path from page load → game playing in ≤1 tap
  local direct_start=0
  # Pattern: autostart or immediate game
  if grep -qiE '(window\.onload|DOMContentLoaded|document\.ready).*(init|start|game)' "$file"; then direct_start=1; fi
  # Pattern: tutorial that doubles as start
  if grep -qiE '(tutorial|guide|how.*play).*(start|begin|play|开始).*(click|tap|press)' "$file"; then direct_start=1; fi
  # Pattern: single button → game
  if grep -qiE '(start|begin|play).*(btn|button).*(click|tap).*(init|game|play)' "$file"; then direct_start=1; fi
  # Anti-pattern: multi-step flow before gameplay
  local steps=$(grep -c 'showOverlay\|showProvince\|showTutorial\|showMenu' "$file" 2>/dev/null || echo 0)
  if [[ $direct_start -eq 1 && $steps -le 2 ]]; then
    ok "核心流程可达 — ≤1次交互即可开始游戏"
    return 0
  elif [[ $direct_start -eq 0 ]]; then
    warn "核心流程可能需要多次交互才能触达 — 建议减少进入游戏前点击次数"
    return 1
  fi
  ok "核心流程基本可达"
  return 0
}

# Check 13: Replayability — is there a clear path to play again?
check_replayability() {
  local file="$1"
  local has_restart=0 has_play_again=0
  grep -qiE '(restart|replay|play.*again|再.*一|重新|再来)' "$file" && has_restart=1
  grep -qiE 'function\s+(restart|reset|replay|newGame)\b' "$file" && has_play_again=1
  if [[ $has_restart -eq 1 && $has_play_again -eq 1 ]]; then
    ok "复玩机制完整 — 有重新开始功能和按钮"
    return 0
  elif [[ $has_restart -eq 1 ]]; then
    ok "有重新开始入口 — 建议添加独立的 reset/newGame 函数确保状态清理完整"
    return 0
  fi
  warn "未检测到复玩机制 — 游戏结束后无法重新开始会降低留存"
  return 1
}

# ── v3 Static Analysis Checks ──────────────────────────────────────────

# Check 14: Property access safety
# Detect object property accesses that don't exist on the source object
# Catches bugs like: c.r.dist (circlesOverlap returns {overlap,dist,dx,dy}, no .r)
check_property_safety() {
  local file="$1" issues=0

  # Pattern 1: .r.dist chain property access (FruitMerge-class bug)
  # circlesOverlap returns {overlap, dist, dx, dy}, accessing .r is always wrong
  if grep -qE '\.r\.(dist|overlap|dx|dy|r)\b' "$file" 2>/dev/null; then
    err "可疑链式属性访问: .r.xxx — 碰撞检测结果无 r 属性 (常见错误: c.r.dist → (a.r+b.r)-c.dist)"
    issues=1
  fi

  # Pattern 2: Function name typo — defined as X but called as Y
  if command -v node &>/dev/null; then
    local typo_js; typo_js=$(mktemp) || typo_js="/tmp/typo_$$.js"
    cat > "$typo_js" << 'TYPOEOF'
const fs = require('fs');
const code = fs.readFileSync(process.argv[2], 'utf8');
const defs = new Set();
const builtins = new Set(['function','if','else','for','while','do','switch','case','break','continue','return','typeof','delete','void','new','in','of','this','super','true','false','null','undefined','NaN','Infinity','eval','parseInt','parseFloat','isNaN','isFinite','encodeURI','decodeURI','Array','Object','String','Number','Boolean','Function','Date','RegExp','Error','Map','Set','WeakMap','WeakSet','Promise','Proxy','Reflect','Symbol','BigInt','Math','JSON','console','setTimeout','setInterval','clearTimeout','clearInterval','requestAnimationFrame','cancelAnimationFrame','fetch','localStorage','sessionStorage','document','window','self','global','globalThis','Audio','Image','ImageData','wx','alert','confirm','prompt','performance','navigator','screen','location','history','Worker','WebSocket','Blob','File','FileReader','FormData','Headers','Request','Response','URL','URLSearchParams','TextEncoder','TextDecoder','atob','btoa','Intl','require','module','exports','process','Buffer','setImmediate','clearImmediate','AggregateError','FinalizationRegistry','WeakRef','assert','expect','describe','it','test']);

const defRe = /function\s+(\w+)\s*\(/g;
let m;
while ((m = defRe.exec(code)) !== null) defs.add(m[1]);
const assignRe = /(?:let|const|var)\s+(\w+)\s*=\s*(?:function|\()/g;
while ((m = assignRe.exec(code)) !== null) defs.add(m[1]);

// Levenshtein distance for one-char edit (insert, delete, substitute)
function levenshtein1(a, b) {
  if (Math.abs(a.length - b.length) > 2) return false;
  // Simple O(n) check for single-edit difference
  let edits = 0;
  let i = 0, j = 0;
  while (i < a.length && j < b.length) {
    if (a[i] !== b[j]) {
      edits++;
      if (edits > 2) return false;
      if (a.length > b.length) { i++; continue; } // deletion in a
      if (b.length > a.length) { j++; continue; } // insertion in a
    }
    i++; j++;
  }
  edits += (a.length - i) + (b.length - j);
  return edits <= 1; // at most 1 insert/delete/substitute
}

const results = [];
const callRe = /\b([a-zA-Z_]\w+)\s*\(/g;
while ((m = callRe.exec(code)) !== null) {
  const name = m[1];
  if (defs.has(name) || builtins.has(name) || name.length < 3) continue;
  const idx = m.index;
  const before = code.slice(Math.max(0, idx-20), idx);
  if (/\.[a-zA-Z_]\w*$/.test(before.trim())) continue;

  for (const d of defs) {
    if (d.length < 3) continue;
    if (name.startsWith(d) || d.startsWith(name)) continue;
    if (levenshtein1(name, d)) {
      results.push(name + ':' + d);
      break;
    }
  }
}
if (results.length > 0) console.log(results.join('\n'));
TYPOEOF
    local typo_out
    typo_out=$(node "$typo_js" "$file" 2>/dev/null || true)
    rm -f "$typo_js"

    if [[ -n "$typo_out" ]]; then
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local call_name="${line%%:*}"
        local def_name="${line#*:}"
        err "函数名可能拼写错误: 调用了 '${call_name}()' 但定义了相似函数 '${def_name}()'"
        issues=1
      done <<< "$typo_out"
    fi
  fi

  # Pattern 3: Node-based analysis — function returns object, caller accesses wrong prop
  if command -v node &>/dev/null; then
    local tmp_js; tmp_js=$(mktemp) || tmp_js="/tmp/propcheck_$$.js"
    cat > "$tmp_js" << 'NODESCRIPT'
const fs = require('fs');
const code = fs.readFileSync(process.argv[2], 'utf8');
const issues = [];

// Find functions returning object literals with 2-8 properties
const fnRe = /function\s+(\w+)\s*\([^)]*\)\s*\{[\s\S]*?return\s*\{([^}]+)\};?/g;
let m;
const retMap = {};
while ((m = fnRe.exec(code)) !== null) {
  const fn = m[1];
  if (['if','else','for','while','do','switch','catch','then','finally'].includes(fn)) continue;
  const props = m[2].split(',').map(s => s.trim().split(':')[0].split('=')[0].trim()).filter(Boolean);
  if (props.length >= 2 && props.length <= 8) retMap[fn] = props;
}

// For each tracked function, check caller property access
for (const [fn, props] of Object.entries(retMap)) {
  const cre = new RegExp('(?:let|const|var)?\\s*(\\w+)\\s*=\\s*' + fn + '\\s*\\(', 'g');
  let cm;
  while ((cm = cre.exec(code)) !== null) {
    const vn = cm[1];
    if (!vn || vn.length > 30) continue;
    const pre = new RegExp('\\b' + vn + '\\.(\\w+)', 'g');
    let pm;
    while ((pm = pre.exec(code)) !== null) {
      const prop = pm[1];
      if (['call','apply','bind','length','name','prototype','constructor','toString','valueOf','toLocaleString','hasOwnProperty','isPrototypeOf'].includes(prop)) continue;
      if (!props.includes(prop)) {
        issues.push('PROP:' + vn + '.' + prop + ':' + fn + ' returns {' + props.join(',') + '}');
      }
    }
  }
}
console.log(issues.join('\n'));
NODESCRIPT
    local node_out
    node_out=$(node "$tmp_js" "$file" 2>/dev/null || true)
    rm -f "$tmp_js"

    if [[ -n "$node_out" ]]; then
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local detail="${line#PROP:}"
        local access="${detail%%:*}"
        local fn_info="${detail#*:}"
        err "属性访问不匹配: ${access} — ${fn_info}"
        issues=1
      done <<< "$node_out"
    fi
  fi

  [[ $issues -eq 0 ]] && { ok "属性访问安全 — 未检测到可疑属性访问模式"; return 0; }
  return 1
}

# Check 15: Physics/substep quality
# Verify game physics patterns: deltaTime, fixed timestep, proper loop structure
check_physics_quality() {
  local file="$1" issues=0

  # Pattern 1: requestAnimationFrame callback should use timestamp parameter
  local has_rAF=0
  grep -q 'requestAnimationFrame' "$file" && has_rAF=1
  if [[ $has_rAF -eq 1 ]]; then
    local rAF_uses_param=0
    # Check various rAF patterns that properly use the timestamp
    if grep -qE 'requestAnimationFrame\(\s*(function\s*\(\s*[a-z]|\(?\s*[a-z]+\s*\)?\s*=>)' "$file"; then
      rAF_uses_param=1
    fi
    # Also check the classic pattern: let _lastTime; function gameLoop(now/timestamp)...
    if grep -qE '(lastTime|_lastTime|prevTime)\s*[=:]' "$file"; then
      rAF_uses_param=1
    fi
    # Fallback: check for gameLoop/animLoop function that takes a parameter
    if grep -qE 'function\s+(gameLoop|animLoop|mainLoop|tick|update)\s*\(\s*\w+\s*\)' "$file"; then
      rAF_uses_param=1
    fi

    if [[ $rAF_uses_param -eq 0 ]]; then
      warn "requestAnimationFrame 回调可能未使用时间戳参数 — 无法正确计算 deltaTime"
      issues=1
    else
      # Check that dt calculation exists (deltaTime from timestamp)
      if grep -qE '(now|ts|timestamp|time)\s*-\s*(last|prev|_last|old)' "$file"; then
        ok "requestAnimationFrame 使用时间戳参数计算 deltaTime"
      else
        if grep -qE '(dt|delta|deltaTime|delta_time)\s*=' "$file"; then
          ok "游戏循环中存在 deltaTime 变量"
        else
          warn "rAF 使用时间戳参数但未发现 deltaTime 计算 — 确保时间步长正确"
          issues=1
        fi
      fi
    fi
  fi

  # Pattern 2: Fixed timestep accumulator pattern
  if grep -qE 'physicsAccum|accumulator|_accum' "$file"; then
    if grep -qE '(physicsAccum|accumulator)\s*[+]=.*dt|PHYSICS_STEP|FIXED_STEP|fixedStep' "$file"; then
      ok "固定时间步长累加器模式 — physicsAccum/accumulator 累积"
    else
      warn "检测到累加器变量但未发现固定步长比较 — 建议使用 fixed timestep"
      issues=1
    fi
  fi

  # Pattern 3: Physics/substep functions should accept dt parameter
  if grep -qE 'function\s+(physicsSubstep|updatePhysics|step|simulate)\b' "$file"; then
    if grep -qE 'function\s+(physicsSubstep|updatePhysics|step|simulate)\s*\(\s*(dt|delta|deltaTime|substep)\s*\)' "$file"; then
      ok "物理子步函数接受 dt 参数"
    else
      # Check if the function takes any parameter at all
      if grep -qE 'function\s+(physicsSubstep|updatePhysics)\s*\(\s*\w+\s*\)' "$file"; then
        ok "物理更新函数接受时间参数"
      else
        warn "物理/碰撞更新函数可能缺少 dt 时间步长参数 — 物理模拟将帧率相关"
        issues=1
      fi
    fi
  fi

  # Pattern 4: No bare setInterval for game loops
  if grep -qE 'setInterval\(' "$file" 2>/dev/null; then
    # Check if it's used for game loop vs. UI/timer purposes
    if grep -qE 'setInterval\(.*(update|game|loop|physics|tick)' "$file" 2>/dev/null; then
      err "游戏循环使用 setInterval — 应使用 requestAnimationFrame 实现帧同步"
      issues=1
    else
      warn "检测到 setInterval — 确认非游戏循环用途"
    fi
  fi

  [[ $issues -eq 0 ]] && { ok "物理/子步质量合格 — 游戏循环模式正确"; return 0; }
  [[ $issues -eq 1 ]] && return 1
  return 0
}

# Check 16: Dead/trivial code detection
# Detect x===x, empty catch, functions with no return
check_dead_code() {
  local file="$1" issues=0

  # Pattern 1: x === x (always true — except NaN, flagged unless NaN-commented)
  # Use node for reliable parsing (handles spacing and expression boundaries)
  if command -v node &>/dev/null; then
    local selfcmp_out
    selfcmp_out=$(node -e "
      const fs = require('fs');
      const code = fs.readFileSync('$file', 'utf8');
      const lines = code.split('\n');
      const issues = [];

      // Match x === x where x is the same identifier on both sides
      // Handles optional whitespace around ===
      const re = /\b([a-zA-Z_]\w*)\s*===\s*\1\b/g;
      for (let i = 0; i < lines.length; i++) {
        let m;
        while ((m = re.exec(lines[i])) !== null) {
          // Skip NaN comparisons if 'NaN' is in the name
          if (m[1] === 'NaN') continue;
          // Check context above for NaN
          let hasNaN = false;
          for (let j = Math.max(0,i-5); j < i; j++) {
            if (/NaN|isNaN/.test(lines[j])) { hasNaN = true; break; }
          }
          if (!hasNaN) {
            issues.push('SELF:' + m[1] + ':' + (i+1));
          }
        }
      }
      if (issues.length > 0) console.log(issues.join('\n'));
    " 2>/dev/null || true)

    if [[ -n "$selfcmp_out" ]]; then
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local var_name="${line#SELF:}"
        var_name="${var_name%%:*}"
        local line_num="${line##*:}"
        warn "自身比较检测: 第${line_num}行 '${var_name} === ${var_name}' — 恒为 true (NaN 检查除外)"
        issues=1
      done <<< "$selfcmp_out"
    fi
  fi

  # Pattern 2: Empty catch blocks
  local empty_catch
  empty_catch=$(grep -cE 'catch\s*\([^)]*\)\s*\{\s*\}' "$file" 2>/dev/null)
  if [[ -z "$empty_catch" ]]; then empty_catch=0; fi
  if [[ $empty_catch -gt 0 ]]; then
    warn "检测到 ${empty_catch} 个空 catch 块 — 错误被静默吞没, 建议至少 console.warn"
    issues=1
  fi

  # Pattern 3: Functions with clear return intent but no return statement
  # Look for functions whose name suggests they produce a value
  if command -v node &>/dev/null; then
    local tmp_js2; tmp_js2=$(mktemp) || tmp_js2="/tmp/deadcode_$$.js"
    cat > "$tmp_js2" << 'NODESCRIPT2'
const fs = require('fs');
const code = fs.readFileSync(process.argv[2], 'utf8');
const lines = [];

// Find functions whose name suggests they should return something
const fnRe = /function\s+(get\w*|calc\w*|compute\w*|find\w*|resolve\w*|make\w*|build\w*|create\w*|gen\w*|hash\w*|parse\w*|convert\w*|transform\w*|merge\w*)\s*\([^)]*\)\s*\{/g;
let m;
while ((m = fnRe.exec(code)) !== null) {
  const fnName = m[1];
  const start = m.index;
  // Find the matching closing brace (simple brace counter)
  let depth = 1;
  let i = start + m[0].length;
  while (i < code.length && depth > 0) {
    if (code[i] === '{') depth++;
    else if (code[i] === '}') depth--;
    i++;
  }
  const body = code.slice(start + m[0].length, i - 1);
  // Check if body has a return statement
  if (!/\breturn\b/.test(body)) {
    lines.push(fnName);
  }
}
if (lines.length > 0) console.log(lines.join('\n'));
NODESCRIPT2
    local missing_returns
    missing_returns=$(node "$tmp_js2" "$file" 2>/dev/null || true)
    rm -f "$tmp_js2"

    if [[ -n "$missing_returns" ]]; then
      while IFS= read -r fn; do
        [[ -z "$fn" ]] && continue
        warn "函数 '${fn}' 名称暗示应返回值但无 return 语句"
      done <<< "$missing_returns"
      issues=1
    fi
  fi

  [[ $issues -eq 0 ]] && { ok "未检测到死代码或琐碎代码"; return 0; }
  return 1
}

# Check 17: Error boundary in critical paths
# Detect game loops, physics, and rAF callbacks without error handling
check_error_boundary() {
  local file="$1" issues=0

  # Pattern 1: Game loop / physics functions without try-catch
  # Use node to check: if a function has no direct try-catch, check if
  # all its callers have try-catch (walk call chain up to 3 levels)
  if command -v node &>/dev/null; then
    local tmp_js3; tmp_js3=$(mktemp) || tmp_js3="/tmp/errbound_$$.js"
    cat > "$tmp_js3" << 'NODESCRIPT3'
const fs = require('fs');
const code = fs.readFileSync(process.argv[2], 'utf8');
const lines = [];

// Critical functions that should be protected
const criticalFns = ['gameLoop','mainLoop','updatePhysics','physicsSubstep','resolveCollision','update','tick','animLoop'];

// Build function -> {body, start, callers} map
const fnRe = /function\s+(\w+)\s*\([^)]*\)\s*\{/g;
let m;
const fns = {};
while ((m = fnRe.exec(code)) !== null) {
  const fnName = m[1];
  const start = m.index;
  let depth = 1;
  let i = start + m[0].length;
  const bodyStart = i;
  while (i < code.length && depth > 0) {
    if (code[i] === '{') depth++;
    else if (code[i] === '}') depth--;
    i++;
  }
  fns[fnName] = {
    body: code.slice(bodyStart, i - 1),
    bodyStart, bodyEnd: i - 1,
    calls: []
  };
}

// For each function, find what it calls
for (const [fn, info] of Object.entries(fns)) {
  const callRe = /\b([a-zA-Z_]\w+)\s*\(/g;
  let cm;
  while ((cm = callRe.exec(info.body)) !== null) {
    const called = cm[1];
    if (fns[called] && called !== fn) {
      info.calls.push(called);
    }
  }
}

// Check if a function has try-catch, OR if all its callers have try-catch (up to 3 levels)
function isProtected(fnName, depth = 0, visited = new Set()) {
  if (depth > 3 || visited.has(fnName)) return false;
  visited.add(fnName);
  const info = fns[fnName];
  if (!info) return false;
  // Check direct try-catch in body
  if (/\btry\s*\{[\s\S]*\}\s*catch\s*\(/.test(info.body)) return true;
  // Check all callers (functions that call this one)
  for (const [fn, info2] of Object.entries(fns)) {
    if (info2.calls.includes(fnName)) {
      if (isProtected(fn, depth + 1, visited)) return true;
    }
  }
  return false;
}

for (const fn of criticalFns) {
  if (!fns[fn]) continue;
  if (fns[fn].body.length < 40) continue; // skip trivial functions
  if (!isProtected(fn)) {
    lines.push(fn);
  }
}
if (lines.length > 0) console.log(lines.join('\n'));
NODESCRIPT3
    local unprotected
    unprotected=$(node "$tmp_js3" "$file" 2>/dev/null || true)
    rm -f "$tmp_js3"

    if [[ -n "$unprotected" ]]; then
      while IFS= read -r fn; do
        [[ -z "$fn" ]] && continue
        err "关键路径缺少异常保护: '${fn}()' — 游戏循环/碰撞函数应包裹 try-catch"
        issues=1
      done <<< "$unprotected"
    fi
  fi

  # Pattern 2: requestAnimationFrame callback without error protection (grep fallback)
  # Check for rAF calls whose callback body lacks try
  if grep -q 'requestAnimationFrame' "$file"; then
    # Extract rAF callback pattern and check for try
    if ! grep -qE 'requestAnimationFrame\s*\([^)]*try\s*\{' "$file" 2>/dev/null; then
      # Look for inline rAF callbacks and check try presence
      if grep -qE 'requestAnimationFrame\s*\(\s*function\s*\(|requestAnimationFrame\s*\(\s*\(' "$file" 2>/dev/null; then
        # Hard to verify inline — check nearby lines for try
        local rAF_line
        rAF_line=$(grep -n 'requestAnimationFrame' "$file" 2>/dev/null | head -1 | cut -d: -f1)
        if [[ -n "$rAF_line" ]]; then
          local following
          following=$(sed -n "$((rAF_line)),$((rAF_line + 10))p" "$file" 2>/dev/null || true)
          if ! echo "$following" | grep -qE 'try\s*\{'; then
            warn "requestAnimationFrame 回调可能缺少错误保护 — 建议添加 try-catch"
            issues=1
          fi
        fi
      fi
    fi
  fi

  # Pattern 3: Collision/physics functions with compute-heavy logic but no try-catch
  if [[ $issues -eq 0 ]]; then
    # Check if physics functions exist and are called from an unprotected context
    local has_physics=0
    grep -qE 'function\s+(resolveCollision|circlesOverlap|updatePhysics|physicsSubstep)\b' "$file" && has_physics=1
    if [[ $has_physics -eq 1 ]]; then
      if ! grep -qE 'try\s*\{' "$file" 2>/dev/null; then
        err "存在物理/碰撞函数但完全缺少异常保护 — 物理错误会崩溃整个游戏"
        issues=1
      fi
    fi
  fi

  [[ $issues -eq 0 ]] && { ok "关键路径异常保护合格 — 游戏循环/物理函数有错误边界"; return 0; }
  return 1
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

    total=17

    echo "  [1/17] 开始交互: 存在启动游戏的机制"
    if check_start_interaction "$file"; then
      passed=$((passed + 1))
    else
      failed=$((failed + 1))
    fi
    echo ""

    echo "  [2/17] 状态管理: 游戏状态追踪 (state/phase)"
    if check_state_management "$file"; then
      passed=$((passed + 1))
    else
      failed=$((failed + 1))
    fi
    echo ""

    echo "  [3/17] 音频手势初始化: AudioContext由用户交互触发"
    if check_audio_gesture_init "$file"; then
      passed=$((passed + 1))
    else
      failed=$((failed + 1))
    fi
    echo ""

    echo "  [4/17] Canvas安全: getContext返回校验"
    if check_canvas_safety "$file"; then
      passed=$((passed + 1))
    else
      failed=$((failed + 1))
    fi
    echo ""

    echo "  [5/17] 错误处理: try-catch异常保护"
    if check_error_handling "$file"; then
      passed=$((passed + 1))
    else
      failed=$((failed + 1))
    fi
    echo ""

    echo "  [6/17] DOM安全: getElementById null检查"
    if check_dom_safety "$file"; then
      passed=$((passed + 1))
    else
      failed=$((failed + 1))
    fi
    echo ""

    echo "  [7/17] localStorage安全: try-catch保护"
    if check_localStorage_safe "$file"; then
      passed=$((passed + 1))
    else
      failed=$((failed + 1))
    fi
    echo ""

    echo "  [8/17] 移动端适配: viewport meta标签"
    if check_mobile_ready "$file"; then
      passed=$((passed + 1))
    else
      failed=$((failed + 1))
    fi
    echo ""

    # ── v2 Critical UX checks ──
    echo "  [9/17] 流程阻断: 无遮罩阻断游戏启动"
    if check_flow_blocking "$file"; then passed=$((passed + 1)); else failed=$((failed + 1)); fi
    echo ""

    echo "  [10/17] 触摸目标: 交互元素≥44px"
    if check_touch_targets "$file"; then passed=$((passed + 1)); else failed=$((failed + 1)); fi
    echo ""

    echo "  [11/17] 处理器有效: onclick引用已定义函数"
    if check_handler_validity "$file"; then passed=$((passed + 1)); else failed=$((failed + 1)); fi
    echo ""

    echo "  [12/17] 核心可达: ≤1次交互开始游戏"
    if check_core_loop_accessibility "$file"; then passed=$((passed + 1)); else failed=$((failed + 1)); fi
    echo ""

    echo "  [13/17] 复玩机制: 游戏结束可重新开始"
    if check_replayability "$file"; then passed=$((passed + 1)); else failed=$((failed + 1)); fi
    echo ""

	    # ── v3 Static Analysis Checks ──
	    echo "  [14/17] 属性访问安全: 检测不存在的属性访问"
	    if check_property_safety "$file"; then passed=$((passed + 1)); else failed=$((failed + 1)); fi
	    echo ""

	    echo "  [15/17] 物理/子步质量: 游戏循环和物理模式"
	    if check_physics_quality "$file"; then passed=$((passed + 1)); else failed=$((failed + 1)); fi
	    echo ""

	    echo "  [16/17] 死代码/琐碎代码检测"
	    if check_dead_code "$file"; then passed=$((passed + 1)); else failed=$((failed + 1)); fi
	    echo ""

	    echo "  [17/17] 关键路径异常边界"
	    if check_error_boundary "$file"; then passed=$((passed + 1)); else failed=$((failed + 1)); fi
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
