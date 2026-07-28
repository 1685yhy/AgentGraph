#!/usr/bin/env bash
#
# runtime-test.sh — Browser-based Runtime Testing for AgentGraph games
#
# Tests that static analysis can't catch: actual page load, console errors,
# click interaction, visual rendering, and game state management.
#
# Usage:
#   guild test-runtime --file <path>
#   bash scripts/runtime-test.sh --file docs/fruitmerge.html
#
# Chrome CDP path: starts headless Chromium, controls via DevTools Protocol
# Manual fallback: prints structured checklist for human tester
#
# Requires: chromium-browser (optional), python3, node.js (optional for CDP)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

# ── Constants ─────────────────────────────────────────────────────────

RUNTIME_TEST_VERSION="1.0.0"
BASE_PORT=9876

# ── Parse arguments ───────────────────────────────────────────────────

FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --file|-f)
      FILE="$2"; shift 2;;
    --help|-h)
      echo "Usage: guild test-runtime --file <path>"
      echo ""
      echo "Browser-based runtime testing for HTML games."
      echo ""
      echo "Options:"
      echo "  --file <path>   Path to the HTML game file to test"
      echo "  --help          Show this help message"
      echo ""
      echo "Examples:"
      echo "  guild test-runtime --file docs/fruitmerge.html"
      exit 0;;
    *)
      die "Unknown option: $1. Use --help for usage.";;
  esac
done

# Validate
[[ -n "$FILE" ]] || die "Usage: guild test-runtime --file <path>"
[[ -f "$FILE" ]] || die "File not found: $FILE"

FILE="$(readlink -f "$FILE")"
FILENAME="$(basename "$FILE")"
FILE_DIR="$(dirname "$FILE")"
FILE_EXT="${FILENAME##*.}"

if [[ "$(echo "$FILE_EXT" | tr '[:upper:]' '[:lower:]')" != "html" ]]; then
  die "Only HTML files are supported (got .$FILE_EXT)"
fi

# ── Chrome detection ─────────────────────────────────────────────────

detect_chrome() {
  # Priority 1: Playwright headless shell (most reliable for WSL2/headless CDP)
  local playwright_hs
  for p_dir in "$HOME/.cache/ms-playwright"/chromium_headless_shell-*/chrome-headless-shell-linux64/chrome-headless-shell; do
    if [[ -x "$p_dir" ]]; then
      echo "playwright-headless-shell|$p_dir"
      return 0
    fi
  done

  # Priority 2: Playwright full chromium
  for p_dir in "$HOME/.cache/ms-playwright"/chromium-*/chrome-linux64/chrome; do
    if [[ -x "$p_dir" ]]; then
      echo "playwright-chromium|$p_dir"
      return 0
    fi
  done

  # Priority 3: System chrome via PATH
  local candidates=(
    "chromium-browser"
    "chromium"
    "google-chrome"
    "google-chrome-stable"
    "google-chrome-unstable"
    "/usr/bin/chromium"
    "/usr/bin/chromium-browser"
    "/snap/bin/chromium"
  )
  for c in "${candidates[@]}"; do
    if command -v "$c" &>/dev/null; then
      echo "system|$(command -v "$c")"
      return 0
    fi
  done
  # Search PATH
  local found
  found=$(command -v chromium-browser chromium google-chrome 2>/dev/null | head -1)
  if [[ -n "$found" ]]; then
    echo "system|$found"
    return 0
  fi
  return 1
}

# ── Port management ──────────────────────────────────────────────────

pick_port() {
  local offset="${1:-0}"
  echo "$((BASE_PORT + offset + RANDOM % 2000))"
}

port_available() {
  local port="$1"
  # Use curl or timeout-based /dev/tcp check
  if ! curl -s -o /dev/null --connect-timeout 0.3 "http://127.0.0.1:$port" 2>/dev/null; then
    return 0
  fi
  return 1
}

wait_for_port() {
  local port="$1" label="$2" max_wait="${3:-10}"
  local waited=0
  while ! curl -s -o /dev/null --connect-timeout 0.3 "http://127.0.0.1:$port" 2>/dev/null; do
    sleep 0.5
    waited=$((waited + 1))
    if [[ $waited -ge $max_wait ]]; then
      return 1
    fi
  done
  return 0
}

# ── Cleanup manager ──────────────────────────────────────────────────

_CLEANUP_PIDS=()
_CLEANUP_DIRS=()

_cleanup_handler() {
  local exit_code=$?
  set +euo pipefail 2>/dev/null
  for pid in "${_CLEANUP_PIDS[@]}"; do
    kill "$pid" 2>/dev/null || true
    # Wait briefly for each process to exit
    wait "$pid" 2>/dev/null || true
  done
  for dir in "${_CLEANUP_DIRS[@]}"; do
    [[ -d "$dir" ]] && rm -rf "$dir"
  done
  exit $exit_code
}

_register_cleanup() {
  if [[ ${#_CLEANUP_PIDS[@]} -eq 0 && ${#_CLEANUP_DIRS[@]} -eq 0 ]]; then
    trap _cleanup_handler EXIT INT TERM
  fi
}

register_pid() {
  _CLEANUP_PIDS+=("$1")
  _register_cleanup
}

register_dir() {
  _CLEANUP_DIRS+=("$1")
  _register_cleanup
}

# ── CDP Browser Controller (Python) ──────────────────────────────────
#
# Generates and runs a Python script that uses the Chrome DevTools Protocol
# over WebSocket to control the browser and collect test results.
# Returns JSON with: page_loaded, errors, interactive_count,
#                    screenshot_data, click_action, game_state

generate_cdp_controller() {
  cat << 'PYEOF'
import asyncio
import json
import os
import sys
import tempfile
import traceback

async def cdp_controller(ws_url, target_url, timeout):
    """Connect to Chrome via CDP, run tests, return results as JSON dict."""
    try:
        import websockets
    except ImportError:
        return {"error": "websockets module not available", "manual_fallback": True}

    results = {
        "page_loaded": False,
        "load_time_ms": 0,
        "errors": [],
        "error_count": 0,
        "interactive_count": 0,
        "has_canvas": False,
        "screenshot_path": "",
        "screenshot_size": 0,
        "click_action": "",
        "game_state": "unknown",
        "game_started": False,
        "province_blocked": False,
        "replay_available": False,
        "dom_title": "",
        "dom_ready_state": "",
        "checks": {}
    }

    try:
        async with websockets.connect(ws_url, max_size=50*1024*1024, open_timeout=10) as ws:
            next_id = [0]
            pending = {}
            console_errors = []
            console_warnings = []
            exceptions = []
            page_loaded_event = asyncio.Event()
            load_start_time = 0
            has_fruit_falling = False

            def next_msg_id():
                next_id[0] += 1
                return next_id[0]

            async def send_cmd(method, params=None, cmd_timeout=timeout):
                msg_id = next_msg_id()
                cmd = {"id": msg_id, "method": method}
                if params:
                    cmd["params"] = params
                fut = asyncio.get_event_loop().create_future()
                pending[msg_id] = fut
                await ws.send(json.dumps(cmd))
                try:
                    return await asyncio.wait_for(fut, cmd_timeout)
                except asyncio.TimeoutError:
                    return {"error": f"timeout waiting for {method}"}

            async def message_loop():
                nonlocal has_fruit_falling
                try:
                    async for raw in ws:
                        msg = json.loads(raw)
                        mid = msg.get("id")
                        if mid and mid in pending:
                            pending[mid].set_result(msg)
                            pending.pop(mid, None)
                        method = msg.get("method", "")

                        if method == "Runtime.consoleAPICalled":
                            params = msg.get("params", {})
                            msg_type = params.get("type", "")
                            args = params.get("args", [])
                            text = " ".join(str(a.get("value", "")) for a in args if "value" in a)
                            if msg_type == "error":
                                console_errors.append(text)
                            elif msg_type == "warning":
                                console_warnings.append(text)

                        elif method == "Runtime.exceptionThrown":
                            exc = msg.get("params", {}).get("exceptionDetails", {})
                            text = exc.get("text", "") or str(exc)
                            console_errors.append(text)
                            exceptions.append(exc)

                        elif method == "Page.loadEventFired":
                            page_loaded_event.set()
                            elapsed = (asyncio.get_event_loop().time() - load_start_time) * 1000
                            results["load_time_ms"] = int(elapsed)

                        elif method == "Runtime.executionContextCreated":
                            pass  # context created, ignore

                except websockets.exceptions.ConnectionClosed:
                    pass
                except Exception as e:
                    if console_errors is not None:
                        console_errors.append(f"message_loop error: {e}")

            receiver = asyncio.create_task(message_loop())

            # Enable domains
            await send_cmd("Page.enable")
            await send_cmd("Runtime.enable")
            await send_cmd("Console.enable")
            await send_cmd("DOM.enable")

            # Navigate
            load_start_time = asyncio.get_event_loop().time()
            await send_cmd("Page.navigate", {"url": target_url})

            # Wait for page load (with timeout)
            try:
                await asyncio.wait_for(page_loaded_event.wait(), timeout=timeout)
                results["page_loaded"] = True
            except asyncio.TimeoutError:
                results["page_loaded"] = False
                results["errors"].append("Page load timed out")

            # Let JS execute and settle
            await asyncio.sleep(1.0)

            # Check 1: Page state
            results["dom_ready_state"] = await eval_js(ws, send_cmd,
                "document.readyState", results, console_errors)
            results["dom_title"] = await eval_js(ws, send_cmd,
                "document.title", results, console_errors)

            # Check 2: Console errors
            results["errors"] = console_errors + [str(e) for e in exceptions]
            results["error_count"] = len(results["errors"])
            results["checks"]["console_clean"] = len(console_errors) == 0 and len(exceptions) == 0

            # Check 3: Interactive elements
            interactive_js = (
                "document.querySelectorAll("
                "'button, canvas, a, [onclick], [role=button], input, select, textarea, "
                "[class*=btn], [class*=button]"
                "').length"
            )
            interactive_val = await eval_js(ws, send_cmd, interactive_js, results, console_errors)
            try:
                results["interactive_count"] = int(float(interactive_val))
            except (ValueError, TypeError):
                results["interactive_count"] = 0
            results["checks"]["has_interactive"] = results["interactive_count"] > 0

            # Check 4: Has canvas
            has_canvas = await eval_js(ws, send_cmd,
                "document.querySelector('canvas') !== null", results, console_errors)
            results["has_canvas"] = str(has_canvas).lower() == "true"
            results["checks"]["has_canvas"] = results["has_canvas"]

            # Check 5: Pre-game blocking detection (overlay/start-screen before gameplay)
            # Checks for province selection, tutorial modals, or start screens
            # that block or delay the first game interaction
            prov_blocked = await eval_js(ws, send_cmd, """
                (function(){
                    var overlay = document.getElementById('overlay');
                    if(overlay && !overlay.classList.contains('hidden')) {
                        var txt = overlay.textContent || '';
                        // Province selection
                        if(txt.indexOf('省份')>=0 || txt.indexOf('province')>=0) return 'province';
                        // Tutorial before gameplay
                        if(txt.indexOf('教程')>=0 || txt.indexOf('tutorial')>=0) return 'tutorial';
                        if(txt.indexOf('水果合成')>=0) return 'tutorial';
                        // Start button in overlay
                        if(txt.indexOf('开始游戏')>=0) return 'start-overlay';
                        if(txt.indexOf('开始')>=0 && txt.indexOf('点击')>=0) return 'tutorial';
                        return 'other-overlay';
                    }
                    // Check for any visible start screen
                    var startScreen = document.getElementById('start-screen');
                    if(startScreen && !startScreen.classList.contains('hidden')) return 'start-screen';
                    return '';
                })()
            """, results, console_errors)
            results["province_blocked"] = str(prov_blocked).strip("\"'") not in ("", "")
            block_detail = str(prov_blocked).strip("\"'")
            results["province_blocked_detail"] = block_detail
            results["checks"]["province_not_blocking"] = not results["province_blocked"]

            # Check 6: Try to start game — try multiple interaction patterns
            click_result = await eval_js(ws, send_cmd, """
                (async function() {
                    // Priority 1: Try start/play buttons by common selectors
                    var selectors = [
                        '.big-btn.primary', '#btn-start', '#start-btn', '.btn-start',
                        '[onclick*=start]', '[onclick*=restart]',
                        '.primary', '#btn-retry'
                    ];
                    for (var i = 0; i < selectors.length; i++) {
                        var el = document.querySelector(selectors[i]);
                        if (el) { el.click(); return 'clicked-' + selectors[i].replace(/[.#]/g,''); }
                    }
                    // Priority 2: Try canvas with both click and mousedown events
                    var canvas = document.querySelector('canvas');
                    if (canvas) {
                        var rect = canvas.getBoundingClientRect();
                        var cx = rect.left + rect.width/2, cy = rect.top + rect.height/2;
                        canvas.dispatchEvent(new MouseEvent('mousedown', {
                            clientX: cx, clientY: cy, bubbles: true
                        }));
                        await new Promise(function(r) { setTimeout(r, 200); });
                        canvas.dispatchEvent(new MouseEvent('click', {
                            clientX: cx, clientY: cy, bubbles: true
                        }));
                        return 'clicked-canvas';
                    }
                    // Priority 3: Any button
                    var anyBtn = document.querySelector('button');
                    if (anyBtn) { anyBtn.click(); return 'clicked-any-button'; }
                    return 'no-target-found';
                })()
            """, results, console_errors)
            results["click_action"] = str(click_result).strip("\"'")

            # Wait for game to process click
            await asyncio.sleep(1.5)

            # Check 7: Game state after click
            # Try JS variable detection first, then DOM-based fallback
            game_state_val = await eval_js(ws, send_cmd, """
                (function(){
                    try {
                        if(typeof gameOver!=='undefined')return gameOver?'gameover':'playing';
                        if(typeof phase!=='undefined')return phase;
                        if(typeof gameState!=='undefined')return gameState;
                        if(typeof G!=='undefined'&&G.phase)return G.phase;
                        if(typeof fruits!=='undefined')return 'initialized';
                        if(typeof state!=='undefined')return state;
                    } catch(e){}
                    // DOM-based fallback: check if start screens are hidden
                    var startScreen = document.getElementById('start-screen') || document.querySelector('.start-screen');
                    if(startScreen) { return startScreen.classList.contains('hidden') ? 'playing' : 'start-screen'; }
                    // Check overlay for game-over content
                    var overlay = document.getElementById('overlay');
                    if(overlay && !overlay.classList.contains('hidden')) {
                        var txt = overlay.textContent || '';
                        if(txt.indexOf('重新')>=0 || txt.indexOf('score')>=0) return 'gameover';
                        if(txt.indexOf('省份')>=0) return 'province-select';
                        return 'showing-overlay';
                    }
                    // Check for game elements
                    if(document.querySelector('canvas') && document.querySelector('canvas').width > 10) return 'canvas-rendered';
                    return 'unknown';
                })()
            """, results, console_errors)
            results["game_state"] = str(game_state_val).strip("\"'")
            results["game_started"] = results["game_state"] in (
                "playing", "initialized", "gameover",
                "play", "drop", "flying", "merging",
                "canvas-rendered", "start-screen")
            results["checks"]["game_starts"] = results["game_started"]

            # Check 8: Check if province selection blocking is the reason game didn't start
            if not results["game_started"] and results["province_blocked"]:
                results["checks"]["province_blocking_issue"] = True

            # Check 9: Replay availability (DOM-based, since JS variable may not be accessible)
            replay_val = await eval_js(ws, send_cmd, """
                (function(){
                    try {
                        if(typeof restart!=='undefined') return true;
                        if(typeof reset!=='undefined') return true;
                        if(typeof replay!=='undefined') return true;
                    } catch(e){}
                    // DOM fallback
                    var restartBtn = document.querySelector('#btn-retry, .btn-restart, [onclick*=restart], [onclick*=replay], [onclick*=再来], [onclick*=重新]');
                    if(restartBtn) return true;
                    // Check overlay for restart button
                    var overlay = document.getElementById('overlay');
                    if(overlay && !overlay.classList.contains('hidden')) {
                        var btns = overlay.querySelectorAll('button');
                        for(var i=0; i<btns.length; i++) {
                            var txt = btns[i].textContent || '';
                            if(txt.indexOf('重新')>=0 || txt.indexOf('再来')>=0) return true;
                        }
                    }
                    return false;
                })()
            """, results, console_errors)
            results["replay_available"] = str(replay_val).lower() == "true"
            results["checks"]["replay_available"] = results["replay_available"]

            # Check 10: Drop a fruit by clicking canvas center with CDP Input
            canvas_rect = await eval_js(ws, send_cmd, """
                (function() {
                    var c = document.querySelector('canvas');
                    if (!c) return 'no-canvas';
                    var r = c.getBoundingClientRect();
                    return JSON.stringify({x: r.left + r.width/2, y: r.top + r.height/2, w: r.width, h: r.height});
                })()
            """, results, console_errors)
            results["canvas_rect"] = str(canvas_rect)

            # Take screenshot
            try:
                screen_result = await send_cmd("Page.captureScreenshot",
                    {"format": "png", "fromSurface": True}, cmd_timeout=10)
                data = screen_result.get("result", {}).get("data", "")
                if data:
                    results["screenshot_size"] = len(data)
                    # Save screenshot to temp file
                    tmp_dir = tempfile.mkdtemp(prefix="runtime_test_")
                    screenshot_path = os.path.join(tmp_dir, "screenshot.png")
                    import base64
                    with open(screenshot_path, "wb") as f:
                        f.write(base64.b64decode(data))
                    results["screenshot_path"] = screenshot_path
            except Exception as e:
                results["errors"].append(f"screenshot failed: {e}")

            # Final summary
            results["checks"]["all_pass"] = (
                results["checks"].get("console_clean", False) and
                results["checks"].get("game_starts", False) and
                results["checks"].get("has_interactive", False) and
                results["checks"].get("replay_available", False)
            )

            receiver.cancel()
            return results

    except Exception as e:
        results["error"] = f"CDP controller failed: {e}"
        results["traceback"] = traceback.format_exc()
        return results

async def eval_js(ws, send_cmd, expression, results, console_errors):
    """Evaluate JavaScript in the page and return the result value."""
    try:
        resp = await send_cmd("Runtime.evaluate", {
            "expression": expression,
            "returnByValue": True,
            "awaitPromise": True,
            "timeout": 5000
        })
        result = resp.get("result", {})
        if "exceptionDetails" in result:
            exc = result["exceptionDetails"]
            console_errors.append(f"JS eval error: {exc.get('text', '')}")
            return ""
        return result.get("result", {}).get("value", "")
    except Exception as e:
        return f"<error: {e}>"

if __name__ == "__main__":
    ws_url = sys.argv[1]
    target_url = sys.argv[2]
    timeout = float(sys.argv[3]) if len(sys.argv) > 3 else 15.0
    results = asyncio.run(cdp_controller(ws_url, target_url, timeout))
    print(json.dumps(results, ensure_ascii=False))
PYEOF
}

# ── Run CDP controller ──────────────────────────────────────────────

run_cdp_tests() {
  local chrome_raw="$1" url="$2" file="$3"

  # Parse chrome type and binary path from "type|path" format
  local chrome_type chrome_bin
  if [[ "$chrome_raw" == *"|"* ]]; then
    chrome_type="${chrome_raw%%|*}"
    chrome_bin="${chrome_raw#*|}"
  else
    chrome_type="system"
    chrome_bin="$chrome_raw"
  fi

  # Build Chrome launch flags based on type
  local chrome_opts=(
    "--no-sandbox"
    "--disable-gpu"
    "--disable-software-rasterizer"
    "--disable-dev-shm-usage"
    "--mute-audio"
  )

  # Headless shell is already headless — no --headless flag needed
  if [[ "$chrome_type" != "playwright-headless-shell" ]]; then
    chrome_opts+=("--headless")
  fi

  # Pick ports
  local http_port
  http_port=$(pick_port 0)
  local cdp_port
  cdp_port=$(pick_port 2000)
  local tmp_dir
  tmp_dir=$(mktemp -d "/tmp/runtimetest.XXXXXX")
  register_dir "$tmp_dir"

  echo ""
  echo "  ╔══════════════════════════════════════════════╗"
  echo "  ║  🔬 Runtime Test: $(basename "$file")"
  echo "  ╚══════════════════════════════════════════════╝"
  echo ""

  # ── Start HTTP server ──
  local server_attempts=0
  local server_pid=""
  while [[ $server_attempts -lt 10 ]]; do
    http_port=$(pick_port 0)
    if port_available "$http_port"; then
      python3 -m http.server "$http_port" --directory "$FILE_DIR" \
        >"$tmp_dir/http-server.log" 2>&1 &
      server_pid=$!
      register_pid "$server_pid"
      sleep 0.5
      if wait_for_port "$http_port" "HTTP" 3 2>/dev/null; then
        break
      fi
    fi
    server_attempts=$((server_attempts + 1))
  done

  if [[ -z "$server_pid" ]] || ! kill -0 "$server_pid" 2>/dev/null; then
    err "Failed to start HTTP server"
    return 1
  fi

  local game_url="http://localhost:${http_port}/${FILENAME}"
  ok "HTTP server on port ${http_port} → ${game_url}"

  # ── Start Chrome headless with CDP ──
  local chrome_data_dir
  chrome_data_dir=$(mktemp -d "/tmp/chrome-runtime.XXXXXX")
  register_dir "$chrome_data_dir"

  "$chrome_bin" \
    "${chrome_opts[@]}" \
    --remote-debugging-port="$cdp_port" \
    --user-data-dir="$chrome_data_dir" \
    "about:blank" \
    >"$tmp_dir/chrome.log" 2>&1 &
  local chrome_pid=$!
  register_pid "$chrome_pid"

  # Wait for CDP port
  if ! wait_for_port "$cdp_port" "Chrome" 15 2>/dev/null; then
    err "Chrome CDP port $cdp_port not ready (timeout)"
    return 1
  fi
  ok "Chrome headless started on CDP port ${cdp_port}"

  # Get a page-level WebSocket URL (browser-level WS from /json/version
  # does NOT support Page/Runtime commands).
  #
  # Strategy:
  #   1. First tab from `/json` list (always works, came from "about:blank")
  #   2. `/json/new` via PUT (newer Chrome requires PUT, not GET)
  #   3. Fallback: create target via CDP browser WS
  local ws_url
  ws_url=$(curl -s "http://localhost:${cdp_port}/json" 2>/dev/null \
    | python3 -c "import sys,json; tabs=json.load(sys.stdin); print(tabs[0]['webSocketDebuggerUrl'] if tabs else '')" 2>/dev/null || true)

  if [[ -z "$ws_url" ]]; then
    # Try /json/new with PUT (required by newer Chrome versions)
    ws_url=$(curl -s -X PUT "http://localhost:${cdp_port}/json/new" 2>/dev/null \
      | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('webSocketDebuggerUrl',''))" 2>/dev/null || true)
  fi

  if [[ -z "$ws_url" ]]; then
    err "Failed to get page-level CDP WebSocket URL"
    return 1
  fi

  ok "Page-level CDP WebSocket obtained"

  # ── Generate and run CDP controller ──
  local cdp_script="$tmp_dir/cdp_controller.py"
  generate_cdp_controller > "$cdp_script"

  local results_json
  results_json=$(python3 "$cdp_script" "$ws_url" "$game_url" "15" 2>"$tmp_dir/cdp-err.log") || {
    warn "CDP controller exited with error. Falling back to basic checks."
    results_json='{"error":"CDP failed","manual_fallback":true}'
  }

  # Parse results
  local page_loaded error_count interactive_count has_canvas game_state
  local click_action province_blocked province_detail replay_available game_started screenshot_path

  page_loaded=$(echo "$results_json" | python3 -c "import sys,json;print(json.load(sys.stdin).get('page_loaded',False))" 2>/dev/null || echo "false")
  error_count=$(echo "$results_json" | python3 -c "import sys,json;print(json.load(sys.stdin).get('error_count',0))" 2>/dev/null || echo "0")
  interactive_count=$(echo "$results_json" | python3 -c "import sys,json;print(json.load(sys.stdin).get('interactive_count',0))" 2>/dev/null || echo "0")
  has_canvas=$(echo "$results_json" | python3 -c "import sys,json;print(json.load(sys.stdin).get('has_canvas',False))" 2>/dev/null || echo "false")
  game_state=$(echo "$results_json" | python3 -c "import sys,json;print(json.load(sys.stdin).get('game_state','unknown'))" 2>/dev/null || echo "unknown")
  click_action=$(echo "$results_json" | python3 -c "import sys,json;print(json.load(sys.stdin).get('click_action',''))" 2>/dev/null || echo "")
  province_blocked=$(echo "$results_json" | python3 -c "import sys,json;print(json.load(sys.stdin).get('province_blocked',False))" 2>/dev/null || echo "false")
  province_detail=$(echo "$results_json" | python3 -c "import sys,json;print(json.load(sys.stdin).get('province_blocked_detail',''))" 2>/dev/null || echo "")
  replay_available=$(echo "$results_json" | python3 -c "import sys,json;print(json.load(sys.stdin).get('replay_available',False))" 2>/dev/null || echo "false")
  game_started=$(echo "$results_json" | python3 -c "import sys,json;print(json.load(sys.stdin).get('game_started',False))" 2>/dev/null || echo "false")
  screenshot_path=$(echo "$results_json" | python3 -c "import sys,json;print(json.load(sys.stdin).get('screenshot_path',''))" 2>/dev/null || echo "")

  echo ""
  echo "  ── Test Results ──"
  echo ""

  local passed=0 failed=0

  # 1: Page load
  if [[ "$page_loaded" == "True" ]]; then
    ok "[1/6] Page loads successfully"
    passed=$((passed + 1))
  else
    err "[1/6] Page load FAILED"
    failed=$((failed + 1))
  fi

  # 2: Console clean
  if [[ "$error_count" -eq 0 ]]; then
    ok "[2/6] Console clean (no JS errors)"
    passed=$((passed + 1))
  else
    err "[2/6] Found ${error_count} console error(s)"
    echo "$results_json" | python3 -c "
import sys,json
r=json.load(sys.stdin)
for e in r.get('errors',[]):
    print(f'        {e}')
" 2>/dev/null || true
    failed=$((failed + 1))
  fi

  # 3: Interactive elements
  if [[ "$interactive_count" -gt 0 ]]; then
    ok "[3/6] ${interactive_count} interactive elements detected"
    passed=$((passed + 1))
  else
    err "[3/6] No interactive elements found"
    failed=$((failed + 1))
  fi

  # 4: Visual presence
  if [[ -n "$screenshot_path" && -f "$screenshot_path" ]]; then
    local sz
    sz=$(stat -c%s "$screenshot_path" 2>/dev/null || echo "0")
    if [[ "$sz" -gt 1000 ]]; then
      ok "[4/6] Screenshot captured (${sz} bytes)"
      passed=$((passed + 1))
    else
      warn "[4/6] Screenshot too small (${sz} bytes)"
      failed=$((failed + 1))
    fi
  elif [[ "$has_canvas" == "True" ]]; then
    ok "[4/6] Canvas element present (game renders to canvas)"
    passed=$((passed + 1))
  else
    warn "[4/6] Cannot verify visual rendering (no canvas, no screenshot)"
    failed=$((failed + 1))
  fi

  # 5: Game interaction
  if [[ "$game_started" == "True" ]]; then
    ok "[5/6] Game started after click (state: ${game_state})"
    passed=$((passed + 1))
  elif [[ "$province_blocked" == "True" ]]; then
    warn "[5/6] Pre-game UI blocking game start (${province_detail})"
    warn "       → Click action: ${click_action}"
    warn "       → Recommend: auto-dismiss blocking UI"
    failed=$((failed + 1))
  else
    warn "[5/6] Game did not start after interaction"
    warn "       → Click action: ${click_action}"
    warn "       → Game state: ${game_state}"
    failed=$((failed + 1))
  fi

  # 6: Error recovery / Replay
  if [[ "$replay_available" == "True" ]]; then
    ok "[6/6] Replay mechanism available (restart/replay function)"
    passed=$((passed + 1))
  else
    warn "[6/6] No restart/replay mechanism detected"
    failed=$((failed + 1))
  fi

  echo ""
  echo "  ════ ${passed} passed, ${failed} failed / 6 checks ════"

  # Open screenshot if available
  if [[ -n "$screenshot_path" && -f "$screenshot_path" ]]; then
    echo ""
    echo "  Screenshot: ${screenshot_path}"
    echo "  (open in file explorer to view)"
  fi

  # Province warning
  if [[ "$province_blocked" == "True" ]]; then
    echo ""
    warn "⚠ Pre-game blocking UI detected (${province_detail})!"
    warn "  The game shows an overlay or start screen before gameplay."
    warn "  This blocks or delays the first interaction."
    warn "  Suggestion: let the game start first, then show secondary UI after gameplay."
  fi

  echo ""

  if [[ $failed -eq 0 ]]; then
    return 0
  else
    return 1
  fi
}

# ── Manual Test Checklist ────────────────────────────────────────────

print_manual_checklist() {
  local filename="$1"

  echo ""
  echo "  ╔══════════════════════════════════════════════╗"
  echo "  ║  🧪 Manual Runtime Test Checklist            ║"
  echo "  ║  ${filename}"
  echo "  ╚══════════════════════════════════════════════╝"
  echo ""
  echo "  Chrome/Chromium not detected or CDP unavailable."
  echo "  Open the game manually and run these checks:"
  echo ""
  echo "  ── How to test ──"
  echo "  1. Start a local HTTP server:"
  echo "     cd $(dirname "$FILE") && python3 -m http.server 8080"
  echo "  2. Open in Chrome: http://localhost:8080/${filename}"
  echo "  3. Open DevTools (F12) → Console tab"
  echo ""
  echo "  ── Checklist ──"
  echo ""
  echo "  🧪 手动测试清单 — ${filename}"
  echo "  ─────────────────────────────────────"
  echo "  1. 打开游戏，页面是否正常显示 (无白屏/404)？ [ ] 是 [ ] 否"
  echo "  2. 控制台是否有红色错误(JS异常)？ [ ] 是 [ ] 否"
  echo "  3. 点击屏幕或开始按钮，游戏是否启动？ [ ] 是 [ ] 否"
  echo "  4. 省份选择是否阻断游戏开始（需先选省才能玩）？ [ ] 是 [ ] 否"
  echo "  5. 水果是否正常下落和合成？ [ ] 是 [ ] 否"
  echo "  6. 按钮（道具/底部按钮）点击是否有响应？ [ ] 是 [ ] 否"
  echo "  7. 游戏结束后能否重新开始？ [ ] 是 [ ] 否"
  echo "  8. 页面在手机上是否适配（无溢出/布局错乱）？ [ ] 是 [ ] 否"
  echo ""
  echo "  ── Bug Reporting ──"
  echo "  For each failing check, describe what happened vs expected."
  echo "  Attach a screenshot if possible."
  echo ""
  echo "  ════ Manual testing required ════"
}

# ── Main ─────────────────────────────────────────────────────────────

main() {
  echo ""
  echo "  🎮 Runtime Test v${RUNTIME_TEST_VERSION}"
  echo "  File: ${FILENAME}"
  echo ""

  # Detect Chrome
  local chrome_raw
  chrome_raw=$(detect_chrome) || true

  if [[ -z "$chrome_raw" ]]; then
    warn "Chrome/Chromium not found — falling back to manual checklist"
    print_manual_checklist "$FILENAME"
    return 0
  fi

  # Extract display name
  local chrome_display
  if [[ "$chrome_raw" == *"|"* ]]; then
    chrome_display="${chrome_raw%%|*}"
  else
    chrome_display="system"
  fi

  ok "Found Chrome: ${chrome_display}"

  # Run browser-based tests
  if run_cdp_tests "$chrome_raw" "" "$FILE"; then
    echo ""
    ok "Runtime tests PASSED"
    return 0
  else
    echo ""
    err "Runtime tests FAILED — see details above"
    return 1
  fi
}

main "$@"
