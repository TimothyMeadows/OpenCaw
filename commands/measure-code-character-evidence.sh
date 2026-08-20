#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./commands/measure-code-character-evidence.sh analyze PROFILE --measurements FILE --output FILE [--compare REPORT]
  ./commands/measure-code-character-evidence.sh capture PROFILE --adapter FILE --output-dir DIR [options]

Analyzes deterministic calibration observations or captures trusted machine evidence through a
host-installed Three.js and Playwright Chromium browser. Installs nothing and never disables the browser sandbox.

Capture options:
  --view VIEW             Repeatable; must include every profile-required view
  --compare REPORT        Add a revision comparison against an earlier evidence report
  --viewport-width N      Browser viewport width (default: 800)
  --viewport-height N     Browser viewport height (default: 800)
  --pixel-ratio N         Browser device pixel ratio (default: 1)
EOF
}

[[ $# -gt 0 ]] || { usage >&2; exit 1; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/memory-common.sh"
opencaw_resolve_paths
node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || { echo "Node.js is required for code-character evidence." >&2; exit 1; }
node_root="$OPENCAW_PROJECT_ROOT_RESOLVED"
node_cli="$script_dir/lib/code-character-evidence-cli.cjs"
if [[ "$node_bin" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then
  node_root="$(wslpath -w "$node_root")"
  node_cli="$(wslpath -w "$node_cli")"
fi
"$node_bin" "$node_cli" "$1" "$node_root" "${@:2}"
