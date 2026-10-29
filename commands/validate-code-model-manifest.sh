#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/validate-code-model-manifest.sh [--strict|--complete] MANIFEST.json

Base validation checks contract integrity, paths, hashes, pass order, and limits.
--strict also rejects placeholders and requires cleanup ownership.
--complete additionally checks passed reviews and the authored host source.
EOF
}

[[ $# -gt 0 ]] || { usage >&2; exit 1; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/memory-common.sh"
opencaw_resolve_paths
node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || { echo "Node.js is required for code-model validation." >&2; exit 1; }
node_root="$OPENCAW_PROJECT_ROOT_RESOLVED"
node_cli="$script_dir/lib/code-model-cli.cjs"
if [[ "$node_bin" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then node_root="$(wslpath -w "$node_root")"; node_cli="$(wslpath -w "$node_cli")"; fi
"$node_bin" "$node_cli" validate "$node_root" "$@"
