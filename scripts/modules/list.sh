#!/usr/bin/env bash
# Module: list.sh — cmd_list
# Source guard: only loadable via guild
[[ -n "${_AG_MODULE_SOURCING:-}" ]] || { echo "This module must be loaded via guild, not run directly" >&2; exit 1; }

cmd_list() {
  local mode=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --contracts) mode="contracts"; shift;;
      --handoffs) mode="handoffs"; shift;;
      *) shift;;
    esac
  done

  case "$mode" in
    contracts)
      echo "已注册的交接契约:"
      awk '
        /^  [a-z]/ {
          if (slug != "") print slug ": 产出 " del_count " 项, 需求 " req_count " 项"
          slug=$1; gsub(/:$/, "", slug); del_count=0; req_count=0
        }
        /delivers:/ { in_del=1; in_req=0; next }
        /requires:/ { in_req=1; in_del=0; next }
        in_del && /- name:/ { del_count++ }
        in_req && /- name:/ { req_count++ }
        END { if (slug != "") print slug ": 产出 " del_count " 项, 需求 " req_count " 项" }
      ' "$CONTRACTS"
      ;;
    handoffs|*)
      cmd_status
      ;;
  esac
}
