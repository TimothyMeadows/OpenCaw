#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/record-code-character-calibration.sh PROFILE.json --gate ID --passing REPORT.json --failing REPORT.json [options]

Transactionally freezes one machine gate's deterministic passing and focused failing fixture reports.
Repeat --passing or --failing to register multiple independently stored calibration reports.
EOF
}

[[ $# -gt 0 ]] || { usage >&2; exit 1; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/memory-common.sh"
opencaw_resolve_paths
node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || { echo "Node.js is required for code-character calibration." >&2; exit 1; }
node_root="$OPENCAW_PROJECT_ROOT_RESOLVED"
node_cli="$script_dir/lib/code-character-cli.cjs"
if [[ "$node_bin" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then
  node_root="$(wslpath -w "$node_root")"
  node_cli="$(wslpath -w "$node_cli")"
fi
"$node_bin" "$node_cli" calibrate "$node_root" "$@"
