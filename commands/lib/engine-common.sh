#!/usr/bin/env bash
# Shared entrypoint; project root resolution stays with the canonical memory layer.
engine_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$engine_lib_dir/memory-common.sh"
engine_run() {
  opencaw_resolve_paths
  local node_bin cli project
  node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
  [[ -n "$node_bin" ]] || { echo 'Node.js is required for engine contracts; nothing was installed.' >&2; return 1; }
  cli="$engine_lib_dir/engine-contract.cjs"
  project="$OPENCAW_PROJECT_ROOT_RESOLVED"
  if [[ "$node_bin" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then
    cli="$(wslpath -w "$cli")"
    project="$(wslpath -w "$project")"
  fi
  "$node_bin" "$cli" "$1" "$project" "${@:2}"
}
