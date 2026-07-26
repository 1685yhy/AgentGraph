# Behavioral Verification Report

## Summary

Added a complete behavioral verification layer to AgentGraph. This closes the gap between "document-level QA" (syntax checks) and "real team collaboration" (does it actually work?).

## What Was Built

### 1. Script: `scripts/test-runner.sh`
The behavioral test engine with 8 built-in checks and extensible test architecture.

**Test types supported:**
- `html-behavior` — Static analysis of HTML/JS: event bindings, guards, error handling patterns
- `html-click` — DOM element existence and handler binding verification
- `html-load` — HTML structure completeness (DOCTYPE, head, body, scripts)
- `http-get` — curl an endpoint and verify status code
- `bash-run` — run a command and check exit code
- `js-condition` — check for specific JS patterns in code

### 2. Command: `guild test`
Integrated into the guild CLI via `nexus.sh`. Three modes:
- `guild test --file <path>` — Run standard test suite on an HTML file
- `guild test --file <path> --spec <spec.yml>` — Run custom test spec
- `guild test --handoff <id>` — Find HTML files in handoff path and run behavioral tests
- `guild test --generate --from-agent <agent> --file <path> [--output <file>]` — Auto-generate test specs from agent contracts

### 3. Quality Gate 4: Behavioral Test Pass
Added to `cmd_accept` in `nexus.sh`. The acceptance flow now has 4 gates:

| Gate | Check | When Blocked |
|------|-------|-------------|
| 1 | handoff status must be "ready" | Incomplete/needs_fix/accepted |
| 2 | all files must pass syntax verify | JS/HTML/CSS errors |
| 3 | no open critical bugs | Unresolved critical feedback |
| **4** | **ALL behavioral tests must pass** | **8 HTML behavioral checks fail** |

### 4. 8 Behavioral Checks for HTML Games
Checks that a real QA engineer would test by playing the game:

| # | Check | What It Tests |
|---|-------|---------------|
| 1 | Start button bound | `btn-start` exists and calls `startGame` |
| 2 | showShare guard | Share overlay only shown after gameover |
| 3 | Audio error handling | `Audio.init()` doesn't crash on failure |
| 4 | Game loop guard | Render only runs during `playing` phase |
| 5 | Share isolation | `share-close` doesn't call `navigator.share()` |
| 6 | Canvas safety | Draw paths check `ctx` before rendering |
| 7 | localStorage safe | All storage wrapped in try-catch |
| 8 | DOM access safe | `getElementById` uses safe wrapper/null check |

## Test Results

### Color Clash (good game)
```
Result: 8 passed, 0 failed / total 8
Exit: 0
```

### Bad game (intentionally broken)
```
Result: 2 passed, 6 failed / total 8
Exit: 1
```

### Acceptance gate: verified
When accepting handoff #6 with Color Clash, Gate 4 ran all 8 behavioral checks:

```
行为测试门禁 (Gate 4):
  检查: color-clash.html
    Result: 8 passed, 0 failed / total 8
    All behavioral tests passed
交接 #6 已接收 — game-qa-engineer 开始工作
```

## Architecture

```
nexus.sh (cmd_accept, cmd_test dispatch)
    └── sources test-runner.sh
         ├── cmd_test()
         │   ├── --file <path> → run_all_tests()
         │   ├── --handoff <id> → find HTML files → run_all_tests()
         │   └── --generate → generate_test_spec()
         │
         ├── run_all_tests()
         │   ├── No spec → Standard 8-check suite
         │   └── Spec file → parse_test_spec() → run per-item
         │
         └── 8 check functions
              ├── check_start_button_bound
              ├── check_showShare_guard
              ├── check_audio_error_handling
              ├── check_game_loop_guard
              ├── check_share_close_no_navigator_share
              ├── check_canvas_context_safety
              ├── check_localStorage_safe
              └── check_unguarded_dom_access
```

## Extending

To add a new behavioral check:
1. Write a function `check_<name>()` in `test-runner.sh`
2. Add the check call to `run_all_tests()` (for standard suite)
3. Add a mapping in `run_html_behavior_test()` (for spec-based testing)
4. Add the check to `generate_test_spec()` (for auto-generation)
