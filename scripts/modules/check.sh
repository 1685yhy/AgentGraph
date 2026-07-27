#!/usr/bin/env bash
# Module: check.sh — cmd_check
# Source guard: only loadable via guild
[[ -n "${_AG_MODULE_SOURCING:-}" ]] || { echo "This module must be loaded via guild, not run directly" >&2; exit 1; }

cmd_check() {
  local id="" check_dups=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --handoff) id="$2"; shift 2;;
      --duplicates) check_dups=true; shift;;
      *) shift;;
    esac
  done

  # --duplicates mode: scan all handoffs for duplicate IDs
  if $check_dups; then
    if command -v node &>/dev/null; then
      node -e "
const fs = require('fs'), path = require('path');
const hdir = '$HANDOFFS_DIR';
const ids = {};
for (const fn of fs.readdirSync(hdir).filter(f => f.endsWith('.json')).sort()) {
  try { const d = JSON.parse(fs.readFileSync(path.join(hdir, fn), 'utf8')); (ids[d.id] = ids[d.id] || []).push(fn); } catch(e) {}
}
let dupFound = false;
for (const [idVal, fns] of Object.entries(ids).sort((a,b) => a[0]-b[0])) {
  if (fns.length > 1) { dupFound = true; console.log('  DUPLICATE ID #' + idVal + ': ' + fns.join('  ')); }
}
if (!dupFound) console.log('  No duplicate IDs found');
else { console.log(''); console.log('  Run \"guild cleanup\" to reset duplicate handoffs'); }
process.exit(dupFound ? 1 : 0);
"
    else
      err "node required for duplicate check"
      return 1
    fi
    return
  fi

  [[ -z "$id" ]] && die "--handoff <id> is required"

  # Find handoff file by ID (pure bash)
  local json_file=""
  for f in "$HANDOFFS_DIR"/*.json; do
    [[ -f "$f" ]] || continue
    local fid
    fid=$(json_get "$f" "id" "0")
    if [[ "$fid" == "$id" ]]; then
      json_file="$f"
      break
    fi
  done

  [[ -f "$json_file" ]] || die "Handoff #$id not found"

  # Display handoff details
  local d_id d_from d_to d_status d_timestamp d_provided d_total d_missing
  d_id=$(json_get "$json_file" "id")
  d_from=$(json_get "$json_file" "from")
  d_to=$(json_get "$json_file" "to")
  d_status=$(json_get "$json_file" "status")
  d_timestamp=$(json_get "$json_file" "timestamp")
  echo "交接 #${d_id}: ${d_from} → ${d_to}"
  echo "状态: ${d_status}"
  echo "时间: ${d_timestamp:0:19}"

  # Parse checklist via node or bash
  if command -v node &>/dev/null; then
    node -e "
const d=JSON.parse(require('fs').readFileSync('$json_file','utf8'));
const c=d.checklist||{};
console.log('完整度: '+c.required_provided+'/'+c.required_total+' 项');
if((c.required_missing||0)>0){console.log('缺失项:');for(const a of(d.artifacts||[])){if(a.status==='missing')console.log('  - '+a.name)}}
else{console.log('所有必需项已满足 ✓')}
"
  else
    cat "$json_file"
  fi
}
