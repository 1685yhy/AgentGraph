#!/usr/bin/env bash
#
# agent-runner.sh — AgentGraph Runtime: single-agent executor.
# Reads agent identity → builds prompt → calls LLM → saves output → creates handoff.
#
# Usage:
#   guild run-agent <slug> "<task>" [--upstream <handoff-id>]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

. "$REPO_ROOT/scripts/lib.sh"

LLM_BACKEND="$SCRIPT_DIR/llm-backend.js"
MEMORY_LIMIT=3  # inject last N memories into prompt

# ── run_agent ──────────────────────────────────────────────────
run_agent() {
  local slug="$1" task="$2" upstream="${3:-}"
  local agent_file emoji name
  agent_file=$(agent_file "$slug")
  [[ -z "$agent_file" ]] && { err "Unknown agent: $slug"; return 1; }
  name=$(agent_frontmatter "$slug" "name")
  emoji=$(agent_frontmatter "$slug" "emoji")
  local short; short=$(agent_frontmatter "$slug" "short")

  echo "╔══════════════════════════════════════════╗"
  echo "║  ${emoji} Agent Runner: ${name} (${slug})"
  echo "║  Task: ${task:0:60}"
  echo "╚══════════════════════════════════════════╝"

  # ── 1. Build system prompt from agent identity ──
  local system_prompt; system_prompt=$(agent_prompt "$slug" 2>/dev/null)
  if [[ -z "$system_prompt" ]]; then
    system_prompt=$(cat "$agent_file")
  fi

  # ── 2. Inject memory context ──
  local mem_ctx; mem_ctx=$(agent_memory_load "$slug" "$MEMORY_LIMIT" 2>/dev/null || echo "")
  if [[ -n "$mem_ctx" ]]; then
    system_prompt="${system_prompt}

## 🧠 历史记忆 (最近 ${MEMORY_LIMIT} 次任务)
${mem_ctx}"
  fi

  # ── 3. Inject upstream outputs if any ──
  if [[ -n "$upstream" ]]; then
    local upstream_file="$REPO_ROOT/handoffs/${upstream}.json"
    if [[ -f "$upstream_file" ]]; then
      local upstream_content
      upstream_content=$(node -e "const d=JSON.parse(require('fs').readFileSync('$upstream_file','utf8'));console.log(d.output||d.summary||'')" 2>/dev/null || echo "(upstream content unavailable)")
      system_prompt="${system_prompt}

## 📥 上游交付物 (handoff #${upstream})
${upstream_content}"
    fi
  fi

  # ── 4. Build user prompt ──
  local user_prompt="## 📋 当前任务
${task}

## 📤 输出要求
请以 ${name} 的身份完成此任务。输出你的工作成果和决策理由。
完成后，AgentGraph 会自动将你的产出交接给下一个 Agent。"

  # ── 5. Call LLM ──
  echo "  🤖 调用 LLM (${AG_LLM_PROVIDER:-anthropic}/${AG_LLM_MODEL:-default})..."
  local output; output=$(node "$LLM_BACKEND" --system "$system_prompt" --prompt "$user_prompt" 2>/tmp/agentgraph-llm-error.log)
  local rc=$?

  if [[ $rc -ne 0 ]]; then
    err "LLM 调用失败 (exit $rc)"
    cat /tmp/agentgraph-llm-error.log >&2
    return $rc
  fi

  # ── 6. Save output ──
  local output_dir="$REPO_ROOT/context/outputs/${slug}"
  mkdir -p "$output_dir"
  local output_file="$output_dir/$(date +%Y%m%d-%H%M%S).md"
  echo "$output" > "$output_file"
  ok "Output saved: $(basename "$output_file")"

  # ── 7. Save to agent memory ──
  agent_memory_save "$slug" "$task" "$(echo "$output" | head -c 500)" > /dev/null 2>&1 || true

  # ── 8. Auto-create handoff to downstream (graph executor handles this) ──
  # The graph executor will detect completion and create the proper handoff.
  # For standalone use: print dispatch info
  local dispatch_id="d-${slug}-$(date +%s)"

  echo ""
  echo "  ✅ 完成: ${emoji} ${name}"
  echo "  📄 输出: $output_file"
  echo "  🏷️  Dispatch: $dispatch_id"
  echo ""

  # Return structured result via stdout (for graph executor to parse)
  echo "AGENT_RESULT: slug=$slug dispatch=$dispatch_id output=$output_file rc=0"
}

# ── CLI ──
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  run_agent "$@"
fi
