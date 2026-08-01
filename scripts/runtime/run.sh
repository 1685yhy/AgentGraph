#!/usr/bin/env bash
#
# run.sh — AgentGraph Runtime: top-level orchestrator.
#
# Usage:
#   guild run --graph <name> --task "<description>" [--yes]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

. "$REPO_ROOT/scripts/lib.sh"
. "$SCRIPT_DIR/event-bus.sh"
. "$REPO_ROOT/scripts/graph-engine.sh"

AGENT_RUNNER="$SCRIPT_DIR/agent-runner.sh"

# classify_task_fallback lives in scripts/graph-generator.sh (sourced by
# nexus.sh). Provide a minimal fallback so run.sh also works standalone.
if ! declare -F classify_task_fallback >/dev/null 2>&1; then
  classify_task_fallback() { echo "web-app"; }
fi

declare -A NODE_STATES   # node_name → pending|running|completed|failed
declare -A NODE_OUTPUTS  # node_name → output_file_path

# ── Main orchestrator ──
cmd_run() {
  local graph_name="" task="" yes_mode=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --graph) graph_name="$2"; shift 2 ;;
      --task) task="$2"; shift 2 ;;
      --yes) yes_mode=true; shift ;;
      *) shift ;;
    esac
  done

  [[ -z "$graph_name" ]] && { err "Usage: guild run --graph <name> --task \"<description>\""; return 1; }
  [[ -z "$task" ]] && { err "Task description required"; return 1; }

  local graph_file="$REPO_ROOT/graphs/${graph_name}.yml"
  [[ -f "$graph_file" ]] || { err "Graph not found: $graph_name (expected $graph_file)"; return 1; }

  echo "╔══════════════════════════════════════════╗"
  echo "║  AgentGraph Runtime — 自动执行引擎      ║"
  echo "║  Graph: $graph_name                     ║"
  echo "║  Task: ${task:0:40}                     ║"
  echo "╚══════════════════════════════════════════╝"
  echo ""

  # ── 1. Classify + plan ──
  echo "── 📋 Step 1: 任务分析 ──"
  local type; type=$(classify_task_fallback "$task")
  echo "  类型: $type"

  # ── 2. Parse Graph YAML → dependency map ──
  echo "── 🗺️  Step 2: 解析 Graph ──"
  local graph_yaml; graph_yaml=$(cat "$graph_file")

  # Extract nodes and their needs using python3 or node
  local nodes_json
  nodes_json=$(echo "$graph_yaml" | node -e "
    const { readFileSync } = require('fs');
    const yaml = readFileSync('/dev/stdin', 'utf8');
    // Simple YAML parser for our restricted format
    const nodes = {};
    let current = null;
    yaml.split('\n').forEach(line => {
      const nodeMatch = line.match(/^  (\w[\w-]*):$/);
      const agentMatch = line.match(/^\s*agent:\s*(\S+)/);
      const needsMatch = line.match(/^\s*needs?:\s*\[(.*)\]/);

      if (nodeMatch && !line.includes('when:')) {
        current = nodeMatch[1];
        nodes[current] = { agent: '', needs: [], delivers: [] };
      }
      if (current && agentMatch) nodes[current].agent = agentMatch[1];
      if (current && needsMatch) {
        const n = needsMatch[1].replace(/['\"]/g, '').split(',').map(s=>s.trim()).filter(Boolean);
        nodes[current].needs = n;
      }
    });
    console.log(JSON.stringify(nodes));
  " 2>/dev/null || echo "{}")

  local node_count; node_count=$(echo "$nodes_json" | node -e "console.log(Object.keys(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'))).length)" 2>/dev/null || echo 0)

  if [[ "$node_count" -eq 0 ]]; then
    err "Graph parsing failed — no nodes found in $graph_file"
    return 1
  fi

  echo "  节点数: $node_count"

  # ── 3. Initialize node states ──
  echo "── 🚀 Step 3: 执行引擎启动 ──"
  echo "$nodes_json" | node -e "
    const nodes = JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    for (const [name, info] of Object.entries(nodes)) {
      console.log('NODE:'+name+' agent='+info.agent+' needs='+(info.needs.join(',' )||'none'));
    }
  "

  # Find initial nodes (no dependencies)
  local initial_nodes
  initial_nodes=$(echo "$nodes_json" | node -e "
    const nodes = JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    console.log(Object.entries(nodes).filter(([n,i])=>i.needs.length===0).map(([n])=>n).join(' '));
  " 2>/dev/null)

  if [[ -z "$initial_nodes" ]]; then
    err "No initial nodes (all have dependencies) — check graph for circular deps"
    return 1
  fi
  echo "  初始节点: $initial_nodes"

  # ── 4. Execute initial nodes ──
  for node in $initial_nodes; do
    local agent_slug; agent_slug=$(echo "$nodes_json" | node -e "console.log(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'))['$node'].agent)" 2>/dev/null)
    echo ""
    echo "  ▶️  启动: $node ($agent_slug)"
    NODE_STATES["$node"]="running"

    # Run agent (agent-runner CLI: bash agent-runner.sh <slug> <task>)
    local result
    result=$(bash "$AGENT_RUNNER" "$agent_slug" "$task" 2>&1) || {
      NODE_STATES["$node"]="failed"
      err "Agent $agent_slug failed for node $node"
      echo "$result"
      continue
    }
    NODE_STATES["$node"]="completed"
    echo "$result"

    # Extract output path
    local output_path; output_path=$(echo "$result" | grep -oP 'output=\K\S+' | head -1)
    [[ -n "$output_path" ]] && NODE_OUTPUTS["$node"]="$output_path"
  done

  # ── 5. Event-driven continuation ──
  echo ""
  echo "── ⏳ Step 4: 等待下游节点 ──"

  local remaining
  remaining=$(echo "$nodes_json" | node -e "
    const nodes = JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    const done = '$initial_nodes'.split(' ').filter(Boolean);
    console.log(Object.keys(nodes).filter(n => !done.includes(n)).length);
  " 2>/dev/null || echo 0)

  if [[ "$remaining" -eq 0 ]]; then
    echo "  所有节点已完成，无需等待。"
  else
    echo "  剩余 $remaining 个节点待执行。以文件 handoff 方式触发下游 Agent。"
    echo ""
    echo "  💡 当前版本: 初始节点已自动执行。"
    echo "     下游节点需通过 guild run-agent <slug> \"<task>\" --upstream <handoff-id> 手动触发，"
    echo "     或使用 guild watch + guild run-agent 组合实现自动流转。"
    echo ""
    echo "  📊 节点状态:"
    for node in "${!NODE_STATES[@]}"; do
      echo "    $node: ${NODE_STATES[$node]}"
    done
  fi

  # ── 6. Summary ──
  echo ""
  echo "══════════════════════════════════════════"
  echo "  执行完成"
  echo "  完成节点: $(echo "${NODE_STATES[@]}" | grep -o 'completed' | wc -l)"
  echo "  失败节点: $(echo "${NODE_STATES[@]}" | grep -o 'failed' | wc -l)"
  echo "══════════════════════════════════════════"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  cmd_run "$@"
fi
