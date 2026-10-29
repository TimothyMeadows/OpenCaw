#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
bash "$repo_root/commands/test-bubo-runtime.sh" model-to-action
node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || { echo 'Node.js is required for action presentation contract tests.' >&2; exit 1; }
test_file="$repo_root/tests/test-model-action-engine.cjs"
if [[ "$node_bin" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then test_file="$(wslpath -w "$test_file")"; fi
"$node_bin" "$test_file"
