#!/usr/bin/env bash
set -euo pipefail
command_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
[[ $# -gt 0 ]] || set -- --help
source "$command_dir/lib/memory-common.sh"
hephaera_resolve_paths
node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || { echo 'Node.js is required for Three.js particle inspection; nothing was installed.' >&2; exit 1; }
node_script="$command_dir/lib/threejs-particles.cjs"
project="$HEPHAERA_PROJECT_ROOT_RESOLVED"
if [[ "$node_bin" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then
  node_script="$(wslpath -w "$node_script")"
  project="$(wslpath -w "$project")"
fi
exec "$node_bin" "$node_script" "$@" --root "$project"
