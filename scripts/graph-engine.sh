#!/usr/bin/env bash
#
# graph-engine.sh — AgentGuild Graph Engine
# Executes agent workflows as directed graphs with loops and parallelism.
#
# Features:
#   1. Node timeout (default 120s, configurable per-node via YAML `timeout:`)
#   2. Human approval gate (action: approve, --yes for auto-approve)
#   3. Crash recovery (guild graph resume)
#   4. Complete report (timeout + exhausted nodes shown properly)
#   5. Edge condition validation (missing nodes, malformed when)
#   6. State file locking (flock for parallel safety)
#   7. State file corruption recovery (.bak backup + detection)
#   8. Node output capture (last 3 lines of stdout in state)
#   9. Full dry-run simulation (shows entire execution plan)
#   10. Empty delivers handling
#
# Architecture:
#   Node (节点) = Agent 执行一个动作
#   Edge (边)   = 依赖关系 + 流转条件
#   State (状态) = 整个图的共享进度
#
# Usage (sourced by nexus.sh):
#   run_graph <graph_file> <work_dir> [dry_run] [auto_yes]
#   resume_graph <graph_name> <work_dir> [auto_yes]
#
# State file: /tmp/guild-graph-<name>-state.json

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "ERROR: graph-engine.sh must be sourced, not executed directly." >&2
  echo "  source scripts/graph-engine.sh" >&2
  exit 1
fi

# Track engine directory for finding sibling scripts
_GRApH_ENGINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null)"

# ── Graph data (populated by parse_graph) ─────────────────────────

GRAPH_NAME=""
GRAPH_DESC=""
GRAPH_FILE=""

declare -A _NODE_AGENT
declare -A _NODE_ACTION
declare -A _NODE_NEEDS
declare -A _NODE_DELIVERS
declare -A _NODE_WHEN
declare -A _NODE_TIMEOUT
_NODE_ORDER=()

_EDGE_FROM=()
_EDGE_TO=()
_EDGE_WHEN=()
_EDGE_LABEL=()

_STATE_FILE=""
_TOPOLOGICAL_ORDER=()
_LAST_COMPLETED=""
declare -A _EDGES_PROCESSED
declare -A _NODE_RESULTS

# Default timeout for nodes (seconds)
DEFAULT_NODE_TIMEOUT=120

# ── State file locking ────────────────────────────────────────────
_LOCK_DEPTH=0
_LOCK_FD=""

_lock_state() {
  if [[ $_LOCK_DEPTH -eq 0 ]]; then
    local lock_file="${_STATE_FILE}.lock"
    exec {_LOCK_FD}>"$lock_file"
    flock -x "$_LOCK_FD" 2>/dev/null || true
  fi
  _LOCK_DEPTH=$((_LOCK_DEPTH + 1))
}

_unlock_state() {
  _LOCK_DEPTH=$((_LOCK_DEPTH - 1))
  if [[ $_LOCK_DEPTH -eq 0 ]]; then
    [[ -n "$_LOCK_FD" ]] && flock -u "$_LOCK_FD" 2>/dev/null || true
  fi
}

# Clean up lock on exit
_cleanup_graph_lock() {
  _LOCK_DEPTH=1
  _unlock_state
  rm -f "${_STATE_FILE}.lock" 2>/dev/null || true
}

# ── Helper: run embedded python script ────────────────────────────

# _run_py <func_name> [args...]
_run_py() {
  local func_name="$1"; shift
  local script_file; script_file=$(mktemp /tmp/guild-py-XXXXXX.py)
  "_py_${func_name}" > "$script_file" 2>/dev/null || {
    echo "Error: python function _py_${func_name} not found" >&2
    rm -f "$script_file"
    return 1
  }
  python3 "$script_file" "$@" 2>/dev/null
  local rc=$?
  rm -f "$script_file"
  return $rc
}

# ── YAML Parsing ──────────────────────────────────────────────────

# Parser script for graph YAML
_py_parse_graph() {
  cat << 'PYEOF'
import json, sys

def parse_list(v):
    v = v.strip()
    if v.startswith('['):
        items = [x.strip().strip("'").strip('"') for x in v.strip('[]').split(',') if x.strip()]
        return items
    return []

def parse_when_dict(v):
    v = v.strip()
    if v.startswith('{') and v.endswith('}'):
        inner = v[1:-1]
        result = {}
        parts = []
        depth = 0
        buf = ''
        for ch in inner:
            if ch == '{': depth += 1
            elif ch == '}': depth -= 1
            elif ch == ',' and depth == 0:
                parts.append(buf); buf = ''
                continue
            buf += ch
        if buf.strip():
            parts.append(buf)
        for part in parts:
            if ':' in part:
                k, kv = part.split(':', 1)
                result[k.strip()] = kv.strip().strip("'").strip('"')
        return result
    return {}

def indent_count(s):
    return len(s) - len(s.lstrip())

graph_file = sys.argv[1]
result = {
    'name': '', 'description': '',
    'nodes': {}, 'edges': [],
    'node_order': []
}
section = None
current_node = None

with open(graph_file, 'r', encoding='utf-8') as f:
    lines = f.readlines()

for line in lines:
    raw = line.rstrip()
    if not raw.strip():
        continue
    stripped = raw.strip()
    indent = indent_count(raw)

    if stripped == 'nodes:':
        section = 'nodes'; continue
    elif stripped == 'edges:':
        section = 'edges'; continue

    if section is None:
        if raw.startswith('name:'):
            result['name'] = stripped.split(':', 1)[1].strip().strip("'").strip('"')
        elif raw.startswith('description:'):
            result['description'] = stripped.split(':', 1)[1].strip().strip("'").strip('"')
        continue

    if section == 'nodes':
        if indent == 2 and ':' in stripped:
            current_node = stripped.rstrip(':').strip()
            result['nodes'][current_node] = {
                'agent': '', 'action': 'execute', 'needs': [],
                'delivers': [], 'when': {}, 'timeout': ''
            }
            result['node_order'].append(current_node)
        elif current_node and indent >= 4 and ': ' in raw:
            key, val = raw.split(':', 1)
            key = key.strip()
            val = val.strip()
            if key == 'needs':
                result['nodes'][current_node][key] = parse_list(val)
            elif key == 'delivers':
                result['nodes'][current_node][key] = parse_list(val)
            elif key == 'when':
                result['nodes'][current_node][key] = parse_when_dict(val)
            else:
                val = val.strip().strip("'").strip('"')
                result['nodes'][current_node][key] = val

    elif section == 'edges':
        if raw.strip().startswith('- '):
            inner = raw.strip()[2:].strip()
            if inner.startswith('{') and inner.endswith('}'):
                inner = inner[1:-1]
                edge = {}
                depth = 0
                buf = ''
                for ch in inner + ',':
                    if ch == '{': depth += 1
                    elif ch == '}': depth -= 1
                    elif ch == ',' and depth == 0:
                        if ':' in buf:
                            k, v = buf.split(':', 1)
                            edge[k.strip()] = v.strip().strip("'").strip('"')
                        buf = ''
                        continue
                    buf += ch
                if edge:
                    result['edges'].append(edge)

print(json.dumps(result, ensure_ascii=False))
PYEOF
}

# _py_emit_nodes — emit pipe-delimited node records (including timeout)
_py_emit_nodes() {
  cat << 'PYEOF'
import json, sys
d = json.load(sys.stdin)
nodes = d['nodes']
for nid in d.get('node_order', list(nodes.keys())):
    ndata = nodes[nid]
    needs = ','.join(ndata.get('needs', []))
    delivers = ','.join(ndata.get('delivers', []))
    w = ndata.get('when', {})
    when_parts = ['{}:{}'.format(k,v) for k,v in w.items()]
    when_str = ';'.join(when_parts)
    timeout = str(ndata.get('timeout', '') or '')
    print('{}|{}|{}|{}|{}|{}|{}'.format(nid, ndata.get('agent',''), ndata.get('action','execute'), needs, delivers, when_str, timeout))
PYEOF
}

# _py_emit_edges — emit pipe-delimited edge records
_py_emit_edges() {
  cat << 'PYEOF'
import json, sys
d = json.load(sys.stdin)
for e in d['edges']:
    print('{}|{}|{}|{}'.format(e.get('from',''), e.get('to',''), e.get('when',''), e.get('label','')))
PYEOF
}

# parse_graph <graph_file>
parse_graph() {
  local graph_file="$1"
  [[ -f "$graph_file" ]] || { err "Graph file not found: $graph_file"; return 1; }

  GRAPH_FILE="$graph_file"

  # Write parser script and run it
  local script_file; script_file=$(mktemp /tmp/guild-parse-XXXXXX.py)
  _py_parse_graph > "$script_file"

  local json
  json=$(python3 "$script_file" "$graph_file" 2>/dev/null)
  local parse_rc=$?
  rm -f "$script_file"

  if [[ $parse_rc -ne 0 || -z "$json" ]]; then
    err "Failed to parse graph YAML: $graph_file"
    return 1
  fi

  # Extract name and description
  GRAPH_NAME=$(echo "$json" | python3 -c "import json,sys; print(json.load(sys.stdin)['name'])" 2>/dev/null)
  GRAPH_DESC=$(echo "$json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('description',''))" 2>/dev/null)

  # Reset data
  _NODE_ORDER=()
  _EDGE_FROM=()
  _EDGE_TO=()
  _EDGE_WHEN=()
  _EDGE_LABEL=()

  # Parse nodes
  local node_script; node_script=$(mktemp /tmp/guild-nodes-XXXXXX.py)
  _py_emit_nodes > "$node_script"

  while IFS='|' read -r node_id agent action needs delivers when_str timeout_str; do
    [[ -z "$node_id" ]] && continue
    _NODE_ORDER+=("$node_id")
    _NODE_AGENT[$node_id]="$agent"
    _NODE_ACTION[$node_id]="$action"
    _NODE_NEEDS[$node_id]="$needs"
    _NODE_DELIVERS[$node_id]="$delivers"
    _NODE_WHEN[$node_id]="${when_str:-}"
    # Parse timeout: must be a positive integer, otherwise default
    if [[ "$timeout_str" =~ ^[0-9]+$ ]] && [[ "$timeout_str" -gt 0 ]]; then
      _NODE_TIMEOUT[$node_id]="$timeout_str"
    else
      _NODE_TIMEOUT[$node_id]="$DEFAULT_NODE_TIMEOUT"
    fi
  done < <(echo "$json" | python3 "$node_script" 2>/dev/null)
  rm -f "$node_script"

  # Parse edges
  local edge_script; edge_script=$(mktemp /tmp/guild-edges-XXXXXX.py)
  _py_emit_edges > "$edge_script"

  while IFS='|' read -r from to when label; do
    [[ -z "$from" || -z "$to" ]] && continue
    _EDGE_FROM+=("$from")
    _EDGE_TO+=("$to")
    _EDGE_WHEN+=("$when")
    _EDGE_LABEL+=("$label")
  done < <(echo "$json" | python3 "$edge_script" 2>/dev/null)
  rm -f "$edge_script"

  # Validate edge conditions
  _validate_edge_conditions

  _compute_topological_order
  return 0
}

# Validate edge conditions: warn about non-existent nodes referenced in edges
_validate_edge_conditions() {
  local issue_found=false

  for (( i = 0; i < ${#_EDGE_FROM[@]}; i++ )); do
    local from="${_EDGE_FROM[$i]}"
    local to="${_EDGE_TO[$i]}"
    local when="${_EDGE_WHEN[$i]}"
    local label="${_EDGE_LABEL[$i]}"

    # Check if from/to nodes exist
    if [[ -z "${_NODE_AGENT[$from]:-}" ]]; then
      warn "图边中源节点 '${from}' 不存在于图中 (边: ${from} -> ${to})"
      issue_found=true
    fi
    if [[ -z "${_NODE_AGENT[$to]:-}" ]]; then
      warn "图边中目标节点 '${to}' 不存在于图中 (边: ${from} -> ${to})"
      issue_found=true
    fi

    # Validate when format
    if [[ -n "$when" ]]; then
      # Malformed when: check it contains reasonable content
      if [[ "$when" != *"status"* && "$when" != *"passed"* && "$when" != *"failed"* && "$when" != *"completed"* ]]; then
        warn "边条件格式异常: when='${when}' (${from} -> ${to}), 将视为无条件"
        issue_found=true
      fi
    fi
  done

  # Also validate node-level when conditions
  for node_id in "${_NODE_ORDER[@]}"; do
    local when_str="${_NODE_WHEN[$node_id]}"
    if [[ -n "$when_str" ]]; then
      local cond_node="${when_str%%:*}"
      local cond_status="${when_str#*:}"
      # Check if cond_node exists in the graph
      if [[ -z "${_NODE_AGENT[$cond_node]:-}" ]]; then
        warn "节点 '${node_id}' 的 when 条件引用了不存在的节点 '${cond_node}'，将忽略此条件"
        _NODE_WHEN[$node_id]=""
        issue_found=true
      fi
      # Check if cond_status is valid
      if [[ "$cond_status" != "passed" && "$cond_status" != "failed" && "$cond_status" != "completed" ]]; then
        warn "节点 '${node_id}' 的 when 条件状态 '${cond_status}' 非标准值 (passed/failed/completed)"
        issue_found=true
      fi
    fi
  done

  if $issue_found; then
    echo "  (图包含验证警告，但仍将继续执行)"
  fi
}

# ── Topological Sort ──────────────────────────────────────────────

_compute_topological_order() {
  _TOPOLOGICAL_ORDER=()
  local -A in_degree
  local -A adj

  for node_id in "${_NODE_ORDER[@]}"; do
    in_degree[$node_id]=0
    adj[$node_id]=""
  done

  for node_id in "${_NODE_ORDER[@]}"; do
    local needs_str="${_NODE_NEEDS[$node_id]}"
    if [[ -n "$needs_str" ]]; then
      local old_ifs="$IFS"; IFS=','; set -- $needs_str; IFS="$old_ifs"
      for dep do
        [[ -z "$dep" ]] && continue
        dep="${dep## }"; dep="${dep%% }"
        in_degree[$node_id]=$(( ${in_degree[$node_id]} + 1 ))
        adj[$dep]="${adj[$dep]} $node_id"
      done
    fi
  done

  local -a queue=()
  for node_id in "${_NODE_ORDER[@]}"; do
    [[ ${in_degree[$node_id]} -eq 0 ]] && queue+=("$node_id")
  done

  while [[ ${#queue[@]} -gt 0 ]]; do
    local n="${queue[0]}"
    queue=("${queue[@]:1}")
    _TOPOLOGICAL_ORDER+=("$n")
    local neighbors="${adj[$n]}"
    if [[ -n "$neighbors" ]]; then
      local old_ifs="$IFS"; IFS=' '; set -- $neighbors; IFS="$old_ifs"
      for neighbor do
        [[ -z "$neighbor" ]] && continue
        in_degree[$neighbor]=$(( ${in_degree[$neighbor]} - 1 ))
        [[ ${in_degree[$neighbor]} -eq 0 ]] && queue+=("$neighbor")
      done
    fi
  done
}

# ── State Management ──────────────────────────────────────────────

# Validate state file JSON integrity
_validate_state_file() {
  [[ -f "$_STATE_FILE" ]] || return 1
  python3 -c "
import json
try:
    with open('$_STATE_FILE') as f:
        d = json.load(f)
    # Validate required fields
    assert 'name' in d, 'missing name'
    assert 'nodes' in d, 'missing nodes'
    for nid, ndata in d['nodes'].items():
        assert 'status' in ndata, f'missing status for {nid}'
    print('VALID')
except Exception as e:
    print('CORRUPT: ' + str(e))
    sys.exit(1)
" 2>/dev/null | grep -q 'VALID'
}

# Backup state file
_backup_state_file() {
  [[ -f "$_STATE_FILE" ]] || return 0
  cp "$_STATE_FILE" "${_STATE_FILE}.bak" 2>/dev/null || true
}

init_state() {
  local graph_name="${1:-$GRAPH_NAME}"
  # Derive safe filename from the graph YAML file (always filesystem-safe)
  local state_basename
  if [[ -n "$GRAPH_FILE" ]]; then
    state_basename=$(basename "$GRAPH_FILE" .yml)
    state_basename=$(basename "$state_basename" .yaml)
  else
    state_basename=$(echo "$graph_name" | sed 's/[^a-zA-Z0-9_-]/-/g; s/--*/-/g; s/^-//; s/-$//')
  fi
  _STATE_FILE="/tmp/guild-graph-${state_basename}-state.json"

  local nodes_json=""
  local first=true
  for node_id in "${_NODE_ORDER[@]}"; do
    $first || nodes_json+=","
    first=false
    nodes_json+="\"${node_id}\":{\"status\":\"pending\",\"started_at\":null,\"completed_at\":null,\"output\":null,\"captured_output\":null}"
  done

  _lock_state
  cat > "$_STATE_FILE" << JSONEOF
{
  "name": "${GRAPH_NAME}",
  "graph_file": "$(readlink -f "${GRAPH_FILE:-unknown}")",
  "started_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "completed_at": null,
  "current_iteration": 0,
  "max_retries": 3,
  "nodes": {${nodes_json}}
}
JSONEOF
  _backup_state_file
  _unlock_state
  ok "图状态已初始化: $_STATE_FILE"
}

_get_state() {
  local node="$1" field="$2"
  _lock_state
  local result
  result=$(python3 -c "
import json
with open('$_STATE_FILE') as f:
    d = json.load(f)
if '$node' == '__graph__':
    print(d.get('$field', ''))
else:
    print(d['nodes'].get('$node', {}).get('$field', ''))
" 2>/dev/null || echo "")
  _unlock_state
  echo "$result"
}

_set_state() {
  local node="$1" field="$2" value="$3"
  _lock_state
  local scr; scr=$(mktemp /tmp/guild-setstate-XXXXXX.py)
  cat > "$scr" << 'PYEOF'
import json, sys
node, field, value, state_file = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
with open(state_file) as f:
    d = json.load(f)
target = d if node == '__graph__' else d['nodes'].setdefault(node, {})
try:
    target[field] = json.loads(value)
except (json.JSONDecodeError, TypeError):
    target[field] = value
with open(state_file, 'w') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
PYEOF
  python3 "$scr" "$node" "$field" "$value" "$_STATE_FILE" 2>/dev/null || true
  rm -f "$scr" 2>/dev/null || true
  _unlock_state
}

_set_node_status() {
  local node="$1" status="$2" output="${3:-}"
  local now; now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  _lock_state
  python3 -c "
import json
with open('$_STATE_FILE') as f:
    d = json.load(f)
d['nodes']['$node']['status'] = '$status'
if '$status' == 'running':
    d['nodes']['$node']['started_at'] = '$now'
elif '$status' in ('completed', 'failed', 'timeout', 'exhausted'):
    d['nodes']['$node']['completed_at'] = '$now'
    d['nodes']['$node']['output'] = '$output'
with open('$_STATE_FILE', 'w') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
" 2>/dev/null || true
  _backup_state_file
  _unlock_state
  _EDGES_PROCESSED[$node]=""
}

_get_status() {
  _lock_state
  local result
  result=$(python3 -c "
import json
with open('$_STATE_FILE') as f:
    d = json.load(f)
print(d['nodes'].get('$1', {}).get('status', 'unknown'))
" 2>/dev/null || echo "unknown")
  _unlock_state
  echo "$result"
}

_save_state() {
  _backup_state_file
}

# ── Node Discovery ────────────────────────────────────────────────

find_ready_nodes() {
  local ready=""
  for node_id in "${_NODE_ORDER[@]}"; do
    local status; status=$(_get_status "$node_id")
    [[ "$status" != "pending" && "$status" != "interrupted" ]] && continue

    local when_str="${_NODE_WHEN[$node_id]}"
    if [[ -n "$when_str" ]]; then
      local cond_node="${when_str%%:*}"
      local cond_status="${when_str#*:}"
      local cond_actual; cond_actual=$(_get_status "$cond_node")
      # Map "passed" to "completed" for semantic compatibility
      if [[ "$cond_status" == "passed" ]]; then
        [[ "$cond_actual" != "completed" && "$cond_actual" != "passed" ]] && continue
      elif [[ "$cond_status" == "failed" ]]; then
        [[ "$cond_actual" != "failed" ]] && continue
      else
        [[ "$cond_actual" != "$cond_status" ]] && continue
      fi
    fi

    local needs_str="${_NODE_NEEDS[$node_id]}"
    local all_met=true
    local node_when="${_NODE_WHEN[$node_id]}"
    if [[ -n "$needs_str" ]]; then
      local old_ifs="$IFS"; IFS=','; set -- $needs_str; IFS="$old_ifs"
      for dep do
        [[ -z "$dep" ]] && continue
        dep="${dep## }"; dep="${dep%% }"
        local dep_status; dep_status=$(_get_status "$dep")
        if [[ "$dep_status" == "completed" ]]; then
          :
        elif [[ "$dep_status" == "failed" && -n "$node_when" ]]; then
          :
        else
          all_met=false; break
        fi
      done
    fi

    $all_met && ready="${ready} ${node_id}"
  done
  echo "$ready" | xargs
}

all_done() {
  for node_id in "${_NODE_ORDER[@]}"; do
    local s; s=$(_get_status "$node_id")
    [[ "$s" == "completed" || "$s" == "passed" ]] || return 1
  done
  return 0
}

# Pending node analysis (bypassed vs blocked distinction)
_PENDING_BYPASSED=""
_PENDING_BLOCKED=""

_analyze_pending_nodes() {
  _PENDING_BYPASSED=""
  _PENDING_BLOCKED=""
  for node_id in "${_NODE_ORDER[@]}"; do
    local s; s=$(_get_status "$node_id")
    [[ "$s" != "pending" ]] && continue

    local when_str="${_NODE_WHEN[$node_id]}"
    if [[ -n "$when_str" ]]; then
      local cond_node="${when_str%%:*}"
      local cond_status="${when_str#*:}"
      local cond_actual; cond_actual=$(_get_status "$cond_node")
      if [[ "$cond_actual" == "completed" || "$cond_actual" == "failed" || "$cond_actual" == "passed" ]]; then
        local cond_ok=false
        if [[ "$cond_status" == "passed" ]]; then
          [[ "$cond_actual" == "completed" || "$cond_actual" == "passed" ]] && cond_ok=true
        elif [[ "$cond_status" == "failed" ]]; then
          [[ "$cond_actual" == "failed" ]] && cond_ok=true
        else
          [[ "$cond_actual" == "$cond_status" ]] && cond_ok=true
        fi
        if ! $cond_ok; then
          _PENDING_BYPASSED="${_PENDING_BYPASSED} ${node_id}"
          continue
        fi
      fi
      continue
    fi

    local needs_str="${_NODE_NEEDS[$node_id]}"
    if [[ -n "$needs_str" ]]; then
      local has_dead_dep=false
      local all_met=true
      local old_ifs="$IFS"; IFS=','; set -- $needs_str; IFS="$old_ifs"
      for dep do
        [[ -z "$dep" ]] && continue
        dep="${dep## }"; dep="${dep%% }"
        local ds; ds=$(_get_status "$dep")
        if [[ "$ds" != "completed" && "$ds" != "passed" ]]; then
          all_met=false
          if [[ "$ds" == "failed" ]] || [[ "$_PENDING_BYPASSED" == *"$dep"* ]]; then
            has_dead_dep=true
          fi
        fi
      done
      if $has_dead_dep; then
        _PENDING_BLOCKED="${_PENDING_BLOCKED} ${node_id}"
      elif $all_met; then
        _PENDING_BLOCKED="${_PENDING_BLOCKED} ${node_id}"
      fi
    else
      _PENDING_BLOCKED="${_PENDING_BLOCKED} ${node_id}"
    fi
  done
}

is_blocked() {
  _analyze_pending_nodes
  [[ -n "$_PENDING_BLOCKED" ]] && return 0
  [[ -n "$_PENDING_BYPASSED" ]] && return 0
  return 1
}

# ── Node Execution ────────────────────────────────────────────────

execute_node() {
  local node_id="$1" work_dir="$2" dry_run="$3" auto_yes="${4:-false}"
  local agent="${_NODE_AGENT[$node_id]}"
  local action="${_NODE_ACTION[$node_id]:-execute}"
  local delivers="${_NODE_DELIVERS[$node_id]}"
  local timeout_sec="${_NODE_TIMEOUT[$node_id]:-$DEFAULT_NODE_TIMEOUT}"

  _set_node_status "$node_id" "running"

  echo ""
  echo "  +-----------------------------------------------"
  echo "  |  节点: ${node_id}"
  echo "  |  Agent: ${agent}"
  echo "  |  动作: ${action}"
  [[ -n "$delivers" ]] && echo "  |  产出: ${delivers}"
  echo "  |  超时: ${timeout_sec}s"
  echo "  +-----------------------------------------------"
  echo ""

  if $dry_run; then
    echo "  [DRY-RUN] 跳过执行"
    _set_node_status "$node_id" "completed"
    _LAST_COMPLETED="$node_id"
    return 0
  fi

  # Create output log for capturing stdout
  local output_log; output_log=$(mktemp /tmp/guild-node-output-XXXXXX)

  local exec_rc=0
  local timed_out=false

  # Fork execution into background for timeout monitoring
  (
    case "$action" in
      approve)
        echo "  等待审批..."
        echo ""
        echo "  ═══════════════════════════════════"
        echo "   审批请求: ${node_id}"
        echo "   Agent: ${agent}"
        [[ -n "$delivers" ]] && echo "   产出: ${delivers}"
        echo "  ═══════════════════════════════════"
        echo ""
        if [[ "$auto_yes" == "true" ]]; then
          echo "  (自动审批 - --yes 模式)"
          echo "  + 自动批准"
          exit 0
        fi
        echo -n "  是否批准? (y/n): "
        local input
        read -r input
        case "$input" in
          y|Y|yes|YES|Yes)
            echo "  + 已批准"
            exit 0
            ;;
          *)
            echo "  x 未批准"
            exit 1
            ;;
        esac
        ;;

      verify)
        echo "  运行验证..."
        local guild_cmd; guild_cmd=$(_find_guild_cmd)
        local verify_ok=true
        local checked_count=0
        local fail_count=0
        local found_files
        found_files=$(find "$work_dir" -type f 2>/dev/null)
        if [[ -z "$found_files" ]]; then
          echo "    注意: 工作目录中没有文件"
          echo "  + 跳过（无文件需验证）"
          exit 0
        else
          while IFS= read -r filepath; do
            [[ -z "$filepath" ]] && continue
            local ftype; ftype=$(_detect_file_type "$filepath")
            if [[ -z "$ftype" ]]; then
              echo "    跳过(未知类型): ${filepath##$work_dir/}"
              continue
            fi
            checked_count=$((checked_count + 1))
            local relpath="${filepath##$work_dir/}"
            echo "    验证: ${relpath} (类型: ${ftype})"

            local file_ok=false
            if [[ -n "$guild_cmd" ]]; then
              if $guild_cmd verify --type "$ftype" --file "$filepath" 2>/dev/null; then
                file_ok=true
              fi
            else
              case "$ftype" in
                html|js|ts)
                  if head -c 1000 "$filepath" | grep -qiE '(console\.error|\.crash\(|异常)' 2>/dev/null; then
                    file_ok=false
                  else
                    file_ok=true
                  fi
                  ;;
                sh)
                  bash -n "$filepath" 2>/dev/null && file_ok=true || file_ok=false
                  ;;
                json)
                  python3 -c "import json; json.load(open('$filepath'))" 2>/dev/null && file_ok=true || file_ok=false
                  ;;
                *)
                  [[ -s "$filepath" ]] && file_ok=true || file_ok=false
                  ;;
              esac
            fi

            if $file_ok; then
              echo "    [OK] 通过: ${relpath}"
            else
              echo "    [ERR] 失败: ${relpath}"
              verify_ok=false
              fail_count=$((fail_count + 1))
            fi
          done < <(printf '%s\n' "$found_files")

          echo ""
          if [[ $checked_count -eq 0 ]]; then
            echo "  + 跳过（所有文件类型均不支持验证）"
            exit 0
          elif $verify_ok; then
            echo "  + 验证通过 (${checked_count}文件, 0失败)"
            exit 0
          else
            echo "  x 验证未通过 (${checked_count}文件, ${fail_count}失败)"
            exit 1
          fi
        fi
        ;;

      deliver)
        echo "  交付模式:"
        echo "    请在 ${work_dir} 中准备好以下交付物:"
        if [[ -n "$delivers" ]]; then
          local old_ifs="$IFS"; IFS=','; set -- $delivers; IFS="$old_ifs"
          for item do
            [[ -z "$item" ]] && continue
            item="${item## }"; item="${item%% }"
            echo "    - ${item}"
          done
        else
          echo "    (无指定交付物)"
        fi
        echo ""
        [[ "$auto_yes" != "true" && -n "$delivers" ]] && { echo "  准备完毕后按 Enter 继续..."; read -r; } || echo "  (自动模式)"

        if [[ -n "$delivers" ]]; then
          local all_found=true
          local old_ifs="$IFS"; IFS=','; set -- $delivers; IFS="$old_ifs"
          for item do
            [[ -z "$item" ]] && continue
            item="${item## }"; item="${item%% }"
            local found; found=$(find "$work_dir" -type f -name "*${item}*" 2>/dev/null | head -1)
            [[ -z "$found" ]] && all_found=false
          done

          if $all_found; then
            echo "  + 交付完成"
            exit 0
          else
            echo "  警告: 部分交付物未找到"
            echo "  + 继续（标记为已完成）"
            exit 0
          fi
        else
          echo "  + 交付完成（无指定交付物）"
          exit 0
        fi
        ;;

      *)
        echo "  执行 ${node_id}..."
        echo "  + 完成"
        exit 0
        ;;
    esac
  ) > "$output_log" 2>&1 &
  local exec_pid=$!

  # Wait for completion with timeout monitoring
  local waited=0
  while kill -0 $exec_pid 2>/dev/null; do
    if [[ $waited -ge $timeout_sec ]]; then
      kill $exec_pid 2>/dev/null
      echo "" >> "$output_log"
      echo "  [TIMEOUT] 节点执行超过 ${timeout_sec}s" >> "$output_log"
      timed_out=true
      break
    fi
    sleep 1
    waited=$((waited + 1))
  done

  # Wait to avoid zombie
  wait $exec_pid 2>/dev/null
  exec_rc=$?

  # Show output to user
  cat "$output_log"

  # Capture last 3 meaningful lines
  local captured_output
  captured_output=$(tail -3 "$output_log" 2>/dev/null | grep -v '^\s*$' || echo "")
  rm -f "$output_log"

  if $timed_out; then
    _set_node_status "$node_id" "timeout" "超时 (${timeout_sec}s)"
    echo "  x [超时] 节点执行超过 ${timeout_sec}s"
  elif [[ $exec_rc -eq 0 ]]; then
    # Read the last line for a meaningful status message
    local last_line; last_line=$(echo "$captured_output" | tail -1)
    if [[ -z "$last_line" || "$last_line" == "None" ]]; then
      last_line="执行完成"
    fi
    # Strip leading "  + " or "  x " for clean output
    last_line="${last_line#  + }"
    last_line="${last_line#  x }"
    _set_node_status "$node_id" "completed" "$last_line"
    # Create handoff record for graph engine node completion
    if ! $dry_run; then
      _create_handoff_for_node "$node_id" "$work_dir" "$agent"
    fi
  else
    local last_line; last_line=$(echo "$captured_output" | tail -1)
    if [[ -z "$last_line" || "$last_line" == "None" ]]; then
      last_line="执行失败"
    fi
    _set_node_status "$node_id" "failed" "$last_line"
  fi

  # Store captured output for report
  _set_state "$node_id" "captured_output" "$captured_output"

  _LAST_COMPLETED="$node_id"
}

# ── Handoff Integration ──────────────────────────────────────────────

# _create_handoff_for_node — auto-create handoff record when graph node completes
_create_handoff_for_node() {
  local node_id="$1" work_dir="$2" agent_name="$3"
  local repo_root
  repo_root="$(cd "$_GRApH_ENGINE_DIR/.." && pwd 2>/dev/null)"
  local handoffs_dir="$repo_root/handoffs"
  mkdir -p "$handoffs_dir"

  # Auto-increment handoff ID
  local max_id=0
  for f in "$handoffs_dir"/*.json; do
    [[ -f "$f" ]] || continue
    local id_val
    id_val=$(python3 -c "import json; print(json.load(open('$f')).get('id',0))" 2>/dev/null || echo 0)
    (( id_val > max_id )) && max_id=$id_val
  done
  local new_id=$((max_id + 1))

  local date_str; date_str=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local date_file; date_file=$(date -u +"%Y-%m-%d")
  local graph_slug="${GRAPH_NAME:-graph}"
  local safe_slug; safe_slug=$(echo "$graph_slug" | sed 's/[^a-zA-Z0-9_-]/-/g')
  local filename="${date_file}-graph-${safe_slug}-to-${agent_name}.json"

  local agent_slug="${agent_name}"
  # Try to resolve agent slug from config
  local config="$repo_root/guild.config.json"
  if [[ -f "$config" ]]; then
    local resolved
    resolved=$(python3 -c "
import json
with open('$config') as f:
    data = json.load(f)
for a in data.get('agents', []):
    if a.get('name','').lower().replace(' ','-') == '$agent_name'.lower().replace(' ','-') or a.get('slug','') == '$agent_name':
        print(a['slug'])
        break
" 2>/dev/null)
    [[ -n "$resolved" ]] && agent_slug="$resolved"
  fi

  cat > "$handoffs_dir/$filename" << HANEOF
{
  "id": $new_id,
  "from": "graph:${graph_slug}",
  "to": "${agent_slug}",
  "timestamp": "${date_str}",
  "message": "Graph node completed: ${node_id}",
  "path": "${work_dir}",
  "artifacts": [
    {"name": "graph_node_output", "file": "${work_dir}", "status": "provided"}
  ],
  "checklist": {
    "required_total": 1,
    "required_provided": 1,
    "required_missing": 0
  },
  "status": "ready",
  "accepted_by": null,
  "source": "graph-engine"
}
HANEOF
  echo "  | Handoff #${new_id} created: graph:${graph_slug} -> ${agent_slug} (node: ${node_id})"
}

_detect_file_type() {
  local filepath="$1"
  local ext="${filepath##*.}"
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

_find_guild_cmd() {
  if command -v guild &>/dev/null; then
    echo "guild"
    return 0
  fi
  return 1
}

# ── Edge Processing ───────────────────────────────────────────────

process_edges() {
  local completed_node="$1"
  local completed_status; completed_status=$(_get_status "$completed_node")
  [[ -z "$completed_node" ]] && return

  echo ""
  echo "  -- 处理 ${completed_node} 的出边 --"

  local edge_count=0
  for (( i = 0; i < ${#_EDGE_FROM[@]}; i++ )); do
    [[ "${_EDGE_FROM[$i]}" != "$completed_node" ]] && continue

    local to="${_EDGE_TO[$i]}"
    local when="${_EDGE_WHEN[$i]}"
    local label="${_EDGE_LABEL[$i]}"

    local should_trigger=true
    if [[ -n "$when" ]]; then
      local condition_met=false
      case "$when" in
        *failed*) [[ "$completed_status" == "failed" || "$completed_status" == "timeout" || "$completed_status" == "exhausted" ]] && condition_met=true ;;
        *passed*|*completed*) [[ "$completed_status" == "completed" ]] && condition_met=true ;;
        *) [[ "$when" == "$completed_status" ]] && condition_met=true ;;
      esac
      should_trigger=$condition_met
    fi

    if ! $should_trigger; then
      echo "  | 跳过 $to（条件不满足: ${when}）"
      continue
    fi

    edge_count=$((edge_count + 1))
    local target_status; target_status=$(_get_status "$to")
    local is_back_edge=false
    [[ "$target_status" == "completed" || "$target_status" == "failed" || "$target_status" == "timeout" || "$target_status" == "exhausted" ]] && is_back_edge=true

    if $is_back_edge; then
      local retry_count; retry_count=${_NODE_RETRY_COUNT[$to]:-0}
      if [[ $retry_count -ge $MAX_RETRIES ]]; then
        _set_state "$to" "status" "exhausted"
        echo "  | 回路 $to 已达最大重试($MAX_RETRIES)，标记为耗尽 — 需人工介入"
        continue
      fi
      _NODE_RETRY_COUNT[$to]=$((retry_count + 1))
      echo "  | 回路 $to$( [[ -n "$label" ]] && echo " (${label})" ) [${_NODE_RETRY_COUNT[$to]}/${MAX_RETRIES}]"
      _set_state "$to" "status" "pending"
      _set_state "$to" "output" null
      _set_state "$to" "started_at" null
      _set_state "$to" "completed_at" null
      _EDGES_PROCESSED[$to]=""
    else
      echo "  | 流转 $to$( [[ -n "$label" ]] && echo " (${label})" )"
      [[ "$target_status" != "pending" ]] && _set_state "$to" "status" "pending"
    fi
  done

  [[ $edge_count -eq 0 ]] && echo "  | (无出边)"
}

# ── Report ────────────────────────────────────────────────────────

print_report() {
  local graph_file="$1" work_dir="$2" duration="$3"

  echo ""
  echo "============================="
  echo "  图执行报告"
  echo "============================="
  echo ""
  echo "  图名称:     $GRAPH_NAME"
  echo "  图文件:     $(readlink -f "$graph_file" 2>/dev/null || echo "$graph_file")"
  [[ -n "$GRAPH_DESC" ]] && echo "  描述:       $GRAPH_DESC"
  echo "  工作目录:   $(readlink -f "$work_dir" 2>/dev/null || echo "$work_dir")"
  echo "  执行时间:   ${duration}s"
  echo ""

  local total=${#_NODE_ORDER[@]}
  local completed=0 failed=0 running=0 pending=0 timedout=0 exhausted=0
  for node_id in "${_NODE_ORDER[@]}"; do
    local s; s=$(_get_status "$node_id")
    case "$s" in
      completed) completed=$((completed + 1));;
      failed) failed=$((failed + 1));;
      timeout) timedout=$((timedout + 1));;
      exhausted) exhausted=$((exhausted + 1));;
      running) running=$((running + 1));;
      pending) pending=$((pending + 1));;
    esac
  done

  echo "  节点统计: 总计=${total} 完成=${completed} 失败=${failed} 超时=${timedout} 耗尽=${exhausted} 待处理=${pending} 运行中=${running}"
  echo ""
  echo "  节点明细:"
  _analyze_pending_nodes
  for node_id in "${_NODE_ORDER[@]}"; do
    local s; s=$(_get_status "$node_id")
    local icon
    case "$s" in
      completed) icon="[OK]";;
      failed) icon="[FAIL]";;
      timeout) icon="[TIME]";;
      exhausted) icon="[EXH]";;
      running) icon="[RUN]";;
      pending) icon="[WAIT]";;
      interrupted) icon="[INT]";;
      *) icon="[?]";;
    esac
    local agent="${_NODE_AGENT[$node_id]}"
    local output; output=$(_get_state "$node_id" "output")
    local captured; captured=$(_get_state "$node_id" "captured_output")

    case "$s" in
      timeout)
        echo "  ${icon} ${node_id} (${agent}) - 超时 (${_NODE_TIMEOUT[$node_id]:-$DEFAULT_NODE_TIMEOUT}s)"
        ;;
      exhausted)
        echo "  ${icon} ${node_id} (${agent}) - 已达最大重试次数"
        ;;
      *)
        echo "  ${icon} ${node_id} (${agent}) - ${s}"
        ;;
    esac
    [[ -n "$output" && "$output" != "None" ]] && echo "      结果: ${output}"
    if [[ -n "$captured" && "$captured" != "None" ]]; then
      echo "      输出摘要:"
      while IFS= read -r c_line; do
        echo "        ${c_line}"
      done <<< "$captured"
    fi
    if [[ "$s" == "pending" ]] && [[ " ${_PENDING_BYPASSED} " == *" ${node_id} "* ]]; then
      local when_str="${_NODE_WHEN[$node_id]}"
      if [[ -n "$when_str" ]]; then
        local cond_node="${when_str%%:*}"
        local cond_status="${when_str#*:}"
        local cond_actual; cond_actual=$(_get_status "$cond_node")
        echo "      旁路: 条件 ${cond_node}.status=${cond_status} 不满足 (实际: ${cond_actual})"
      fi
    fi
  done

  echo ""
  local bypassed_count; bypassed_count=$(echo "$_PENDING_BYPASSED" | wc -w)
  local blocked_count; blocked_count=$(echo "$_PENDING_BLOCKED" | wc -w)
  if [[ $failed -gt 0 ]]; then
    err "图执行存在失败节点"
  elif [[ $timedout -gt 0 ]]; then
    err "图执行存在超时节点"
  elif [[ $exhausted -gt 0 ]]; then
    err "图执行存在耗尽节点"
  elif [[ $blocked_count -gt 0 ]]; then
    warn "图执行未完全完成（${blocked_count} 个节点阻塞）"
  elif [[ $bypassed_count -gt 0 ]]; then
    ok "图执行完成（${bypassed_count} 个节点已旁路）"
  else
    ok "图执行全部完成"
  fi
}

# ── Graph Visualization ───────────────────────────────────────────

print_graph_info() {
  echo "=== Graph: ${GRAPH_NAME} ==="
  echo ""
  echo "Nodes:"
  for node_id in "${_NODE_ORDER[@]}"; do
    echo "  ${node_id}:"
    echo "    agent: ${_NODE_AGENT[$node_id]}"
    echo "    action: ${_NODE_ACTION[$node_id]:-execute}"
    echo "    timeout: ${_NODE_TIMEOUT[$node_id]:-$DEFAULT_NODE_TIMEOUT}s"
    [[ -n "${_NODE_NEEDS[$node_id]}" ]] && echo "    needs: [${_NODE_NEEDS[$node_id]}]"
    [[ -n "${_NODE_DELIVERS[$node_id]}" ]] && echo "    delivers: [${_NODE_DELIVERS[$node_id]}]"
    [[ -n "${_NODE_WHEN[$node_id]}" ]] && echo "    when: {${_NODE_WHEN[$node_id]}}"
  done

  echo ""
  echo "Edges:"
  if [[ ${#_EDGE_FROM[@]} -eq 0 ]]; then
    echo "  (无边)"
  else
    for (( i = 0; i < ${#_EDGE_FROM[@]}; i++ )); do
      echo "  ${_EDGE_FROM[$i]} -> ${_EDGE_TO[$i]}$( [[ -n "${_EDGE_WHEN[$i]}" ]] && echo " [cond: ${_EDGE_WHEN[$i]}]" )$( [[ -n "${_EDGE_LABEL[$i]}" ]] && echo " (${_EDGE_LABEL[$i]})" )"
    done
  fi

  echo ""
  echo "Topological order: ${_TOPOLOGICAL_ORDER[*]}"
}

# ── Dry-Run Simulation ────────────────────────────────────────────

_simulate_graph() {
  local work_dir="$1"
  local max_iterations=50
  local MAX_RETRIES=3

  echo ""
  echo "================================================================="
  echo "  [DRY-RUN] 完整执行模拟"
  echo "================================================================="
  echo ""
  echo "  图: ${GRAPH_NAME}"
  echo "  节点数: ${#_NODE_ORDER[@]}"
  echo "  边数: ${#_EDGE_FROM[@]}"
  echo "  最大迭代: ${max_iterations}"
  echo ""

  # Simulate using virtual state tracking (in-memory)
  declare -A _SIM_STATUS
  for node_id in "${_NODE_ORDER[@]}"; do
    _SIM_STATUS[$node_id]="pending"
  done
  declare -A _SIM_RETRIES
  declare -A _SIM_EDGES_PROCESSED

  local iteration=0
  while [[ $iteration -lt $max_iterations ]]; do
    iteration=$((iteration + 1))
    echo "  ── iteration ${iteration} ──"

    # Find ready nodes
    local ready=""
    for node_id in "${_NODE_ORDER[@]}"; do
      local sim_status="${_SIM_STATUS[$node_id]}"
      [[ "$sim_status" != "pending" ]] && continue

      local when_str="${_NODE_WHEN[$node_id]}"
      if [[ -n "$when_str" ]]; then
        local cond_node="${when_str%%:*}"
        local cond_status="${when_str#*:}"
        local sim_cond="${_SIM_STATUS[$cond_node]:-pending}"
        if [[ "$cond_status" == "passed" ]]; then
          [[ "$sim_cond" != "completed" ]] && continue
        elif [[ "$cond_status" == "failed" ]]; then
          [[ "$sim_cond" != "failed" && "$sim_cond" != "timeout" ]] && continue
        else
          [[ "$sim_cond" != "$cond_status" ]] && continue
        fi
      fi

      local needs_str="${_NODE_NEEDS[$node_id]}"
      local all_met=true
      if [[ -n "$needs_str" ]]; then
        local old_ifs="$IFS"; IFS=','; set -- $needs_str; IFS="$old_ifs"
        for dep do
          [[ -z "$dep" ]] && continue
          dep="${dep## }"; dep="${dep%% }"
          local ds="${_SIM_STATUS[$dep]:-pending}"
          [[ "$ds" == "completed" ]] && continue
          all_met=false; break
        done
      fi
      $all_met && ready="${ready} ${node_id}"
    done

    if [[ -z "$ready" ]]; then
      # Check if all completed
      local all_done=true
      for node_id in "${_NODE_ORDER[@]}"; do
        [[ "${_SIM_STATUS[$node_id]}" != "completed" ]] && { all_done=false; break; }
      done
      $all_done && { echo "  (全部完成)"; break; }

      # Check bypassed/blocked
      local bypassed="" blocked=""
      for node_id in "${_NODE_ORDER[@]}"; do
        [[ "${_SIM_STATUS[$node_id]}" != "pending" ]] && continue
        local when_str="${_NODE_WHEN[$node_id]}"
        if [[ -n "$when_str" ]]; then
          local cond_node="${when_str%%:*}"
          local cond_status="${when_str#*:}"
          local sim_cond="${_SIM_STATUS[$cond_node]:-pending}"
          if [[ "$sim_cond" == "completed" || "$sim_cond" == "failed" ]]; then
            local cond_ok=false
            [[ "$cond_status" == "passed" && "$sim_cond" == "completed" ]] && cond_ok=true
            [[ "$cond_status" == "failed" && "$sim_cond" == "failed" ]] && cond_ok=true
            $cond_ok || bypassed="${bypassed} ${node_id}"
          fi
        fi
      done
      if [[ -n "$bypassed" ]]; then
        for b in $bypassed; do echo "  [BYP] ${b} - 条件不满足，已旁路"; done
        break
      fi
      echo "  (阻塞 - 无就绪节点)"
      break
    fi

    # Execute ready nodes (virtually)
    local simulated_executed=false
    local old_ifs="$IFS"; IFS=' '; set -- $ready; IFS="$old_ifs"
    for node_id do
      [[ -z "$node_id" ]] && continue
      simulated_executed=true
      local agent="${_NODE_AGENT[$node_id]}"
      local action="${_NODE_ACTION[$node_id]:-execute}"
      local delivers="${_NODE_DELIVERS[$node_id]}"
      local timeout="${_NODE_TIMEOUT[$node_id]:-$DEFAULT_NODE_TIMEOUT}"

      echo "  > [SIM] ${node_id} (${agent}, ${action}, timeout=${timeout}s)"

      # Mark as completed in simulation
      _SIM_STATUS[$node_id]="completed"

      # Process outgoing edges virtually
      for (( i = 0; i < ${#_EDGE_FROM[@]}; i++ )); do
        [[ "${_EDGE_FROM[$i]}" != "$node_id" ]] && continue
        local to="${_EDGE_TO[$i]}"
        local edge_when="${_EDGE_WHEN[$i]}"
        local edge_label="${_EDGE_LABEL[$i]}"

        # Check edge condition
        local trigger=true
        if [[ -n "$edge_when" ]]; then
          local cond_met=false
          case "$edge_when" in
            *failed*) [[ "${_SIM_STATUS[$node_id]}" == "failed" ]] && cond_met=true ;;
            *passed*|*completed*) [[ "${_SIM_STATUS[$node_id]}" == "completed" ]] && cond_met=true ;;
          esac
          trigger=$cond_met
        fi

        if $trigger; then
          local target_sim="${_SIM_STATUS[$to]}"
          if [[ "$target_sim" == "completed" || "$target_sim" == "failed" ]]; then
            # Back edge
            local retries="${_SIM_RETRIES[$to]:-0}"
            if [[ $retries -ge $MAX_RETRIES ]]; then
              echo "    └─ 边: -> ${to}${edge_label:+ ($edge_label)} [EXHAUSTED]"
              _SIM_STATUS[$to]="exhausted"
            else
              _SIM_RETRIES[$to]=$((retries + 1))
              echo "    └─ 回路: -> ${to}${edge_label:+ ($edge_label)} [${_SIM_RETRIES[$to]}/${MAX_RETRIES}]"
              _SIM_STATUS[$to]="pending"
            fi
          else
            echo "    └─ 边: -> ${to}${edge_label:+ ($edge_label)}"
            _SIM_STATUS[$to]="pending"
          fi
        else
          echo "    └─ 边跳过: -> ${to} (条件 ${edge_when} 不满足)"
        fi
      done
    done

    if ! $simulated_executed; then
      echo "  (无节点执行)"
      break
    fi
    echo ""
  done

  # Final summary
  echo "================================================================="
  echo "  [DRY-RUN] 模拟完成"
  echo "================================================================="
  echo ""
  local sim_completed=0 sim_failed=0 sim_pending=0 sim_exhausted=0
  for node_id in "${_NODE_ORDER[@]}"; do
    case "${_SIM_STATUS[$node_id]}" in
      completed) sim_completed=$((sim_completed + 1));;
      failed) sim_failed=$((sim_failed + 1));;
      exhausted) sim_exhausted=$((sim_exhausted + 1));;
      pending) sim_pending=$((sim_pending + 1));;
    esac
  done
  echo "  节点: 完成=${sim_completed} 失败=${sim_failed} 耗尽=${sim_exhausted} 待处理=${sim_pending}"
  echo "  迭代次数: ${iteration}"

  # Check for loops
  if [[ $iteration -ge $max_iterations ]]; then
    warn "  [DRY-RUN] 模拟达到最大迭代次数 (${max_iterations}) — 可能存在无限循环"
  elif [[ $sim_pending -gt 0 ]]; then
    warn "  [DRY-RUN] 存在 ${sim_pending} 个节点未执行 — 可能因条件不满足阻塞"
  else
    ok "  [DRY-RUN] 模拟显示图执行会正常完成"
  fi
  echo ""
}

# ── Resume Graph ──────────────────────────────────────────────────

resume_graph() {
  local graph_name="$1" work_dir="$2" auto_yes="${3:-false}"

  local state_file="/tmp/guild-graph-${graph_name}-state.json"
  # Also check from graph file name
  local state_basename
  if [[ -n "$GRAPH_FILE" ]]; then
    state_basename=$(basename "$GRAPH_FILE" .yml)
    state_basename=$(basename "$state_basename" .yaml)
    local alt_state_file="/tmp/guild-graph-${state_basename}-state.json"
    [[ -f "$alt_state_file" ]] && state_file="$alt_state_file"
  fi
  # Also check sanitized graph name
  local safe_name
  safe_name=$(echo "$graph_name" | sed 's/[^a-zA-Z0-9_-]/-/g; s/--*/-/g; s/^-//; s/-$//')
  [[ -f "$state_file" ]] || state_file="/tmp/guild-graph-${safe_name}-state.json"
  [[ -f "$state_file" ]] || { err "没有可恢复的状态文件: $state_file"; return 1; }

  _STATE_FILE="$state_file"

  # Validate state file integrity
  if ! _validate_state_file; then
    err "状态文件已损坏: $state_file"
    if [[ -f "${state_file}.bak" ]]; then
      echo "  发现备份文件: ${state_file}.bak"
      echo -n "  是否从备份恢复? (y/n): "
      local input
      read -r input
      if [[ "$input" == "y" || "$input" == "Y" ]]; then
        cp "${state_file}.bak" "$state_file"
        echo "  已从备份恢复"
        if ! _validate_state_file; then
          err "备份文件也损坏了"
          echo "  请重新运行: guild graph run --graph ${graph_name} --path ${work_dir}"
          return 1
        fi
      else
        echo "  请重新运行: guild graph run --graph ${graph_name} --path ${work_dir}"
        return 1
      fi
    else
      echo "  无可用备份。请重新运行: guild graph run --graph ${graph_name} --path ${work_dir}"
      return 1
    fi
  fi

  # Read graph name from state
  local state_graph_name
  state_graph_name=$(python3 -c "
import json
with open('$_STATE_FILE') as f:
    d = json.load(f)
print(d.get('name', ''))
" 2>/dev/null)

  if [[ -n "$state_graph_name" && "$state_graph_name" != "$graph_name" ]]; then
    warn "状态文件中的图名称 '${state_graph_name}' 与请求的 '${graph_name}' 不匹配"
  fi

  # Mark running/interrupted nodes for re-execution
  local nodes_to_reset
  nodes_to_reset=$(python3 -c "
import json
with open('$_STATE_FILE') as f:
    d = json.load(f)
reset_nodes = []
for nid, ndata in d['nodes'].items():
    if ndata.get('status') in ('running', 'interrupted'):
        reset_nodes.append(nid)
print(' '.join(reset_nodes))
" 2>/dev/null)

  _lock_state
  python3 -c "
import json
with open('$_STATE_FILE') as f:
    d = json.load(f)
for nid in d['nodes']:
    if d['nodes'][nid].get('status') in ('running', 'interrupted'):
        d['nodes'][nid]['status'] = 'pending'
        d['nodes'][nid]['output'] = '中断 - 已重置为待执行'
        d['nodes'][nid]['started_at'] = None
        d['nodes'][nid]['completed_at'] = None
with open('$_STATE_FILE', 'w') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
" 2>/dev/null || true
  _backup_state_file
  _unlock_state

  if [[ -n "$nodes_to_reset" ]]; then
    echo "  已标记中断/运行中节点为待执行: ${nodes_to_reset}"
  fi

  # Find last completed node
  local last_completed
  last_completed=$(python3 -c "
import json
with open('$_STATE_FILE') as f:
    d = json.load(f)
last = None
for nid, ndata in d['nodes'].items():
    if ndata.get('status') == 'completed':
        last = nid
print(last or '')
" 2>/dev/null)

  echo ""
  ok "正在恢复图执行: ${graph_name}"
  echo "  状态文件: $_STATE_FILE"
  echo "  最后完成节点: ${last_completed:-无}"
  echo "  工作目录: $(readlink -f "$work_dir" 2>/dev/null || echo "$work_dir")"
  echo ""

  # Continue the main loop
  _graph_main_loop "$GRAPH_FILE" "$work_dir" "false" "$auto_yes"
  local rc=$?
  return $rc
}

# ── Main Execution Loop ──────────────────────────────────────────

_graph_main_loop() {
  local graph_file="$1" work_dir="$2" dry_run="$3" auto_yes="$4"

  local max_iterations=50
  MAX_RETRIES=3
  declare -A _NODE_RETRY_COUNT
  declare -A _NODE_RESULTS

  local start_time; start_time=$(date +%s)
  local iteration=0

  echo ""
  echo "============================="
  echo "  Graph Engine: ${GRAPH_NAME}"
  echo "============================="
  echo ""

  if $dry_run; then
    echo "  [DRY-RUN 模式 - 仅模拟，不实际执行]"
  fi
  echo ""

  print_graph_info
  echo ""

  # For dry-run: run full simulation instead of actual execution
  if $dry_run; then
    _simulate_graph "$work_dir"
    return 0
  fi

  while [[ $iteration -lt $max_iterations ]]; do
    iteration=$((iteration + 1))
    _set_state "__graph__" "current_iteration" "$iteration"

    local ready_nodes; ready_nodes=$(find_ready_nodes)

    if [[ -z "$ready_nodes" ]]; then
      all_done && { echo ""; echo "  图执行完成"; break; }
      _analyze_pending_nodes
      if [[ -n "$_PENDING_BLOCKED" ]]; then
        local blocked_count; blocked_count=$(echo "$_PENDING_BLOCKED" | wc -w)
        echo ""; echo "  图被阻塞（${blocked_count} 个节点无法继续）"
        break
      fi
      if [[ -n "$_PENDING_BYPASSED" ]]; then
        local bypassed_count; bypassed_count=$(echo "$_PENDING_BYPASSED" | wc -w)
        echo ""; echo "  图执行完成（${bypassed_count} 个节点已旁路）"
        break
      fi
      sleep 0.3
      ready_nodes=$(find_ready_nodes)
      [[ -n "$ready_nodes" ]] || continue
    fi

    echo ""
    echo "  -- iteration ${iteration}: ready nodes --"

    local -a pids=() pid_nodes=()
    local old_ifs="$IFS"; IFS=' '; set -- $ready_nodes; IFS="$old_ifs"
    for node_id do
      [[ -z "$node_id" ]] && continue
      echo "  > start: ${node_id}"
      if [[ ${#@} -gt 1 ]]; then
        # Parallel execution — each node writes result to a temp file
        local node_result; node_result=$(mktemp /tmp/guild-result-XXXXXX)
        (
          execute_node "$node_id" "$work_dir" "$dry_run" "$auto_yes"
          local ns; ns=$(_get_status "$node_id")
          local no; no=$(_get_state "$node_id" "output")
          echo "${node_id}|${ns}|${no}" > "$node_result"
        ) &
        pids+=($!); pid_nodes+=("$node_id")
        _NODE_RESULTS[$node_id]="$node_result"
    else
        execute_node "$node_id" "$work_dir" "$dry_run" "$auto_yes"
      fi
    done

    if [[ ${#pids[@]} -gt 0 ]]; then
      echo ""; echo "  waiting for ${#pids[@]} parallel nodes..."
      for (( i = 0; i < ${#pids[@]}; i++ )); do
        wait "${pids[$i]}" 2>/dev/null || err "  node ${pid_nodes[$i]} error"
        local node_id="${pid_nodes[$i]}"
        local result_file="${_NODE_RESULTS[$node_id]}"
        if [[ -f "$result_file" ]]; then
          local result_data; result_data=$(cat "$result_file" 2>/dev/null)
          local r_node r_status r_output
          r_node=$(echo "$result_data" | cut -d'|' -f1)
          r_status=$(echo "$result_data" | cut -d'|' -f2)
          r_output=$(echo "$result_data" | cut -d'|' -f3-)
          if [[ -n "$r_status" ]]; then
            _set_state "$r_node" "status" "$r_status"
            _set_state "$r_node" "output" "${r_output:-}"
            _EDGES_PROCESSED[$r_node]=""
          fi
          rm -f "$result_file"
        fi
      done
      echo "  all parallel nodes done"
    fi

    for node_id in "${_NODE_ORDER[@]}"; do
      local s; s=$(_get_status "$node_id")
      if [[ "$s" == "completed" || "$s" == "failed" || "$s" == "timeout" || "$s" == "exhausted" ]]; then
        if [[ -z "${_EDGES_PROCESSED[$node_id]:-}" ]]; then
          process_edges "$node_id"
          _EDGES_PROCESSED[$node_id]="1"
        fi
      fi
    done

    _save_state
  done

  [[ $iteration -ge $max_iterations ]] && warn "Max iterations reached"

  local end_time; end_time=$(date +%s)
  print_report "$graph_file" "$work_dir" $(( end_time - start_time ))
  _set_state "__graph__" "completed_at" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  local failed_count=0
  for node_id in "${_NODE_ORDER[@]}"; do
    local s; s=$(_get_status "$node_id")
    [[ "$s" == "failed" ]] && failed_count=$((failed_count + 1))
  done
  return $failed_count
}

# ── Main Entry Point ──────────────────────────────────────────────

run_graph() {
  local graph_file="$1" work_dir="$2" dry_run="${3:-false}" auto_yes="${4:-false}"

  [[ -f "$graph_file" ]] || { err "Graph file not found: $graph_file"; return 1; }
  [[ -d "$work_dir" ]] || mkdir -p "$work_dir"

  echo "  解析图定义: $(basename "$graph_file")..."
  parse_graph "$graph_file" || return 1

  # Initialize state only for actual execution (not dry-run)
  if ! $dry_run; then
    init_state "$GRAPH_NAME"
  fi

  _graph_main_loop "$graph_file" "$work_dir" "$dry_run" "$auto_yes"
  local rc=$?

  _cleanup_graph_lock

  return $rc
}
