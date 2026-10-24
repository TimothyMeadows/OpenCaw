#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || { echo 'Node.js is required for Unity capability verification.' >&2; exit 1; }
script_path="$repo_root/tests/test-unity-capabilities.cjs"
if [[ "$node_bin" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then
  script_path="$(wslpath -w "$script_path")"
fi
"$node_bin" "$script_path" "$@"
