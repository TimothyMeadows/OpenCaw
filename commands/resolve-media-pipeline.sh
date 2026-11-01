#!/usr/bin/env bash
set -euo pipefail
command_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || { echo 'Node.js is required for media pipeline contracts; nothing was installed.' >&2; exit 1; }
node_script="$command_dir/lib/media-pipeline-contract.cjs"
if [[ "$node_bin" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then node_script="$(wslpath -w "$node_script")"; fi
for argument in "$@"; do
  if [[ "$argument" == --help || "$argument" == -h ]]; then exec "$node_bin" "$node_script" resolve --help; fi
done
has_root=false
for argument in "$@"; do [[ "$argument" != --root ]] || has_root=true; done
if [[ "$has_root" == false ]]; then
  source "$command_dir/lib/memory-common.sh"
  hephaera_resolve_paths
  set -- "$@" --root "$HEPHAERA_PROJECT_ROOT_RESOLVED"
fi
exec "$node_bin" "$node_script" resolve "$@"
