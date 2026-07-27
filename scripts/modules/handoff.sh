#!/usr/bin/env bash
# Module: handoff.sh — cmd_handoff
# Source guard: only loadable via guild
[[ -n "${_AG_MODULE_SOURCING:-}" ]] || { echo "This module must be loaded via guild, not run directly" >&2; exit 1; }

# ── Commands ────────────────────────────────────────────────────────

cmd_handoff() {
  local from="" to="" path="" message=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --from) from="$2"; shift 2;;
      --to) to="$2"; shift 2;;
      --path) path="$2"; shift 2;;
      --message) message="$2"; shift 2;;
      *) shift;;
    esac
  done

  [[ -n "$from" ]] || die "--from is required"
  [[ -n "$to" ]] || die "--to is required"
  [[ -d "$path" ]] || die "--path must be a directory: $path"

  local from_slug to_slug
  from_slug="$(resolve_agent "$from")"
  to_slug="$(resolve_agent "$to")"

  [[ -n "$from_slug" ]] || die "Unknown agent: $from"
  [[ -n "$to_slug" ]] || die "Unknown agent: $to"

  local id
  id=$(next_id)
  local date
  date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  echo "创建交接 #${id}: ${from_slug} → ${to_slug}"

  # Get receiver's requirements (filter by sender if possible)
  local reqs
  reqs=$(get_requires "$to_slug" | grep "|${from_slug}|" || get_requires "$to_slug")

  # Scan artifacts
  local scan_result
  scan_result=$(scan_artifacts "$path" "$reqs")
  local matched
  matched=$(echo "$scan_result" | awk '/^MATCHED_START/{found=1; next} /^MATCHED_END/{found=0} found')
  local missing
  missing=$(echo "$scan_result" | awk '/^MISSING_START/{found=1; next} /^MISSING_END/{found=0} found')

  # Build JSON using node for proper string escaping
  local json_file
  json_file="$HANDOFFS_DIR/$(date +%Y-%m-%d)-${from_slug}-to-${to_slug}.json"
  mkdir -p "$HANDOFFS_DIR"

  # Write matched/missing to temp files for node to read
  local matched_file; matched_file=$(mktemp /tmp/guild-matched-XXXXXX.tsv)
  local missing_file; missing_file=$(mktemp /tmp/guild-missing-XXXXXX.tsv)
  echo -e "$matched" | grep -v '^$' > "$matched_file"
  echo -e "$missing" | grep -v '^$' > "$missing_file"

  # Pass variables via env to avoid bash escaping issues in node -e
  local req_total=0 req_provided=0 req_missing_count=0 new_status="incomplete"
  AG_HANDOFF_ID="$id" \
  AG_HANDOFF_FROM="$from_slug" \
  AG_HANDOFF_TO="$to_slug" \
  AG_HANDOFF_DATE="$date" \
  AG_HANDOFF_MSG="$message" \
  AG_HANDOFF_PATH="$path" \
  AG_HANDOFF_JSON="$json_file" \
  AG_MATCHED_FILE="$matched_file" \
  AG_MISSING_FILE="$missing_file" \
  node -e '
const { readFileSync, writeFileSync } = require("fs");

const matched = readFileSync(process.env.AG_MATCHED_FILE, "utf8").trim().split("\n").filter(Boolean);
const missing = readFileSync(process.env.AG_MISSING_FILE, "utf8").trim().split("\n").filter(Boolean);

const artifacts = [];
let req_provided = 0, req_missing_count = 0;

for (const line of matched) {
  const parts = line.split("|");
  const name = parts[0], source = parts[1] || "found";
  if (!name) continue;
  artifacts.push({ name, file: source, status: "provided" });
  req_provided++;
}

for (const line of missing) {
  const parts = line.split("|");
  const name = parts[1], required = parts[2];
  if (!name) continue;
  const isRequired = required === "True";
  artifacts.push({ name, file: null, status: "missing", required: isRequired });
  if (isRequired) req_missing_count++;
}

const req_total = req_provided + artifacts.filter(a => a.status === "missing").length;
const new_status = req_missing_count === 0 ? "ready" : "incomplete";

const doc = {
  id: parseInt(process.env.AG_HANDOFF_ID),
  from: process.env.AG_HANDOFF_FROM,
  to: process.env.AG_HANDOFF_TO,
  timestamp: process.env.AG_HANDOFF_DATE,
  message: process.env.AG_HANDOFF_MSG,
  path: process.env.AG_HANDOFF_PATH,
  artifacts,
  checklist: { required_total: req_total, required_provided: req_provided, required_missing: req_missing_count },
  status: new_status,
  accepted_by: null
};

writeFileSync(process.env.AG_HANDOFF_JSON, JSON.stringify(doc, null, 2) + "\n", "utf8");
'

  # Read stats from the written JSON
  req_total=$(json_get "$json_file" "required_total" "0")
  req_provided=$(json_get "$json_file" "required_provided" "0")
  req_missing_count=$(json_get "$json_file" "required_missing" "0")
  new_status=$(json_get "$json_file" "status" "incomplete")

  rm -f "$matched_file" "$missing_file"

  echo "  状态: $new_status"
  echo "  完整度: $req_provided/$req_total 项已提供"
  if [[ $req_missing_count -gt 0 ]]; then
    echo "  [!!] 缺失 $req_missing_count 项:"
    echo -e "$missing" | grep '|True$' | while IFS='|' read -r from_name name required; do
      echo "       - $name"
    done
  fi
  echo "  记录: $json_file"

  # Auto-verify deliverable quality (only if completeness passed)
  echo ""
  echo "  质量验证..."
  local verify_failed=false
  local is_ready; is_ready=false
  grep -q '"status": "ready"' "$json_file" 2>/dev/null && is_ready=true

  while IFS= read -r -d '' f; do
    local vtype; vtype=$(detect_type "$f")
    if [[ -n "$vtype" ]]; then
      if verify_file "$vtype" "$f"; then
        echo "    ✅ $(basename "$f"): 通过"
      else
        verify_failed=true
        echo "    ❌ $(basename "$f"): 质量检查未通过"
      fi
    fi
  done < <(find "$path" -type f -print0 2>/dev/null)

  if $verify_failed; then
    if $is_ready; then
      sed -i 's/"status": "ready"/"status": "needs_fix"/' "$json_file"
      is_ready=false
    fi
    echo ""
    echo "  ⚠️  状态已更新为 needs_fix（交付物存在但质量检查未通过）"
  else
    echo ""
    echo "  ✓ 质量验证通过"
  fi

  # Auto-notify receiver's inbox
  local status_text
  if $is_ready; then
    status_text="$from_slug 创建了交接 #$id，所有交付物已就绪"
  else
    if $verify_failed; then
      status_text="$from_slug 创建了交接 #$id，交付物存在但质量检查未通过"
    else
      status_text="$from_slug 创建了交接 #$id，存在缺失项待补充"
    fi
  fi
  add_inbox_item "$to_slug" "handoff_incoming" "$from_slug" \
    "handoff_id=$id" \
    "$status_text" \
    "检查交付物并运行 guild accept --handoff $id"
  echo "  📨 已通知 $to_slug"

  # Context check: are there relevant decisions this handoff should follow?
  echo ""
  echo "  上下文检查..."

  local relevant=0
  for f in "$REPO_ROOT/context/decisions"/*.json; do
    [[ -f "$f" ]] || continue
    local dec_agent; dec_agent=$(grep -o '"agent": "[^"]*"' "$f" | head -1 | cut -d'"' -f4)
    local dec_topic; dec_topic=$(grep -o '"topic": "[^"]*"' "$f" | head -1 | cut -d'"' -f4)
    local dec_status; dec_status=$(grep -o '"status": "[^"]*"' "$f" | tail -1 | cut -d'"' -f4)

    # If the decision maker is the sender or receiver of this handoff
    if [[ "$dec_agent" == "$from_slug" || "$dec_agent" == "$to_slug" ]] && [[ "$dec_status" == "active" ]]; then
      ((relevant++)) 2>/dev/null || true
      echo "    📋 相关决策: #$(grep -o '"id": [0-9]*' "$f" | head -1 | awk '{print $2}') [$dec_agent] $dec_topic"
    fi
  done

  [[ $relevant -gt 0 ]] && echo "    → 建议确认交付物是否遵循以上决策" || echo "    (无相关决策)"

  # Auto-detect conflicts
  local conflict_found=false
  for f in "$REPO_ROOT/context/decisions"/*.json; do
    [[ -f "$f" ]] || continue
    local dec_agent; dec_agent=$(grep -o '"agent": "[^"]*"' "$f" | head -1 | cut -d'"' -f4)
    local dec_topic; dec_topic=$(grep -o '"topic": "[^"]*"' "$f" | head -1 | cut -d'"' -f4)

    # Check if another agent has a decision on the same topic with different content
    for g in "$REPO_ROOT/context/decisions"/*.json; do
      [[ -f "$g" ]] || continue
      [[ "$f" == "$g" ]] && continue
      local g_agent; g_agent=$(grep -o '"agent": "[^"]*"' "$g" | head -1 | cut -d'"' -f4)
      local g_topic; g_topic=$(grep -o '"topic": "[^"]*"' "$g" | head -1 | cut -d'"' -f4)

      if [[ "$dec_topic" == "$g_topic" && "$dec_agent" != "$g_agent" ]]; then
        # Same topic, different agents — potential conflict
        if [[ "$dec_agent" == "$from_slug" || "$dec_agent" == "$to_slug" ]] || [[ "$g_agent" == "$from_slug" || "$g_agent" == "$to_slug" ]]; then
          $conflict_found && continue
          conflict_found=true
          echo ""
          warn "检测到潜在决策冲突: $dec_topic"
          echo "    $dec_agent vs $g_agent"
          echo "    建议: 运行 guild context check 查看详情"
          echo "    建议: 在继续交接前解决此冲突"
          # Auto-notify conflicting agents
          add_inbox_item "$dec_agent" "conflict_active" "$g_agent" \
            "topic=$dec_topic" \
            "与 $g_agent 在 $dec_topic 上存在矛盾决策" \
            "基于决策权重协商解决。运行 guild resolve --topic '$dec_topic'"
          add_inbox_item "$g_agent" "conflict_active" "$dec_agent" \
            "topic=$g_topic" \
            "与 $dec_agent 在 $g_topic 上存在矛盾决策" \
            "基于决策权重协商解决。运行 guild resolve --topic '$g_topic'"
        fi
      fi
    done
  done
}
