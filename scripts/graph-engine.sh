#!/usr/bin/env bash
#
# graph-engine.sh — AgentGuild Graph Engine
# Executes agent workflows as directed graphs with loops and parallelism.
#
# Architecture:
#   Node (节点) = Agent 执行一个动作
#   Edge (边)   = 依赖关系 + 流转条件
#   State (状态) = 整个图的共享进度
#
# Usage (sourced by nexus.sh):
#   run_graph <graph_file> <work_dir> [dry_run] [auto_yes]
#
# State file: /tmp/guild-graph-<name>-state.json

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "ERROR: graph-engine.sh must be sourced, not executed directly." >&2
  echo "  source scripts/graph-engine.sh" >&2
  exit 1
fi

# Track engine directory for finding sibling scripts (e.g., ../guild)
_GRApH_ENGINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null)"

# ── Graph data (populated by parse_graph) ─────────────────────────

GRAPH_NAME=""
GRAPH_DESC=""

declare -A _NODE_AGENT
declare -A _NODE_ACTION
declare -A _NODE_NEEDS
declare -A _NODE_DELIVERS
declare -A _NODE_WHEN
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

# ── Helper: run embedded python script ────────────────────────────

# _run_py <func_name> [args...]
# Writes a Python script from a named heredoc and executes it.
_run_py() {
  local func_name="$1"; shift
  local script_file; script_file=$(mktemp /tmp/guild-py-XXXXXX.py)
  # Extract the script body from the named heredoc
  "_py_${func_name}" > "$script_file" 2>/dev/null || {
    # Fallback: lookup function in a predefined map
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
result = {'name': '', 'description': '', 'nodes': {}, 'edges': []}
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
                'delivers': [], 'when': {}
            }
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

# _py_emit_nodes — emit pipe-delimited node records
_py_emit_nodes() {
  cat << 'PYEOF'
import json, sys
d = json.load(sys.stdin)
nodes = d['nodes']
for nid, ndata in nodes.items():
    needs = ','.join(ndata.get('needs', []))
    delivers = ','.join(ndata.get('delivers', []))
    w = ndata.get('when', {})
    when_parts = ['{}:{}'.format(k,v) for k,v in w.items()]
    when_str = ';'.join(when_parts)
    print('{}|{}|{}|{}|{}|{}'.format(nid, ndata.get('agent',''), ndata.get('action','execute'), needs, delivers, when_str))
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

  while IFS='|' read -r node_id agent action needs delivers when_str; do
    [[ -z "$node_id" ]] && continue
    _NODE_ORDER+=("$node_id")
    _NODE_AGENT[$node_id]="$agent"
    _NODE_ACTION[$node_id]="$action"
    _NODE_NEEDS[$node_id]="$needs"
    _NODE_DELIVERS[$node_id]="$delivers"
    _NODE_WHEN[$node_id]="${when_str:-}"
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

  _compute_topological_order
  return 0
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

init_state() {
  local graph_name="${1:-$GRAPH_NAME}"
  _STATE_FILE="/tmp/guild-graph-${graph_name}-state.json"

  local nodes_json=""
  local first=true
  for node_id in "${_NODE_ORDER[@]}"; do
    $first || nodes_json+=","
    first=false
    nodes_json+="\"${node_id}\":{\"status\":\"pending\",\"started_at\":null,\"completed_at\":null,\"output\":null}"
  done

  cat > "$_STATE_FILE" << JSONEOF
{
  "name": "${GRAPH_NAME}",
  "graph_file": "$(readlink -f "${graph_file:-unknown}")",
  "started_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "completed_at": null,
  "current_iteration": 0,
  "nodes": {${nodes_json}}
}
JSONEOF
  ok "图状态已初始化: $_STATE_FILE"
}

_get_state() {
  local node="$1" field="$2"
  python3 -c "
import json
with open('$_STATE_FILE') as f:
    d = json.load(f)
if '$node' == '__graph__':
    print(d.get('$field', ''))
else:
    print(d['nodes'].get('$node', {}).get('$field', ''))
" 2>/dev/null || echo ""
}

_set_state() {
  local node="$1" field="$2" value="$3"
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
}

_set_node_status() {
  local node="$1" status="$2" output="${3:-}"
  local now; now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  python3 -c "
import json
with open('$_STATE_FILE') as f:
    d = json.load(f)
d['nodes']['$node']['status'] = '$status'
if '$status' == 'running':
    d['nodes']['$node']['started_at'] = '$now'
elif '$status' in ('completed', 'failed'):
    d['nodes']['$node']['completed_at'] = '$now'
    d['nodes']['$node']['output'] = '$output'
with open('$_STATE_FILE', 'w') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
" 2>/dev/null || true
  _EDGES_PROCESSED[$node]=""
}

_get_status() {
  python3 -c "
import json
with open('$_STATE_FILE') as f:
    d = json.load(f)
print(d['nodes'].get('$1', {}).get('status', 'unknown'))
" 2>/dev/null || echo "unknown"
}

_save_state() { :; }

# ── Node Discovery ────────────────────────────────────────────────

find_ready_nodes() {
  local ready=""
  for node_id in "${_NODE_ORDER[@]}"; do
    local status; status=$(_get_status "$node_id")
    [[ "$status" != "pending" ]] && continue

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
        # Accept "completed" for all needs; also accept "failed" when the
        # node has a "when" condition (the when gate handles flow).
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
      # If condition target is done, check if condition is met
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
          # Condition target is done but condition not met -> bypassed
          _PENDING_BYPASSED="${_PENDING_BYPASSED} ${node_id}"
          continue
        fi
      fi
      # Condition target still pending — not ready to classify yet
      continue
    fi

    # No when condition — check if dependencies can ever be met
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
          # If dep is failed, bypassed, or itself blocked -> node is blocked
          if [[ "$ds" == "failed" ]] || [[ "$_PENDING_BYPASSED" == *"$dep"* ]]; then
            has_dead_dep=true
          fi
        fi
      done
      if $has_dead_dep; then
        _PENDING_BLOCKED="${_PENDING_BLOCKED} ${node_id}"
      elif $all_met; then
        # Should be ready but isn't — treat as blocked
        _PENDING_BLOCKED="${_PENDING_BLOCKED} ${node_id}"
      fi
    else
      # No needs, no when -> should be ready; treat as blocked
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

  _set_node_status "$node_id" "running"

  echo ""
  echo "  +-----------------------------------------------"
  echo "  |  节点: ${node_id}"
  echo "  |  Agent: ${agent}"
  echo "  |  动作: ${action}"
  [[ -n "$delivers" ]] && echo "  |  产出: ${delivers}"
  echo "  +-----------------------------------------------"
  echo ""

  if $dry_run; then
    echo "  [DRY-RUN] 跳过执行"
    _set_node_status "$node_id" "completed"
    _LAST_COMPLETED="$node_id"
    return 0
  fi

  case "$action" in
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
        _set_node_status "$node_id" "completed" "跳过: 工作目录无文件"
        echo "  + 跳过（无文件需验证）"
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
            # Fallback: basic validation per type
            case "$ftype" in
              html|js|ts)
                # Check for common error patterns (debug artifacts, crash indicators)
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
            ok "    通过: ${relpath}"
          else
            err "    失败: ${relpath}"
            verify_ok=false
            fail_count=$((fail_count + 1))
          fi
        done < <(printf '%s\n' "$found_files")

        echo ""
        if [[ $checked_count -eq 0 ]]; then
          _set_node_status "$node_id" "completed" "跳过: 无支持验证的文件类型"
          echo "  + 跳过（所有文件类型均不支持验证）"
        elif $verify_ok; then
          _set_node_status "$node_id" "completed" "验证通过 (${checked_count}文件, 0失败)"
          echo "  + 验证通过 (${checked_count}文件)"
        else
          _set_node_status "$node_id" "failed" "验证未通过 (${checked_count}文件, ${fail_count}失败)"
          echo "  x 验证未通过 (${checked_count}文件, ${fail_count}失败)"
        fi
      fi
      ;;

    deliver)
      echo "  交付模式:"
      echo "    请在 ${work_dir} 中准备好以下交付物:"
      local old_ifs="$IFS"; IFS=','; set -- $delivers; IFS="$old_ifs"
      for item do
        [[ -z "$item" ]] && continue
        item="${item## }"; item="${item%% }"
        echo "    - ${item}"
      done
      echo ""
      [[ "$auto_yes" != "true" ]] && { echo "  准备完毕后按 Enter 继续..."; read -r; } || echo "  (自动模式)"

      local all_found=true
      local old_ifs="$IFS"; IFS=','; set -- $delivers; IFS="$old_ifs"
      for item do
        [[ -z "$item" ]] && continue
        item="${item## }"; item="${item%% }"
        local found; found=$(find "$work_dir" -type f -name "*${item}*" 2>/dev/null | head -1)
        [[ -z "$found" ]] && all_found=false
      done

      if $all_found; then
        _set_node_status "$node_id" "completed" "交付物已就绪"
        echo "  + 交付完成"
      else
        warn "  部分交付物未找到"
        _set_node_status "$node_id" "completed" "交付物可能不完整"
        echo "  + 继续（标记为已完成）"
      fi
      ;;

    *)
      echo "  执行 ${node_id}..."
      _set_node_status "$node_id" "completed" "执行完成"
      echo "  + 完成"
      ;;
  esac

  _LAST_COMPLETED="$node_id"
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

# _find_guild_cmd — locate the guild CLI script on PATH.
# Only checks PATH so test scenarios with minimal files fall through
# to the built-in per-file validators (which are more lenient).
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
        *failed*) [[ "$completed_status" == "failed" ]] && condition_met=true ;;
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
    [[ "$target_status" == "completed" || "$target_status" == "failed" ]] && is_back_edge=true

    if $is_back_edge; then
      echo "  | 回路 $to$( [[ -n "$label" ]] && echo " (${label})" )"
      _set_state "$to" "status" "pending"
      _set_state "$to" "output" null
      _set_state "$to" "started_at" null
      _set_state "$to" "completed_at" null
      _EDGES_PROCESSED[$to]=""  # Reset edge tracking for the target
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
  local completed=0 failed=0 running=0 pending=0
  for node_id in "${_NODE_ORDER[@]}"; do
    local s; s=$(_get_status "$node_id")
    case "$s" in
      completed) completed=$((completed + 1));;
      failed) failed=$((failed + 1));;
      running) running=$((running + 1));;
      pending) pending=$((pending + 1));;
    esac
  done

  echo "  节点统计: 总计=${total} 完成=${completed} 失败=${failed} 待处理=${pending} 运行中=${running}"
  echo ""
  echo "  节点明细:"
  _analyze_pending_nodes
  for node_id in "${_NODE_ORDER[@]}"; do
    local s; s=$(_get_status "$node_id")
    local icon
    case "$s" in completed) icon="[OK]";; failed) icon="[FAIL]";; running) icon="[RUN]";; pending) icon="[WAIT]";; *) icon="[?]";; esac
    local agent="${_NODE_AGENT[$node_id]}"
    local output; output=$(_get_state "$node_id" "output")
    echo "  ${icon} ${node_id} (${agent}) - ${s}"
    [[ -n "$output" && "$output" != "None" ]] && echo "      结果: ${output}"
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

# ── Main Entry Point ──────────────────────────────────────────────

run_graph() {
  local graph_file="$1" work_dir="$2" dry_run="${3:-false}" auto_yes="${4:-false}"

  [[ -f "$graph_file" ]] || { err "Graph file not found: $graph_file"; return 1; }
  [[ -d "$work_dir" ]] || mkdir -p "$work_dir"

  echo "  解析图定义: $(basename "$graph_file")..."
  parse_graph "$graph_file" || return 1

  init_state "$GRAPH_NAME"

  echo ""
  echo "============================="
  echo "  Graph Engine: ${GRAPH_NAME}"
  echo "============================="
  echo ""

  $dry_run && echo "  [DRY-RUN mode - no actual execution]"
  echo ""

  print_graph_info
  echo ""

  local start_time; start_time=$(date +%s)
  local iteration=0
  local max_iterations=100

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
        # Read result from temp file and update state
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
      if [[ "$s" == "completed" || "$s" == "failed" ]]; then
        if [[ -z "${_EDGES_PROCESSED[$node_id]:-}" ]]; then
          process_edges "$node_id"
          _EDGES_PROCESSED[$node_id]="1"
        fi
      fi
    done

    _save_state

    $dry_run && { echo ""; echo "  [DRY-RUN stop after first pass]"; break; }
  done

  [[ $iteration -ge $max_iterations ]] && warn "Max iterations reached"

  local end_time; end_time=$(date +%s)
  print_report "$graph_file" "$work_dir" $(( end_time - start_time ))
  _set_state "__graph__" "completed_at" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  local failed_count=0
  for node_id in "${_NODE_ORDER[@]}"; do
    s=$(_get_status "$node_id")
    [[ "$s" == "failed" ]] && failed_count=$((failed_count + 1))
  done
  return $failed_count
}
