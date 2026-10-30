#!/usr/bin/env bash
set -euo pipefail
command_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
[[ $# -gt 0 ]] || set -- --help
has_root=false
is_help=false
for argument in "$@"; do
  [[ "$argument" != --root ]] || has_root=true
  [[ "$argument" != --help && "$argument" != help ]] || is_help=true
done
if [[ "$has_root" == false && "$is_help" == false ]]; then
  source "$command_dir/lib/memory-common.sh"
  opencaw_resolve_paths
  set -- "$@" --root "$OPENCAW_PROJECT_ROOT_RESOLVED"
fi
node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || { echo 'Node.js is required for the Bubo host adapter; nothing was installed.' >&2; exit 1; }
node_script="$command_dir/lib/bubo-media-adapter.cjs"
if [[ "$node_bin" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then node_script="$(wslpath -w "$node_script")"; fi
exec "$node_bin" "$node_script" "$@"
