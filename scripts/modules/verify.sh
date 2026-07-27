#!/usr/bin/env bash
# Module: verify.sh — cmd_verify
# Source guard: only loadable via guild
[[ -n "${_AG_MODULE_SOURCING:-}" ]] || { echo "This module must be loaded via guild, not run directly" >&2; exit 1; }

# ── cmd_verify ───────────────────────────────────────────────────────

# Usage: guild verify --type <type> --file <path>
#        guild verify --path <dir>
#        guild verify --handoff <id>

cmd_verify() {
  local verify_type="" file_path="" dir_path="" handoff_id=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --type) verify_type="$2"; shift 2;;
      --file) file_path="$2"; shift 2;;
      --path) dir_path="$2"; shift 2;;
      --handoff) handoff_id="$2"; shift 2;;
      *) shift;;
    esac
  done

  # Resolve handoff path
  if [[ -n "$handoff_id" ]]; then
    local json_file=""
    for f in "$HANDOFFS_DIR"/*.json; do
      [[ -f "$f" ]] || continue
      local fid
      fid=$(json_get "$f" "id")
      if [[ "$fid" == "$handoff_id" ]]; then
        json_file="$f"
        break
      fi
    done
    [[ -f "$json_file" ]] || die "Handoff #$handoff_id not found"
    dir_path=$(json_get "$json_file" "path")
    [[ -d "$dir_path" ]] || die "Handoff #$handoff_id path not found: $dir_path"
  fi

  if [[ -n "$file_path" ]]; then
    # Single file verify
    [[ -n "$verify_type" ]] || verify_type=$(detect_type "$file_path")
    [[ -n "$verify_type" ]] || die "Cannot detect type for $file_path. Use --type."
    echo "验证: $file_path"
    echo "  类型: $verify_type"
    if verify_file "$verify_type" "$file_path"; then
      ok "通过"
      return 0
    else
      return 1
    fi
  elif [[ -n "$dir_path" ]]; then
    # Directory verify
    echo "验证目录: $dir_path"
    echo ""
    if verify_directory "$dir_path"; then
      echo ""
      ok "目录验证通过"
      return 0
    else
      echo ""
      err "目录验证存在未通过项"
      return 1
    fi
  else
    die "需要 --type --file <path>, --path <dir>, 或 --handoff <id>"
  fi
}
