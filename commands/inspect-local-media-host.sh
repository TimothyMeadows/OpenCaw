#!/usr/bin/env bash
set -euo pipefail
command_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || { echo 'Node.js is required for structured host inspection; nothing was installed.' >&2; exit 1; }
node_script="$command_dir/lib/bubo-media-host.cjs"
if [[ "$node_bin" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then node_script="$(wslpath -w "$node_script")"; fi
for argument in "$@"; do
  if [[ "$argument" == --help || "$argument" == -h ]]; then exec "$node_bin" "$node_script" --help; fi
done
arguments=("$@")
root_arg=''
for ((index=0; index<${#arguments[@]}; index++)); do
  if [[ "${arguments[$index]}" == --root ]]; then
    [[ $((index+1)) -lt ${#arguments[@]} && -z "$root_arg" ]] || { echo 'Missing or duplicate --root.' >&2; exit 1; }
    root_arg="${arguments[$((index+1))]}"
  fi
done
if [[ -n "$root_arg" ]]; then export HEPHAERA_PROJECT_ROOT="$root_arg"; fi
source "$command_dir/lib/memory-common.sh"
hephaera_resolve_paths
if [[ -z "$root_arg" ]]; then set -- "$@" --root "$HEPHAERA_PROJECT_ROOT_RESOLVED"; fi
exec "$node_bin" "$node_script" "$@"
