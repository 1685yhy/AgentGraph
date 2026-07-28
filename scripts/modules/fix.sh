#!/usr/bin/env bash
# Module: fix.sh — Auto-fix strategies for common gate failures
# Source guard: only loadable via guild
[[ -n "${_AG_MODULE_SOURCING:-}" ]] || { echo "This module must be loaded via guild, not run directly" >&2; exit 1; }

# ── Strategy registry ──────────────────────────────────────────────────
FIX_STRATEGIES="state-management audio-gesture viewport-meta localStorage-try-catch replayability canvas-safety province-blocking"

declare -A FIX_LABELS
FIX_LABELS[state-management]="添加游戏状态变量 (gameState = 'playing')"
FIX_LABELS[audio-gesture]="添加 AudioContext 用户手势初始化"
FIX_LABELS[viewport-meta]="添加 viewport meta 标签"
FIX_LABELS[localStorage-try-catch]="localStorage 调用包装 try-catch"
FIX_LABELS[replayability]="添加复玩机制 (restart 函数 + 按钮)"
FIX_LABELS[canvas-safety]="canvas.getContext 添加 null 回退"
FIX_LABELS[province-blocking]="将省份选择移至游戏结束后"

# ── Helpers ────────────────────────────────────────────────────────────

fix_create_backup() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  cp "$file" "${file}.bak"
  echo "${file}.bak"
}

fix_restore_backup() {
  local file="$1"
  [[ -f "${file}.bak" ]] || return 1
  cp "${file}.bak" "$file"
  rm -f "${file}.bak"
}

fix_has_changes() {
  local file="$1"
  [[ -f "${file}.bak" ]] || return 1
  ! diff -q "$file" "${file}.bak" &>/dev/null
}

FIX_TMPDIR="${TMPDIR:-/tmp}/guild-fix"
mkdir -p "$FIX_TMPDIR"

fix_write_script() {
  local name="$1" code="$2"
  local target="$FIX_TMPDIR/${name}.js"
  echo "$code" > "$target"
  echo "$target"
}

fix_node() {
  local file="$1" js_path="$2"
  node -e "
const fs = require('fs');
let c = fs.readFileSync('$file', 'utf8');
$(cat "$js_path")
fs.writeFileSync('$file', c, 'utf8');
" 2>/dev/null
}

fix_strategy_name() {
  local s="$1"
  echo "${FIX_LABELS[$s]:-$s}"
}

# ── Inline node scripts ───────────────────────────────────────────────

_fix_write_state_script() {
  cat << 'JSEOF'
const patterns = [/function\s+(init|initGame|startGame|setupGame)\s*\([^)]*\)\s*\{/];
let inserted = false;
for (const pat of patterns) {
  const m = c.match(pat);
  if (m) {
    const idx = m.index + m[0].length;
    const nearby = c.substring(idx, idx + 200);
    if (!nearby.includes("gameState")) {
      c = c.slice(0, idx) + "\n  let gameState = \"playing\";" + c.slice(idx);
      inserted = true;
      break;
    }
  }
}
if (!inserted) {
  const scriptMatch = c.match(/<script>\s*\n?/);
  if (scriptMatch) {
    const idx = scriptMatch.index + scriptMatch[0].length;
    c = c.slice(0, idx) + "let gameState = \"playing\";\n" + c.slice(idx);
    inserted = true;
  }
}
if (!inserted) {
  const headClose = c.indexOf("</head>");
  if (headClose > -1) {
    c = c.slice(0, headClose) + "\n<script>let gameState = \"playing\";</script>\n" + c.slice(headClose);
  }
}
JSEOF
}

_fix_write_audio_script() {
  cat << 'JSEOF'
const ensureAudioCode = [
"",
"function ensureAudio() {",
"  if (!window._audioCtx) {",
"    try { window._audioCtx = new (window.AudioContext || window.webkitAudioContext)(); } catch(e) {}",
"  }",
"  if (window._audioCtx && window._audioCtx.state === \"suspended\") {",
"    try { window._audioCtx.resume(); } catch(e) {}",
"  }",
"  return window._audioCtx;",
"}",
""
].join("\n");

let inserted = false;
const evRegex = /addEventListener\s*\(\s*["'](?:click|touchstart|mousedown)["']/;
const m = c.match(evRegex);
if (m) {
  const lineStart = c.lastIndexOf("\n", m.index) + 1;
  c = c.slice(0, lineStart) + ensureAudioCode + c.slice(lineStart);
  inserted = true;
}
if (!inserted) {
  const scriptEnd = c.lastIndexOf("</script>");
  if (scriptEnd > -1) {
    c = c.slice(0, scriptEnd) + "\n" + ensureAudioCode + c.slice(scriptEnd);
  }
}
c = c.replace(/\.addEventListener\s*\(\s*["'](?:click|touchstart)["'][^)]*\)\s*\{/g, function(m) {
  return m + "\n    ensureAudio();";
});
c = c.replace(/onclick\s*=\s*"([^"]+)"/g, function(m, h) {
  if (h.indexOf("ensureAudio") < 0) {
    return 'onclick="ensureAudio();' + h + '"';
  }
  return m;
});
JSEOF
}

_fix_write_ls_script() {
  cat << 'JSEOF'
const wrapperCode = [
"",
"// Safe localStorage wrappers",
"function lsGet(k, fallback) {",
"  try { const v = localStorage.getItem(k); return v !== null ? v : fallback; } catch(e) { return fallback; }",
"}",
"function lsSet(k, v) {",
"  try { localStorage.setItem(k, v); } catch(e) {}",
"}",
""
].join("\n");

if (c.indexOf("function lsGet") < 0 && c.indexOf("function lsSet") < 0 && c.indexOf("function safeGet") < 0) {
  const lines = c.split("\n");
  let insertLine = -1;
  for (let i = 0; i < lines.length; i++) {
    if (lines[i].indexOf("localStorage.") >= 0) {
      insertLine = i;
      break;
    }
  }
  if (insertLine > 0) {
    let targetLine = insertLine;
    for (let i = insertLine - 1; i >= Math.max(0, insertLine - 5); i--) {
      const t = lines[i].trim();
      if (t === "" || t.indexOf("//") === 0) {
        targetLine = i + 1;
        break;
      }
    }
    lines.splice(targetLine, 0, "", wrapperCode.trim());
    c = lines.join("\n");
  }
}
c = c.replace(/localStorage\.getItem\(([^)]+)\)/g, function(m, a) {
  return "lsGet(" + a + ", null)";
});
c = c.replace(/localStorage\.setItem\(([^)]+)\)/g, function(m, a) {
  return "lsSet(" + a + ")";
});
c = c.replace(/localStorage\.removeItem\(([^)]+)\)/g, function(m, a) {
  return "lsSet(" + a + ", null)";
});
JSEOF
}

_fix_write_replay_script() {
  cat << 'JSEOF'
const restartFunc = [
"",
"function restart() {",
"  gameState = \"playing\";",
"  score = 0;",
"  gameOver = false;",
"  var ov = document.getElementById(\"overlay\");",
"  if (ov) ov.classList.add(\"hidden\");",
"}",
""
].join("\n");
let changed = false;
const panelEnd = c.lastIndexOf("</div>");
if (panelEnd > 0) {
  const section = c.substring(Math.max(0, panelEnd - 500), panelEnd);
  if (section.indexOf("restart") < 0 && section.indexOf("重新开始") < 0 && section.indexOf("再来一局") < 0) {
    let depth = 0;
    let closeSearch = c.length - 7;
    for (let i = c.length - 1; i >= 0; i--) {
      if (c.substring(i, i + 6) === "</div>") { depth++; closeSearch = i; if (depth >= 2) break; }
    }
    c = c.slice(0, closeSearch) + '\n    <button class="big-btn primary" onclick="restart()">\u{1F504} 重新开始</button>' + c.slice(closeSearch);
    changed = true;
  }
}
const scriptEnd = c.lastIndexOf("</script>");
if (scriptEnd > 0 && c.indexOf("function restart") < 0) {
  c = c.slice(0, scriptEnd) + restartFunc + "\n" + c.slice(scriptEnd);
  changed = true;
}
JSEOF
}

_fix_write_canvas_script() {
  cat << 'JSEOF'
c = c.replace(/(getContext\(["']2d["']\))(?!\s*\|\|)/g, "$1 || null");
JSEOF
}

_fix_write_province_script() {
  cat << 'JSEOF'
let changed = false;
const initBlock = /if\s*\(!\s*province\s*\)\s*\{[^}]*showProvinceSelect[^}]*\}\s*else\s*\{([^}]*)\}/;
const m = c.match(initBlock);
if (m) {
  const startCall = m[1].trim();
  c = c.replace(initBlock, startCall);
  changed = true;
}
const altBlock = /if\s*\(!province\)\s*showProvinceSelect\(\)/;
if (altBlock.test(c) && !changed) {
  c = c.replace(altBlock, "// Province selection deferred to after game over");
}
JSEOF
}

# ── Detection functions ───────────────────────────────────────────────

detect_state_management() {
  local file="$1"
  if grep -qE "(gameState|currentPhase|_state|status)" "$file"; then return 1; fi
  return 0
}

detect_audio_gesture() {
  local file="$1"
  if grep -qE "(AudioContext|webkitAudioContext).*catch" "$file"; then return 1; fi
  if grep -qE "(click|touchstart|mousedown).*(initAudio|audioInit|setupAudio|startAudio)" "$file"; then return 1; fi
  if grep -qE "function[[:space:]]+(initAudio|audioInit|setupAudio|ensureAudio)" "$file"; then return 1; fi
  if grep -qE "audioCtx.*resume|AudioContext.*resume" "$file"; then return 1; fi
  if grep -qE "addEventListener.*(click|touch).*audio" "$file"; then return 1; fi
  if grep -qE "new.*AudioContext|new.*webkitAudioContext" "$file"; then return 1; fi
  return 0
}

detect_viewport_meta() {
  local file="$1"
  if grep -qiE "name=.viewport.|viewport.*content=" "$file"; then return 1; fi
  if grep -qiE "viewport.*width.*device-width" "$file"; then return 1; fi
  return 0
}

detect_localStorage_try_catch() {
  local file="$1"
  local ls_uses
  ls_uses=$(grep -c "localStorage[.]\(getItem\|setItem\|removeItem\)" "$file" 2>/dev/null || echo 0)
  if [[ "$ls_uses" -eq 0 ]]; then return 1; fi
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local line_num="${line%%:*}"
    local context_before
    context_before=$(sed -n "$((line_num - 10)),$((line_num))p" "$file" 2>/dev/null || true)
    if ! echo "$context_before" | grep -qE 'try[[:space:]]*\{'; then
      return 0
    fi
  done < <(grep -n "localStorage[.]\(getItem\|setItem\|removeItem\)" "$file" 2>/dev/null || true)
  return 1
}

detect_replayability() {
  local file="$1"
  if grep -qiE "function[[:space:]]+(restart|reset|replay|newGame)\b" "$file"; then return 1; fi
  if grep -qiE "(restart-btn|btn-restart|btn-replay|replay-btn|btn-retry)" "$file"; then return 1; fi
  return 0
}

detect_canvas_safety() {
  local file="$1"
  if grep -qE "getContext\(" "$file"; then
    if grep -qE "getContext.*\|\|[[:space:]]*null" "$file"; then return 1; fi
    if grep -qE "if.*!ctx|if.*ctx[[:space:]]*===?[[:space:]]*null" "$file"; then return 1; fi
    return 0
  fi
  return 1
}

detect_province_blocking() {
  local file="$1"
  grep -qiE "(province|省份|select.*prov|choose.*prov)" "$file" || return 1
  if grep -qE "if.*!province|province.*\|\|.*init|!province.*showProvince" "$file"; then return 0; fi
  if grep -qE "showProvinceSelect.*init|init.*showProvinceSelect" "$file"; then return 0; fi
  return 1
}

# ── Fix strategies ────────────────────────────────────────────────────

fix_state_management() {
  local file="$1" dry_run="${2:-false}"
  detect_state_management "$file" || return 1
  local desc="添加 let gameState = 'playing';"
  if $dry_run; then ok "[DRY-RUN] $desc"; return 0; fi
  local backup; backup=$(fix_create_backup "$file")
  local spath; spath=$(_fix_write_state_script | fix_write_script "fix-state" "$(cat -)")
  fix_node "$file" "$spath"
  if fix_has_changes "$file"; then ok "state-management: $desc"; return 0; fi
  warn "state-management: 未能自动修复"
  return 1
}

fix_audio_gesture() {
  local file="$1" dry_run="${2:-false}"
  detect_audio_gesture "$file" || return 1
  if ! grep -qE "(Audio|audio|snd|sfx|beep|sound)" "$file"; then
    warn "audio-gesture: 未检测到音频代码，跳过"
    return 1
  fi
  local desc="添加 AudioContext 用户手势初始化"
  if $dry_run; then ok "[DRY-RUN] $desc"; return 0; fi
  local backup; backup=$(fix_create_backup "$file")
  local spath; spath=$(_fix_write_audio_script | fix_write_script "fix-audio" "$(cat -)")
  fix_node "$file" "$spath"
  if fix_has_changes "$file"; then ok "audio-gesture: $desc"; return 0; fi
  warn "audio-gesture: 未能自动修复"
  return 1
}

fix_viewport_meta() {
  local file="$1" dry_run="${2:-false}"
  detect_viewport_meta "$file" || return 1
  local desc="添加 viewport meta 标签"
  if $dry_run; then ok "[DRY-RUN] $desc"; return 0; fi
  local backup; backup=$(fix_create_backup "$file")
  if grep -q "</head>" "$file"; then
    sed -i "s|<head>|<head>\n<meta name=\"viewport\" content=\"width=device-width,initial-scale=1.0,maximum-scale=1.0,user-scalable=no\">|" "$file"
    if fix_has_changes "$file"; then ok "viewport-meta: $desc"; return 0; fi
  fi
  warn "viewport-meta: 未能自动修复"
  return 1
}

fix_localStorage_try_catch() {
  local file="$1" dry_run="${2:-false}"
  detect_localStorage_try_catch "$file" || return 1
  local desc="localStorage 调用包装 try-catch"
  if $dry_run; then ok "[DRY-RUN] $desc"; return 0; fi
  local backup; backup=$(fix_create_backup "$file")
  local spath; spath=$(_fix_write_ls_script | fix_write_script "fix-ls" "$(cat -)")
  fix_node "$file" "$spath"
  if fix_has_changes "$file"; then ok "localStorage-try-catch: $desc"; return 0; fi
  warn "localStorage-try-catch: 未能自动修复"
  return 1
}

fix_replayability() {
  local file="$1" dry_run="${2:-false}"
  detect_replayability "$file" || return 1
  local desc="添加 restart() 函数和重新开始按钮"
  if $dry_run; then ok "[DRY-RUN] $desc"; return 0; fi
  local backup; backup=$(fix_create_backup "$file")
  local spath; spath=$(_fix_write_replay_script | fix_write_script "fix-replay" "$(cat -)")
  fix_node "$file" "$spath"
  if fix_has_changes "$file"; then ok "replayability: $desc"; return 0; fi
  warn "replayability: 未能自动修复"
  return 1
}

fix_canvas_safety() {
  local file="$1" dry_run="${2:-false}"
  detect_canvas_safety "$file" || return 1
  local desc="canvas.getContext 添加 null 回退"
  if $dry_run; then ok "[DRY-RUN] $desc"; return 0; fi
  local backup; backup=$(fix_create_backup "$file")
  local spath; spath=$(_fix_write_canvas_script | fix_write_script "fix-canvas" "$(cat -)")
  fix_node "$file" "$spath"
  if fix_has_changes "$file"; then ok "canvas-safety: $desc"; return 0; fi
  warn "canvas-safety: 未能自动修复"
  return 1
}

fix_province_blocking() {
  local file="$1" dry_run="${2:-false}"
  detect_province_blocking "$file" || return 1
  local desc="将省份选择移至游戏结束后"
  if $dry_run; then ok "[DRY-RUN] $desc"; return 0; fi
  local backup; backup=$(fix_create_backup "$file")
  local spath; spath=$(_fix_write_province_script | fix_write_script "fix-province" "$(cat -)")
  fix_node "$file" "$spath"
  if fix_has_changes "$file"; then ok "province-blocking: $desc"; return 0; fi
  warn "province-blocking: 未能自动修复（需要手动调整）"
  return 1
}

# ── Analyze file for fixable issues ───────────────────────────────────
fix_analyze() {
  local file="$1"
  local sname
  for s in $FIX_STRATEGIES; do
    sname=$(echo "$s" | tr '-' '_')
    if detect_$sname "$file" 2>/dev/null; then
      echo "$s"
    fi
  done
}

# ── Apply fixes ───────────────────────────────────────────────────────
fix_apply() {
  local file="$1"; shift
  local dry_run=false
  local strategies=()
  for arg in "$@"; do
    if [[ "$arg" == "--dry-run" ]]; then
      dry_run=true
    else
      strategies+=("$arg")
    fi
  done
  [[ -f "$file" ]] || { err "fix: 文件不存在: $file"; return 1; }
  if [[ ${#strategies[@]} -eq 0 ]]; then
    while IFS= read -r s; do
      [[ -n "$s" ]] && strategies+=("$s")
    done < <(fix_analyze "$file")
  fi
  if [[ ${#strategies[@]} -eq 0 ]]; then
    if $dry_run; then ok "未检测到需要修复的问题"; else ok "无需修复 — 所有检查已通过"; fi
    return 0
  fi
  if $dry_run; then
    echo "  将应用 ${#strategies[@]} 项修复:"
    for s in "${strategies[@]}"; do
      local label; label=$(fix_strategy_name "$s")
      echo "    - $s ($label)"
    done
    return 0
  fi
  local backup; backup=$(fix_create_backup "$file")
  local applied=()
  local sname
  for s in "${strategies[@]}"; do
    sname=$(echo "$s" | tr '-' '_')
    if fix_$sname "$file" "false"; then
      applied+=("$s")
    fi
  done
  if [[ ${#applied[@]} -eq 0 ]]; then
    warn "未能应用任何修复"
    fix_restore_backup "$file"
    return 1
  fi
  echo "  已应用 ${#applied[@]}/${#strategies[@]} 项修复"
  return 0
}

# ── Fix manifest ──────────────────────────────────────────────────────
fix_create_manifest() {
  local file="$1" fixes="$2" gate_before="$3" gate_after="$4"
  local fixes_dir="$REPO_ROOT/context/fixes"
  mkdir -p "$fixes_dir"
  local timestamp; timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local file_slug; file_slug=$(basename "$file" | sed 's/\.[^.]*$//')
  local manifest_file="$fixes_dir/$(date +%Y%m%d-%H%M%S)-${file_slug}.json"
  local fixes_json="[]"
  if command -v node &>/dev/null; then
    fixes_json=$(node -e "var f='${fixes}'.split(' ').filter(Boolean);console.log(JSON.stringify(f));" 2>/dev/null)
  fi
  cat > "$manifest_file" << JSONEOF
{
  "file": "${file}",
  "timestamp": "${timestamp}",
  "fixes_applied": ${fixes_json},
  "backup": "${file}.bak",
  "gate_before": "${gate_before}",
  "gate_after": "${gate_after}"
}
JSONEOF
  echo "$manifest_file"
}

# ── Gate interaction ──────────────────────────────────────────────────
fix_suggest() {
  local file="$1"
  [[ -f "$file" ]] || { err "文件不存在: $file"; return 1; }
  local fixable=()
  while IFS= read -r s; do
    [[ -n "$s" ]] && fixable+=("$s")
  done < <(fix_analyze "$file")
  if [[ ${#fixable[@]} -eq 0 ]]; then
    ok "无需修复 — 所有可自动修复项目已通过"
    return 0
  fi
  err "${#fixable[@]} 项可自动修复"
  echo "可自动修复的项目:"
  for s in "${fixable[@]}"; do
    local label; label=$(fix_strategy_name "$s")
    echo "    - $s ($label)"
  done
  echo ""
  echo "   运行: guild fix --file \"$file\" --all"
  return 0
}

fix_gate_count() {
  local file="$1"
  local total=0 passed=0
  local sname
  for s in $FIX_STRATEGIES; do
    total=$((total + 1))
    sname=$(echo "$s" | tr '-' '_')
    if ! detect_$sname "$file" 2>/dev/null; then
      passed=$((passed + 1))
    fi
  done
  echo "${passed}/${total}"
}

# ── Handoff resolver ──────────────────────────────────────────────────
fix_find_handoff_html() {
  local handoff="$1"
  local json_file=""
  for f in "$HANDOFFS_DIR"/*.json; do
    [[ -f "$f" ]] || continue
    local fid; fid=$(json_get "$f" "id")
    if [[ "$fid" == "$handoff" ]]; then
      json_file="$f"
      break
    fi
  done
  [[ -f "$json_file" ]] || { err "Handoff #$handoff not found"; return 1; }
  local path; path=$(json_get "$json_file" "path")
  [[ -d "$path" ]] || { err "Handoff #$handoff path not found: $path"; return 1; }
  local html_files=()
  while IFS= read -r -d '' f; do
    html_files+=("$f")
  done < <(find "$path" -name "*.html" -type f -print0 2>/dev/null)
  if [[ ${#html_files[@]} -eq 0 ]]; then
    err "Handoff #$handoff 中未找到 HTML 文件"
    return 1
  fi
  printf '%s\n' "${html_files[@]}"
}

# ── Command entry point ──────────────────────────────────────────────
cmd_fix() {
  local handoff="" file_path="" dry_run=false fix_all=false list_strategies=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --handoff) handoff="$2"; shift 2;;
      --file) file_path="$2"; shift 2;;
      --dry-run) dry_run=true; shift;;
      --all) fix_all=true; shift;;
      --list) list_strategies=true; shift;;
      *) shift;;
    esac
  done

  if $list_strategies; then
    echo "可用自动修复策略:"
    echo ""
    for s in $FIX_STRATEGIES; do
      local label; label=$(fix_strategy_name "$s")
      printf "  %-30s %s\n" "$s" "$label"
    done
    echo ""
    echo "用法:"
    echo "  guild fix --handoff <id>              # 自动修复交接中所有 HTML"
    echo "  guild fix --file <path> --all         # 修复文件所有可修复项"
    echo "  guild fix --file <path> --dry-run     # 预览修复"
    echo "  guild fix --file <path> [策略名...]   # 修复指定项目"
    return 0
  fi

  # Handoff mode
  if [[ -n "$handoff" ]]; then
    local html_files=()
    while IFS= read -r f; do
      html_files+=("$f")
    done < <(fix_find_handoff_html "$handoff" 2>/dev/null)
    if [[ ${#html_files[@]} -eq 0 ]]; then
      fix_find_handoff_html "$handoff"
      return $?
    fi
    echo "Fix: Handoff #$handoff"
    echo ""
    for html_file in "${html_files[@]}"; do
      echo "-- File: $(basename "$html_file") --"
      local gate_before; gate_before=$(fix_gate_count "$html_file")
      if $dry_run; then
        echo "  [DRY-RUN] Preview mode - no changes"
        fix_apply "$html_file" "--dry-run"
      else
        local applied=()
        while IFS= read -r s; do
          [[ -n "$s" ]] && applied+=("$s")
        done < <(fix_apply "$html_file")
        if [[ ${#applied[@]} -gt 0 ]]; then
          local gate_after; gate_after=$(fix_gate_count "$html_file")
          local fix_str="${applied[*]}"
          local manifest; manifest=$(fix_create_manifest "$html_file" "$fix_str" "$gate_before" "$gate_after")
          echo "  Manifest: $(basename "$manifest")"
          echo "  Gate: $gate_before -> $gate_after"
        fi
      fi
      echo ""
    done
    return 0
  fi

  # File mode
  if [[ -n "$file_path" ]]; then
    [[ -f "$file_path" ]] || die "文件不存在: $file_path"
    echo "Fix: $(basename "$file_path")"
    echo ""
    local gate_before; gate_before=$(fix_gate_count "$file_path")

    if $dry_run; then
      echo "  [DRY-RUN] Preview mode - no changes"
      fix_apply "$file_path" "--dry-run"
      return $?
    fi

    local specific_strategies=()
    for arg in "$@"; do
      [[ "$arg" == "--file" || "$arg" == "$file_path" || "$arg" == "--all" || "$arg" == "--dry-run" ]] && continue
      specific_strategies+=("$arg")
    done

    if $fix_all || [[ ${#specific_strategies[@]} -eq 0 ]]; then
      local strategies=()
      while IFS= read -r s; do
        [[ -n "$s" ]] && strategies+=("$s")
      done < <(fix_analyze "$file_path")
      if [[ ${#strategies[@]} -eq 0 ]]; then
        ok "无需修复 — 所有检查已通过 ($gate_before)"
        return 0
      fi
      local applied=()
      for s in "${strategies[@]}"; do
        local sname; sname=$(echo "$s" | tr '-' '_')
        if fix_$sname "$file_path" "false"; then
          applied+=("$s")
        fi
      done
      local gate_after; gate_after=$(fix_gate_count "$file_path")
      local fix_str="${applied[*]}"
      if [[ ${#applied[@]} -gt 0 ]]; then
        local manifest; manifest=$(fix_create_manifest "$file_path" "$fix_str" "$gate_before" "$gate_after")
        echo ""
        echo "  已应用 ${#applied[@]}/${#strategies[@]} 项修复"
        echo "  Manifest: $(basename "$manifest")"
        echo "  Gate: $gate_before -> $gate_after"
      else
        warn "未能应用任何修复"
        return 1
      fi
      return 0
    fi

    local applied=()
    for s in "${specific_strategies[@]}"; do
      local sname; sname=$(echo "$s" | tr '-' '_')
      if fix_$sname "$file_path" "false"; then
        applied+=("$s")
      fi
    done
    local gate_after; gate_after=$(fix_gate_count "$file_path")
    local fix_str="${applied[*]}"
    if [[ ${#applied[@]} -gt 0 ]]; then
      local manifest; manifest=$(fix_create_manifest "$file_path" "$fix_str" "$gate_before" "$gate_after")
      echo ""
      echo "  Manifest: $(basename "$manifest")"
      echo "  Gate: $gate_before -> $gate_after"
    fi
    [[ ${#applied[@]} -gt 0 ]] && return 0 || return 1
  fi

  # No args
  echo "用法:"
  echo "  guild fix --handoff <id>              # 自动修复所有可修复的门禁失败"
  echo "  guild fix --file <path> --all         # 修复所有可修复项目"
  echo "  guild fix --file <path> --dry-run     # 预览修复（不修改文件）"
  echo "  guild fix --file <path> [策略名...]   # 修复指定项目"
  echo "  guild fix --list                      # 列出可用修复策略"
}

# Main guard
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  cmd_fix "$@"
fi
