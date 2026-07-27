#!/usr/bin/env bash
# Module: run.sh — cmd_run
# Source guard: only loadable via guild
[[ -n "${_AG_MODULE_SOURCING:-}" ]] || { echo "This module must be loaded via guild, not run directly" >&2; exit 1; }

cmd_run() {
  local pipeline="" path="" dry_run=false auto_yes=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --pipeline) pipeline="$2"; shift 2;;
      --path) path="$2"; shift 2;;
      --dry-run) dry_run=true; shift;;
      --yes) auto_yes=true; shift;;
      --list) for f in "$REPO_ROOT/pipelines/"*.yml; do
                [[ -f "$f" ]] || continue
                local name; name=$(grep -m1 '^name:' "$f" | sed 's/^name: *//')
                local desc; desc=$(grep -m1 '^description:' "$f" | sed 's/^description: *//')
                echo "  $(basename "$f" .yml) — $name"
                [[ -n "$desc" ]] && echo "    $desc"
              done; return;;
      *) shift;;
    esac
  done

  [[ -n "$pipeline" ]] || die "--pipeline <name> is required"
  [[ -n "$path" ]] || die "--path <dir> is required"
  [[ -d "$path" ]] || die "--path must be a directory: $path"

  local pipeline_file="$REPO_ROOT/pipelines/${pipeline}.yml"
  [[ -f "$pipeline_file" ]] || die "Pipeline not found: $pipeline (looked for $pipeline_file)"

  echo "============================================"
  echo "  流水线: $pipeline"
  echo "============================================"
  echo ""

  if $dry_run; then
    echo "[DRY-RUN 模式 — 不会创建实际交接]"
    echo ""
  fi

  # Read phases from pipeline YAML
  local phase_count; phase_count=$(grep -c '^  - phase:' "$pipeline_file")

  for ((i=0; i<phase_count-1; i++)); do
    local current_phase next_phase current_agents next_agents
    current_phase=$(awk -v n=$((i+1)) '/^  - phase:/{count++; if(count==n){sub(/.*phase: /,""); print; exit}}' "$pipeline_file")
    next_phase=$(awk -v n=$((i+2)) '/^  - phase:/{count++; if(count==n){sub(/.*phase: /,""); print; exit}}' "$pipeline_file")
    current_agents=$(awk -v n=$((i+1)) '/^  - phase:/{count++} count==n && /agents:/{gsub(/.*agents: \[|\]/,""); gsub(/,/," "); print; exit}' "$pipeline_file")
    next_agents=$(awk -v n=$((i+2)) '/^  - phase:/{count++} count==n && /agents:/{gsub(/.*agents: \[|\]/,""); gsub(/,/," "); print; exit}' "$pipeline_file")

    echo "━━━ 阶段: $current_phase → $next_phase ━━━"
    echo "  当前: $current_agents"
    echo "  产出后交给: $next_agents"
    echo ""
    echo "  请在 $path 目录中准备好 $current_phase 阶段的交付物"
    if $auto_yes; then
      echo "  (全自动模式 - 跳过用户提示)"
    else
      echo "  完成后按 Enter 继续（或输入 'skip' 跳过此阶段）..."
      if ! $dry_run; then
        read -r input
        [[ "$input" == "skip" ]] && { echo "  已跳过"; echo ""; continue; }
      fi
    fi

    echo ""
    echo "  正在创建交接..."

    # Auto-handoff: each current agent → each next agent
    local all_ready=true
    for from_agent in $current_agents; do
      for to_agent in $next_agents; do
        if $dry_run; then
          echo "    [DRY-RUN] $from_agent → $to_agent"
        else
          echo "    $from_agent → $to_agent"
          # Use the handoff logic inline
          local from_slug to_slug
          from_slug="$(resolve_agent "$from_agent")"
          to_slug="$(resolve_agent "$to_agent")"

          [[ -n "$from_slug" ]] || { echo "      [!!] 未知 Agent: $from_agent"; continue; }
          [[ -n "$to_slug" ]] || { echo "      [!!] 未知 Agent: $to_agent"; continue; }

          local id; id=$(next_id)
          local date; date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

          # Get receiver's requirements
          local reqs; reqs=$(get_requires "$to_slug" | grep "|${from_slug}|" || get_requires "$to_slug")

          # Scan artifacts
          local scan_result; scan_result=$(scan_artifacts "$path" "$reqs")
          local matched; matched=$(echo "$scan_result" | awk '/^MATCHED_START/{found=1; next} /^MATCHED_END/{found=0} found')
          local missing; missing=$(echo "$scan_result" | awk '/^MISSING_START/{found=1; next} /^MISSING_END/{found=0} found')

          local req_missing; req_missing=$(echo "$missing" | grep -c '|True$' 2>/dev/null || echo 0)

          # Build JSON record
          local json_file="$HANDOFFS_DIR/$(date +%Y-%m-%d)-${pipeline}-${from_slug}-to-${to_slug}.json"

          # Write matched/missing to temp files for safe data transfer
          local mtmp; mtmp=$(mktemp); local mtmp2; mtmp2=$(mktemp)
          echo "$matched" > "$mtmp"
          echo "$missing" > "$mtmp2"

          if command -v node &>/dev/null; then
            node -e "
const fs=require('fs');
const matched=fs.readFileSync('$mtmp','utf8').trim().split('\n').filter(l=>l);
const missing=fs.readFileSync('$mtmp2','utf8').trim().split('\n').filter(l=>l);
const artifacts=[];
for(const l of matched){const p=l.split('|');if(p.length>=2)artifacts.push({name:p[0],file:'found',status:'provided'})}
for(const l of missing){const p=l.split('|');if(p.length>=3)artifacts.push({name:p[1],file:null,status:'missing',required:p[2]==='True'})}
const rt=artifacts.length,rp=artifacts.filter(a=>a.status==='provided').length;
const rm=artifacts.filter(a=>a.status==='missing'&&a.required!==false).length;
const rec={id:$id,from:'$from_slug',to:'$to_slug',timestamp:'$date',pipeline:'$pipeline',phase_from:'$current_phase',phase_to:'$next_phase',path:'$path',artifacts:artifacts,checklist:{required_total:rt,required_provided:rp,required_missing:rm},status:rm===0?'ready':'incomplete',accepted_by:null};
fs.mkdirSync('$HANDOFFS_DIR',{recursive:true});
fs.writeFileSync('$json_file',JSON.stringify(rec,null,2)+'\n','utf8');
console.log('      状态: '+rec.status);
console.log('      完整度: '+rp+'/'+rt);
if(rm>0){console.log('      [!!] 缺失 '+rm+' 项');for(const a of artifacts){if(a.status==='missing')console.log('           - '+a.name)}}
" 2>/dev/null
          fi
          rm -f "$mtmp" "$mtmp2"

          if [[ "$req_missing" -gt 0 ]]; then
            all_ready=false
          fi
        fi
      done
    done

    if ! $all_ready && ! $dry_run; then
      echo ""
      if ! $auto_yes; then
        echo "  ⚠️  存在缺失项。请补充后按 Enter 重试（或输入 'skip' 跳过）..."
        read -r input
        [[ "$input" == "skip" ]] && { echo "  已跳过"; echo ""; continue; }
      else
        echo "  (全自动模式 - 跳过缺失项检查)"
      fi
    fi

    echo ""
    echo "  ✓ 阶段 $current_phase → $next_phase 完成"

    # Auto context check after phase
    if ! $dry_run; then
      echo ""
      echo "  正在运行上下文检查..."
      "$0" context check 2>/dev/null | head -10
    fi

    echo ""
  done

  echo "============================================"
  echo "  流水线完成: $pipeline"
  echo "============================================"

  # Show inbox summary
  echo ""
  echo "=== 收件箱摘要 ==="
  local any_inbox=false
  for d in "$REPO_ROOT/context/inbox"/*/; do
    [[ -d "$d" ]] || continue
    local a; a=$(basename "$d")
    local unread; unread=$(count_unread "$a")
    if [[ "$unread" -gt 0 ]]; then
      echo "  $a: $unread 未读"
      any_inbox=true
    fi
  done
  $any_inbox || echo "  所有收件箱为空"
}
