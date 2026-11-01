#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "${1:-}" == --help || "${1:-}" == -h || $# -eq 0 ]]; then
  echo 'Usage: state-transition.sh <inspect|prepare>'
  echo 'Inspect legacy-state fences without writes, or explicitly prepare a persistent fence.'
  echo 'Neither operation moves state, rewrites approvals, adopts installations or clears a fence.'
  exit 0
fi
[[ $# -eq 1 && ( "$1" == inspect || "$1" == prepare ) ]] || { echo 'Use inspect or prepare; no adoption or force option is available.' >&2; exit 1; }
source "$script_dir/lib/memory-common.sh"
hephaera_resolve_paths
python_bin="$(command -v python3 2>/dev/null || command -v python 2>/dev/null || true)"
[[ -n "$python_bin" ]] || { echo 'Existing Python 3.9+ is required; no software was installed.' >&2; exit 1; }
exec "$python_bin" -B -X utf8 "$script_dir/lib/state_transition.py" "$1" --root "$HEPHAERA_PROJECT_ROOT_RESOLVED"
