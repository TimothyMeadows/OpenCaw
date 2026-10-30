#!/usr/bin/env bash
set -euo pipefail
command_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || { echo 'Node.js is required for media production commands; nothing was installed.' >&2; exit 1; }
node_script="$command_dir/lib/media-pipeline-command.cjs"
if [[ "$node_bin" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then node_script="$(wslpath -w "$node_script")"; fi
is_help=false
has_root=false
for argument in "$@"; do
  [[ "$argument" != --help && "$argument" != -h && "$argument" != help ]] || is_help=true
  [[ "$argument" != --root ]] || has_root=true
done
if [[ "$is_help" == false && "$has_root" == false && $# -gt 0 ]]; then
  source "$command_dir/lib/memory-common.sh"
  opencaw_resolve_paths
  set -- "$@" --root "$OPENCAW_PROJECT_ROOT_RESOLVED"
fi
exec "$node_bin" "$node_script" AUDIO "$@"
