# Graph Engine — Architecture Pivot Report

## Summary

Successfully architected and implemented the AgentGuild Graph Engine — replacing linear pipelines with directed graph-based workflows supporting loops, parallel execution, and conditional edges.

## Deliverables

### Core Engine
- `scripts/graph-engine.sh` — Pure Bash graph execution engine (932 lines)
  - YAML graph definition parser (with Python3 assistance)
  - Dependency-driven node scheduling (Kahn's topological sort)
  - Parallel node execution via background processes + result files
  - Loop handling (back-edge detection and node reset)
  - Conditional edges (when: clauses with passed/failed mapping)
  - JSON state persistence at `/tmp/guild-graph-<name>-state.json`
  - Execution report generation

### Graph Definitions
- `graphs/feature-dev.yml` — 7-node single feature development with test → fix loop
- `graphs/game-mvp.yml` — 9-node game MVP with parallel art/code/ui/audio
- `graphs/iterate.yml` — 6-node product iteration with feedback loop

### CLI Integration
- `scripts/nexus.sh` — Added `guild graph` commands:
  - `guild graph run` — Execute a graph (--graph, --path, --dry-run, --yes)
  - `guild graph status` — View running graph state
  - `guild graph show` — Display graph structure
  - `guild graph list` — List available graphs

## Verification

```bash
# Syntax checks
bash -n scripts/graph-engine.sh   # PASS
bash -n scripts/nexus.sh          # PASS

# List available graphs
./guild graph list                # 3 graphs found

# Show graph structures
./guild graph show feature-dev    # 7 nodes, 3 edges
./guild graph show game-mvp       # 9 nodes, 3 edges
./guild graph show iterate        # 6 nodes, 3 edges

# Full execution
./guild graph run --graph feature-dev --path /tmp/test --yes  # 5 iterations, 3s, 6/7 completed
./guild graph status                                           # Shows running state

# Lint still passes
./scripts/lint.sh --all            # 40 PASS
```

## Key Technical Decisions

1. **Node+Edge+State primitives**: Clean separation between graph structure (YAML), execution logic (Bash), and runtime state (JSON).

2. **Heredoc Python scripts**: Used `cat << 'PYEOF'` with quoted delimiters to embed Python parsers without Bash quoting issues.

3. **Result file for parallel**: Background processes write node results to temp files, avoiding concurrent state file writes.

4. **Condition mapping**: "passed" → "completed" semantic mapping ensures both node-level `when` and edge-level conditions work consistently.

5. **Blocked detection**: `is_blocked()` properly identifies nodes whose `when` conditions can never be met, preventing infinite loops.

## Architecture

```
graph.yml ──→ parse_graph() ──→ Bash associative arrays
                                      │
state.json ←── init_state() ──────────┘
                                      │
                    ┌──────────────────┘
                    ▼
            while loop (max 100)
                    │
         find_ready_nodes() ──→ topological order
                    │
         execute_node() ──→ parallel via &
                    │
         process_edges() ──→ conditional + loop
                    │
         print_report() ──→ final summary
```

## Node Types

| Action | Behavior |
|--------|----------|
| `deliver` | Prompts user for deliverables, checks existence |
| `verify` | Runs quality verification on deliverables |
| `execute` | Default — marks node as completed |

## Edge Types

| Type | Detection | Behavior |
|------|-----------|----------|
| Forward | Target is pending | Marks target as ready |
| Backward (loop) | Target is completed/failed | Resets target to pending |
| Conditional | Has `when:` clause | Only triggers when condition matches |
