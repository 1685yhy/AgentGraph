#!/usr/bin/env bash
# Module: graph.sh — cmd_graph
# Source guard: only loadable via guild
[[ -n "${_AG_MODULE_SOURCING:-}" ]] || { echo "This module must be loaded via guild, not run directly" >&2; exit 1; }

# ── cmd_graph ──────────────────────────────────────────────────────────

# Usage: guild graph run   --graph <name> --path <dir> [--dry-run] [--yes]
#        guild graph status [--graph <name>]
#        guild graph show   <name>
#        guild graph list

cmd_graph() {
  local sub="${1:-run}"; shift || true

  case "$sub" in
    run)
      local graph="" path="" dry_run=false auto_yes=false
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --graph) graph="$2"; shift 2;;
          --path) path="$2"; shift 2;;
          --dry-run) dry_run=true; shift;;
          --yes) auto_yes=true; shift;;
          *) shift;;
        esac
      done
      [[ -n "$graph" ]] || die "--graph <name> is required"
      [[ -d "$path" ]] || die "--path must be a directory: $path"

      local graph_file="$REPO_ROOT/graphs/${graph}.yml"
      [[ -f "$graph_file" ]] || die "Graph not found: $graph"

      echo "╔══════════════════════════════════════════╗"
      echo "║  Graph Engine: $graph"
      echo "╚══════════════════════════════════════════╝"

      # Source and run graph engine
      source "$REPO_ROOT/scripts/graph-engine.sh"
      # Temp disable errexit/nounset for graph engine (it has its own error handling)
      set +euo pipefail
      run_graph "$graph_file" "$path" "$dry_run" "$auto_yes"
      local graph_rc=$?
      set -euo pipefail
      return $graph_rc
      ;;

    resume)
      local graph="" path="" auto_yes=false
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --graph) graph="$2"; shift 2;;
          --path) path="$2"; shift 2;;
          --yes) auto_yes=true; shift;;
          *) shift;;
        esac
      done
      [[ -n "$graph" ]] || die "--graph <name> is required"
      [[ -d "$path" ]] || die "--path must be a directory: $path"

      local graph_file="$REPO_ROOT/graphs/${graph}.yml"
      [[ -f "$graph_file" ]] || die "Graph not found: $graph"

      echo "╔══════════════════════════════════════════╗"
      echo "║  Graph Engine: $graph (恢复模式)"
      echo "╚══════════════════════════════════════════╝"

      source "$REPO_ROOT/scripts/graph-engine.sh"
      set +euo pipefail
      parse_graph "$graph_file" || return 1
      resume_graph "$graph" "$path" "$auto_yes"
      local graph_rc=$?
      set -euo pipefail
      return $graph_rc
      ;;

    status)
      local graph_name="${1:-}"
      # Show graph execution state
      if [[ -n "$graph_name" ]]; then
        local state_basename="$graph_name"
        local graph_file="$REPO_ROOT/graphs/${graph_name}.yml"
        if [[ -f "$graph_file" ]]; then
          state_basename=$(basename "$graph_file" .yml)
          state_basename=$(basename "$state_basename" .yaml)
        fi
        local state_file="/tmp/guild-graph-${state_basename}-state.json"
        # Fallback: try raw name
        [[ -f "$state_file" ]] || state_file="/tmp/guild-graph-${graph_name}-state.json"
        [[ -f "$state_file" ]] || { echo "图 \"$graph_name\" 无运行中的状态"; return 0; }
        if command -v node &>/dev/null; then
          node -e "
const d=JSON.parse(require('fs').readFileSync('$state_file','utf8'));
console.log('图状态: ${graph_name}');
console.log('迭代: '+d.current_iteration||0);console.log();
const icons={'pending':'⏳','running':'🔄','completed':'✅','failed':'❌','timeout':'⌛','exhausted':'💀'};
for(const[k,n]of Object.entries(d.nodes)){console.log('  '+(icons[n.status]||'⬜')+' '+k+': '+n.status)}
" 2>/dev/null || cat "$state_file"
        else
          cat "$state_file"
        fi
      else
        # List all running graph states
        local found=false
        for f in /tmp/guild-graph-*-state.json; do
          [[ -f "$f" ]] || continue
          found=true
          local gname; gname=$(basename "$f" | sed 's/guild-graph-//;s/-state.json//')
          echo "  图: $gname"
          if command -v node &>/dev/null; then
            node -e "
const d=JSON.parse(require('fs').readFileSync('$f','utf8'));
const ns=Object.values(d.nodes||{});
const done=ns.filter(n=>n.status==='completed').length;
const failed=ns.filter(n=>n.status==='failed').length;
console.log('    节点: '+done+'/'+ns.length+' 完成, '+failed+' 失败');
console.log('    迭代: '+(d.current_iteration||0));
" 2>/dev/null
          fi
        done
        $found || echo "  无运行中的图"
      fi
      ;;

    show)
      local graph="${1:-}"
      [[ -n "$graph" ]] || die "usage: guild graph show <name>"
      local graph_file="$REPO_ROOT/graphs/${graph}.yml"
      [[ -f "$graph_file" ]] || die "Graph not found: $graph"

      echo "=== Graph: $graph ==="
      echo ""
      echo "Nodes:"
      grep -E '^  [a-z]' "$graph_file" | sed 's/://;s/^/  /'
      echo ""
      echo "Edges:"
      grep -A1 '^edges:' "$graph_file" | tail -n +2
      ;;

    list)
      echo "可用图:"
      local any=false
      for f in "$REPO_ROOT/graphs"/*.yml; do
        [[ -f "$f" ]] || continue
        any=true
        local name; name=$(grep '^name:' "$f" | head -1 | sed 's/name: *//')
        local desc; desc=$(grep '^description:' "$f" | head -1 | sed 's/description: *//')
        echo "  $(basename "$f" .yml) — $name"
        [[ -n "$desc" ]] && echo "    $desc"
      done
      $any || echo "  (无图定义)"
      ;;

    *)
      echo "用法: guild graph [run|status|show|list]"
      echo ""
      echo "  run    — 执行图"
      echo "  status — 查看图执行状态"
      echo "  show   — 显示图结构"
      echo "  list   — 列出可用图"
      ;;
  esac
}
