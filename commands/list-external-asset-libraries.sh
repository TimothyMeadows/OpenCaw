#!/usr/bin/env bash
set -euo pipefail
command_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
node_script="$command_dir/lib/style-contract.cjs"
node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || { echo 'Node.js is required for host style policy; nothing was installed.' >&2; exit 1; }
if [[ "$node_bin" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then node_script="$(wslpath -w "$node_script")"; fi
for argument in "$@"; do
  if [[ "$argument" == --help || "$argument" == -h ]]; then exec "$node_bin" "$node_script" libraries --help; fi
done
source "$command_dir/lib/memory-common.sh"
opencaw_resolve_paths
node_root="$OPENCAW_PROJECT_ROOT_RESOLVED"
node_arguments=("$@")
if [[ "$node_bin" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then
  node_root="$(wslpath -w "$node_root")"
  node_policy_path() {
    if [[ "$1" =~ ^[A-Za-z]:[\\/] || "$1" == \\\\* ]]; then printf '%s' "$1"; else wslpath -w "$1"; fi
  }
  for ((index=0; index<${#node_arguments[@]}; index++)); do
    case "${node_arguments[$index]}" in
      --style|--evidence|--engine-evidence|--engine-output)
        [[ $((index+1)) -lt ${#node_arguments[@]} ]] || break
        index=$((index+1)); node_arguments[$index]="$(node_policy_path "${node_arguments[$index]}")" ;;
      --*) ;;
      *) if [[ libraries == validate ]]; then node_arguments[$index]="$(node_policy_path "${node_arguments[$index]}")"; fi ;;
    esac
  done
fi
exec "$node_bin" "$node_script" libraries --root "$node_root" "${node_arguments[@]}"
