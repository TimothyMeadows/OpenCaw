#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/inspect-external-asset-library.sh LIBRARY_ID [--style STYLE.md] [--json]

Inventories supported 3D model, rig, and animation files without loading asset contents.
Symbolic links are skipped and never followed.
EOF
}

if [[ "${1:-}" == '-h' || "${1:-}" == '--help' ]]; then usage; exit 0; fi
[[ $# -ge 1 ]] || { usage >&2; exit 1; }
library_id="$1"
shift
style_file=''
json=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --style) [[ $# -ge 2 ]] || { echo '--style requires a path.' >&2; exit 1; }; style_file="$2"; shift 2 ;;
    --json) json=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/memory-common.sh"
source "$script_dir/lib/external-asset-library-common.sh"
opencaw_resolve_paths
external_asset_library_validate_id "$library_id"
style_file="${style_file:-$OPENCAW_PROJECT_ROOT_RESOLVED/STYLE.md}"
[[ -f "$style_file" ]] || { echo "Missing STYLE.md: $style_file" >&2; exit 1; }
bash "$script_dir/validate-style-contract.sh" "$style_file" >/dev/null
library_path="$(external_asset_library_get_path "$style_file" "$library_id")"
node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || { echo 'Node.js is required to inspect external asset libraries.' >&2; exit 1; }
library_for_node="$(external_asset_library_path_for_node "$library_path" "$node_bin")"
engine_for_node="$(external_asset_library_path_for_node "$script_dir/lib/external-asset-library.js" "$node_bin")"
format='text'
[[ $json -eq 0 ]] || format='json'
"$node_bin" "$engine_for_node" inventory "$library_for_node" "$library_id" "$format"
