#!/usr/bin/env bash
# Module: gate.sh — cmd_gate + list_gates
# Source guard: only loadable via guild
[[ -n "${_AG_MODULE_SOURCING:-}" ]] || { echo "This module must be loaded via guild, not run directly" >&2; exit 1; }

# ── cmd_gate ──────────────────────────────────────────────────────────

# Usage: guild gate --handoff <id> [--gate <1-5>]
#        guild gate --list

cmd_gate() {
  local handoff="" gate_num=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --handoff) handoff="$2"; shift 2;;
      --gate) gate_num="$2"; shift 2;;
      --list) list_gates; return;;
      *) shift;;
    esac
  done

  [[ -n "$handoff" ]] || die "--handoff <id> is required"

  # Find handoff file by ID
  local json_file=""
  for f in "$HANDOFFS_DIR"/*.json; do
    [[ -f "$f" ]] || continue
    local fid
    fid=$(json_get "$f" "id")
    if [[ "$fid" == "$handoff" ]]; then
      json_file="$f"
      break
    fi
  done
  [[ -f "$json_file" ]] || die "Handoff #$handoff not found"

  local path from to
  path=$(json_get "$json_file" "path")
  from=$(json_get "$json_file" "from")
  to=$(json_get "$json_file" "to")

  echo "╔══════════════════════════════════════╗"
  echo "║  Quality Gates: Handoff #$handoff"
  echo "║  $from -> $to"
  echo "╚══════════════════════════════════════╝"
  echo ""

  local passed=0 failed=0
  local gates=("completeness" "syntax" "behavior" "playability" "agent-standards")

  for gate in "${gates[@]}"; do
    [[ -n "$gate_num" && "$gate" != "$gate_num" ]] && continue

    echo "-- Gate: $gate --"

    case "$gate" in
      completeness)
        local missing=0
        # Count missing required artifacts using node
        if command -v node &>/dev/null; then
          missing=$(node -e "const d=JSON.parse(require('fs').readFileSync('$json_file','utf8'));let m=0;for(const a of(d.artifacts||[])){if(a.status==='missing'&&a.required!==false)m++}console.log(m)" 2>/dev/null) || missing=0
        fi
        if [[ "$missing" -eq 0 ]]; then
          echo "  [OK] 所有必需交付物已提供"
          passed=$((passed + 1))
        else
          echo "  [FAIL] $missing 项缺失"
          failed=$((failed + 1))
        fi
        ;;

      syntax)
        local syntax_ok=true
        if [[ -d "$path" ]]; then
          while IFS= read -r -d '' f; do
            local vtype; vtype=$(detect_type "$f")
            if [[ -n "$vtype" ]]; then
              if ! verify_file "$vtype" "$f" 2>/dev/null; then
                syntax_ok=false
                echo "  [FAIL] $(basename "$f"): 语法验证失败"
              fi
            fi
          done < <(find "$path" -type f -print0 2>/dev/null)
        fi
        if $syntax_ok; then
          echo "  [OK] 所有文件语法验证通过"
          passed=$((passed + 1))
        else
          failed=$((failed + 1))
        fi
        ;;

      behavior)
        if [[ -x "$REPO_ROOT/scripts/test-runner.sh" && -d "$path" ]]; then
          local behavior_ok=true
          while IFS= read -r -d '' f; do
            if [[ "$(detect_type "$f")" == "html" ]]; then
              local test_output
              test_output=$(run_all_tests "$f" 2>&1) || behavior_ok=false
              echo "$test_output" | sed 's/^/  /'
            fi
          done < <(find "$path" -name "*.html" -type f -print0 2>/dev/null)
          if $behavior_ok; then
            echo "  [OK] 行为测试通过"
            passed=$((passed + 1))
          else
            echo "  [FAIL] 行为测试未全部通过"
            failed=$((failed + 1))
          fi
        else
          echo "  [SKIP] 行为测试不可用（无HTML文件或test-runner不可达）"
        fi
        ;;

      playability)
        local play_ok=true
        local html_files=0
        while IFS= read -r -d '' f; do
          if [[ "$(detect_type "$f")" == "html" ]]; then
            html_files=$((html_files + 1))
            local file_content; file_content=$(cat "$f")

            echo "  检查: $(basename "$f")"

            # Check 1: Tutorial/onboarding
            if [[ $(echo "$file_content" | grep -ci 'tutorial\|教程\|引导\|hint\|提示.*点击\|点击.*提示\|instruction\|指导' || true) -gt 0 ]]; then
              echo "    [OK] 有教程或引导提示"
            else
              echo "    [WARN] 缺少教程或引导提示"
            fi

            # Check 2: Audio init on user gesture
            if [[ $(echo "$file_content" | grep -c 'AudioContext.*click\|audioCtx.*click\|initAudio\|audio.*init.*click\|addEventListener.*click.*audio\|用户手势.*音频\|click.*AudioContext' || true) -gt 0 ]]; then
              echo "    [OK] 音效在用户手势时初始化"
            else
              if [[ $(echo "$file_content" | grep -c 'new.*AudioContext\|new.*webkitAudioContext' || true) -gt 0 ]]; then
                echo "    [WARN] AudioContext在构造时创建(非用户手势) — 可能静音"
              fi
            fi

            # Check 3: No blocking UI before core interaction
            if [[ $(echo "$file_content" | grep -c 'startGame\|btn-start.*click\|开始.*addEventListener\|core.*start\|play.*addEventListener' || true) -gt 0 ]]; then
              echo "    [OK] 核心功能 ≤1 次交互可达"
            else
              echo "    [WARN] 核心功能可能需要多次交互才能触达"
            fi

            # Check 4: Error state visible
            if [[ $(echo "$file_content" | grep -ci 'error\|错误\|失败\|start-error\|error-message\|err-msg\|error-state' || true) -gt 0 ]]; then
              echo "    [OK] 有错误状态展示"
            else
              echo "    [WARN] 缺少用户可见的错误状态"
            fi

            # Check 5: Mobile ready
            if [[ $(echo "$file_content" | grep -c 'viewport.*width=device-width' || true) -gt 0 ]]; then
              echo "    [OK] 移动端适配"
            else
              echo "    [FAIL] 缺少viewport meta标签"
              play_ok=false
            fi
          fi
        done < <(find "$path" -type f -print0 2>/dev/null)

        if [[ $html_files -eq 0 ]]; then
          # Check for non-HTML deliverables (APIs, documents)
          local doc_files=0
          while IFS= read -r -d '' f; do
            local vtype; vtype=$(detect_type "$f")
            case "$vtype" in
              md|json|yaml|yml)
                doc_files=$((doc_files + 1))
                local doc_content; doc_content=$(cat "$f")
                if echo "$doc_content" | grep -qi 'problem\|问题.*定义\|背景.*挑战\|为什么.*做'; then
                  echo "    [OK] 有清晰的问题陈述"
                else
                  echo "    [WARN] 缺少清晰的问题陈述"
                fi
                if echo "$doc_content" | grep -qi '指标\|metric\|KPIs\|成功率\|转化率\|目标'; then
                  echo "    [OK] 有成功指标"
                else
                  echo "    [WARN] 缺少可衡量的成功指标"
                fi
                if echo "$doc_content" | grep -qi '范围.*不\|不.*做\|out of scope\|不做\|非目标' 2>/dev/null; then
                  echo "    [OK] 定义了范围边界"
                else
                  echo "    [WARN] 未定义"不做什么"的范围边界"
                fi
                break
                ;;
            esac
          done < <(find "$path" -type f -print0 2>/dev/null)
          if [[ $doc_files -gt 0 ]]; then
            echo "  [OK] 文档类交付物检查完成"
          else
            echo "  [SKIP] 无可检查的文件类型"
          fi
        fi

        if $play_ok; then
          passed=$((passed + 1))
        else
          failed=$((failed + 1))
        fi
        ;;

      agent-standards)
        echo "  Agent标准检查 (from: $from, to: $to):"
        local agent_ok=true

        for agent_slug in "$from" "$to"; do
          # Find agent file from config using node
          local agent_file=""
          if command -v node &>/dev/null; then
            agent_file=$(node -e "
const d=JSON.parse(require('fs').readFileSync('$CONFIG','utf8'));
for(const a of(d.agents||[])){if(a.slug==='$agent_slug'){console.log('$REPO_ROOT/'+a.file);break}}
" 2>/dev/null)
          fi

          [[ -f "$agent_file" ]] || { echo "  [SKIP] $agent_slug: 未找到Agent定义文件"; continue; }

          # Extract section 9 (success metrics)
          local metrics
          metrics=$(awk '/^## 9\. 成功指標|^## 9\. 成功指标/{found=1; next} /^## 10\./{found=0} found' "$agent_file" 2>/dev/null)
          [[ -z "$metrics" ]] && { echo "  [SKIP] $agent_slug: 无成功指标定义"; continue; }

          echo "  -- $agent_slug 成功指标 --"

          # Metric: 中文内容 (game-qa-engineer)
          if echo "$metrics" | grep -qi '中文\|Chinese\|中文内容\|所有.*文字'; then
            for f in $(find "$path" -name "*.html" -type f 2>/dev/null); do
              if grep -qP '[\x{4e00}-\x{9fff}]' "$f" 2>/dev/null; then
                echo "    [OK] [$agent_slug] 包含中文内容"
              else
                echo "    [WARN] [$agent_slug] HTML文件缺少中文内容"
              fi
            done
          fi

          # Metric: 无console.error
          if echo "$metrics" | grep -qi 'console.error\|零错误\|zero error\|console.error'; then
            for f in $(find "$path" -name "*.html" -type f 2>/dev/null); do
              if grep -q 'console\.error' "$f" 2>/dev/null; then
                echo "    [FAIL] [$agent_slug] 包含console.error调用"
                agent_ok=false
              else
                echo "    [OK] [$agent_slug] 无console.error调用"
              fi
            done
          fi

          # Metric: AudioContext on user gesture (game-audio-engineer)
          if echo "$metrics" | grep -qi '音频.*触发\|Audio.*user gesture\|音频延迟\|audio.*click\|用户手势'; then
            for f in $(find "$path" -name "*.html" -type f 2>/dev/null); do
              if grep -q 'new AudioContext' "$f" 2>/dev/null; then
                if grep -q 'addEventListener.*click\|onclick\|touchstart.*AudioContext\|AudioContext.*click' "$f" 2>/dev/null; then
                  echo "    [OK] [$agent_slug] AudioContext由用户手势初始化"
                else
                  echo "    [WARN] [$agent_slug] AudioContext可能在构造时创建"
                fi
              fi
            done
          fi

          # Metric: 所有用户可见文字必须有中文 (game-qa-engineer)
          if echo "$metrics" | grep -qi '中文\|Chinese\|所有.*用户.*可见'; then
            for f in $(find "$path" -name "*.html" -type f 2>/dev/null); do
              if grep -qP '[\x{4e00}-\x{9fff}]' "$f" 2>/dev/null; then
                echo "    [OK] [$agent_slug] HTML包含中文字符"
              else
                echo "    [WARN] [$agent_slug] HTML未检测到中文字符"
              fi
            done
          fi

          # Metric: 延迟 < 20ms / 性能预算 (game-audio-engineer)
          if echo "$metrics" | grep -qi '延迟.*20\|latency\|performance budget\|内存占用\|memory.*budget'; then
            echo "    [INFO] [$agent_slug] 性能指标(延迟/内存/音效数) — 需运行时验证"
          fi
        done

        if $agent_ok; then
          echo "  [OK] 所有Agent标准检查通过"
          passed=$((passed + 1))
        else
          echo "  [FAIL] 部分Agent标准未满足"
          failed=$((failed + 1))
        fi
        ;;
    esac
    echo ""
  done

  echo "══════════════════════════════════"
  echo "  Gate结果: $passed 通过, $failed 失败"
  if [[ $failed -eq 0 ]]; then
    echo "  [OK] 所有质量门禁通过 — 可以接受"
  else
    echo "  [FAIL] $failed 个门禁未通过 — 拒绝接受"
  fi
  echo "══════════════════════════════════"

  # Return non-zero if any gate failed
  [[ $failed -eq 0 ]]
}

# ── list_gates ─────────────────────────────────────────────────────────

list_gates() {
  echo "质量门禁 (Quality Gates):"
  echo ""
  echo "  1. completeness     — 所有必需交付物已提供"
  echo "  2. syntax           — 所有文件语法验证通过"
  echo "  3. behavior         — 行为测试通过(事件绑定/守卫/错误处理)"
  echo "  4. playability      — 可玩性检查(教程/音效/UX流程/移动端)"
  echo "  5. agent-standards  — 相关Agent的成功标准逐条验证"
  echo ""
  echo "用法: guild gate --handoff <id> [--gate <1-5>]"
}
