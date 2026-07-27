#!/usr/bin/env bash
# Module: context.sh — cmd_context
# Source guard: only loadable via guild
[[ -n "${_AG_MODULE_SOURCING:-}" ]] || { echo "This module must be loaded via guild, not run directly" >&2; exit 1; }

# ── cmd_context ────────────────────────────────────────────────────────

cmd_context() {
  local sub="${1:-show}"; shift || true

  case "$sub" in
    show)
      echo "=== 决策图谱 ==="
      echo ""

      local idx="$REPO_ROOT/context/index.json"
      [[ -f "$idx" ]] || { echo "  暂无决策记录。使用 guild decide 创建第一条。"; return 0; }

      # Group by type
      echo "按类型分组："
      local types=""
      if command -v node &>/dev/null; then
        types=$(node -e "
const idx=JSON.parse(require('fs').readFileSync('$idx','utf8'));
const types={};
for(const d of(idx.decisions||[])){if(!types[d.type])types[d.type]=[];types[d.type].push(d)}
for(const t of Object.keys(types).sort())console.log(t+':'+types[t].length);
" 2>/dev/null)
      fi

      if [[ -n "$types" ]]; then
        echo "$types" | while IFS=':' read -r t count; do
          echo "  $t ($count 条)"
          # List decisions of this type
          if command -v node &>/dev/null; then
            node -e "
const idx=JSON.parse(require('fs').readFileSync('$idx','utf8'));
for(const d of(idx.decisions||[])){if(d.type==='$t')console.log('    #'+d.id+' ['+d.agent+'] '+d.topic+' ('+d.status+')')}
" 2>/dev/null
          fi
        done
      else
        # Fallback: list all from files
        echo "  (使用文件列表)"
        for f in "$REPO_ROOT/context/decisions"/*.json; do
          [[ -f "$f" ]] || continue
          local id; id=$(grep -o '"id": [0-9]*' "$f" | head -1 | awk '{print $2}')
          local agent; agent=$(grep -o '"agent": "[^"]*"' "$f" | head -1 | cut -d'"' -f4)
          local topic; topic=$(grep -o '"topic": "[^"]*"' "$f" | head -1 | cut -d'"' -f4)
          local status; status=$(grep -o '"status": "[^"]*"' "$f" | tail -1 | cut -d'"' -f4)
          echo "    #$id [$agent] $topic ($status)"
        done
      fi
      ;;

    check)
      echo "=== 冲突检查 ==="
      echo ""

      local idx="$REPO_ROOT/context/index.json"
      [[ -f "$idx" ]] || { echo "  暂无决策。"; return 0; }

      local conflicts=0

      # Check 1: Decisions on same topic by different agents
      echo "1. 同主题多决策："
      local check1_output="CONFLICT_COUNT=0"
      if command -v node &>/dev/null; then
        check1_output=$(node -e "
const idx=JSON.parse(require('fs').readFileSync('$idx','utf8'));
const topics={};
for(const d of(idx.decisions||[])){if(d.status==='active'){if(!topics[d.topic])topics[d.topic]=[];topics[d.topic].push(d)}}
let found=0;
for(const[t,decs]of Object.entries(topics)){
  if(decs.length>1){const agents=new Set(decs.map(d=>d.agent));if(agents.size>1){
    found++;console.log('  ⚠️  冲突: '+t);
    for(const d of decs)console.log('      #'+d.id+' ['+d.agent+']: '+d.topic);
  }}
}
console.log('CONFLICT_COUNT='+found);
" 2>/dev/null) || check1_output="CONFLICT_COUNT=0"
      else
        echo "  (无法运行冲突检查 — node required)"
      fi

      # Print check output (excluding the CONFLICT_COUNT marker)
      echo "$check1_output" | grep -v "^CONFLICT_COUNT="
      local conflict_count; conflict_count=$(echo "$check1_output" | grep "^CONFLICT_COUNT=" | cut -d= -f2)
      conflict_count=${conflict_count:-0}
      if [[ "$conflict_count" -gt 0 ]]; then
        conflicts=$conflict_count
        # Auto-notify conflicting agents from context check
        local conflict_notify_done=false
        for f in "$REPO_ROOT/context/decisions"/*.json; do
          [[ -f "$f" ]] || continue
          local dec_agent; dec_agent=$(grep -o '"agent": "[^"]*"' "$f" | head -1 | cut -d'"' -f4)
          local dec_topic; dec_topic=$(grep -o '"topic": "[^"]*"' "$f" | head -1 | cut -d'"' -f4)
          for g in "$REPO_ROOT/context/decisions"/*.json; do
            [[ -f "$g" ]] || continue
            [[ "$f" == "$g" ]] && continue
            local g_agent; g_agent=$(grep -o '"agent": "[^"]*"' "$g" | head -1 | cut -d'"' -f4)
            local g_topic; g_topic=$(grep -o '"topic": "[^"]*"' "$g" | head -1 | cut -d'"' -f4)
            if [[ "$dec_topic" == "$g_topic" && "$dec_agent" != "$g_agent" ]]; then
              $conflict_notify_done && continue
              conflict_notify_done=true
          add_inbox_item "$dec_agent" "conflict_active" "$g_agent" \
            "topic=$dec_topic" \
            "与 $g_agent 在 $dec_topic 上存在矛盾决策" \
            "基于决策权重协商解决。运行 guild resolve --topic '$dec_topic'"
          add_inbox_item "$g_agent" "conflict_active" "$dec_agent" \
            "topic=$g_topic" \
            "与 $dec_agent 在 $g_topic 上存在矛盾决策" \
            "基于决策权重协商解决。运行 guild resolve --topic '$g_topic'"
            fi
          done
        done
      fi

      # Check 2: Handoff traceability
      echo ""
      echo "2. 决策追溯："
      local total_trace=0
      for f in "$REPO_ROOT/context/decisions"/*.json; do
        [[ -f "$f" ]] || continue
        local traces; traces=$(grep -c '"handoff_id"' "$f" 2>/dev/null || echo 0)
        ((total_trace += traces)) 2>/dev/null || true
      done
      echo "  总决策数: $(ls "$REPO_ROOT/context/decisions"/*.json 2>/dev/null | wc -l)"
      echo "  已追溯的交付物: $total_trace"

      echo ""
      [[ $conflicts -gt 0 ]] && echo "  ⚠️  发现潜在冲突，运行 guild resolve 处理。" || echo "  ✓ 未检测到冲突。"
      ;;

    *)
      echo "用法: guild context [show|check]"
      ;;
  esac
}
