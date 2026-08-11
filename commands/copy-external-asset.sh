#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/copy-external-asset.sh LIBRARY_ID RELATIVE_ASSET_PATH [--style STYLE.md] [--evidence .ai/tasks/<task>/FILE.json]

Copies a configured read-only external asset file or bundle into:
  <project-root>/assets/models/<library-id>/<relative-asset-path>

The command never follows symbolic links or overwrites an existing destination.
EOF
}

if [[ "${1:-}" == '-h' || "${1:-}" == '--help' ]]; then usage; exit 0; fi
[[ $# -ge 2 ]] || { usage >&2; exit 1; }
library_id="$1"
asset_path="$2"
shift 2
style_file=''
evidence=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    --style) [[ $# -ge 2 ]] || { echo '--style requires a path.' >&2; exit 1; }; style_file="$2"; shift 2 ;;
    --evidence) [[ $# -ge 2 ]] || { echo '--evidence requires a path.' >&2; exit 1; }; evidence="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/memory-common.sh"
source "$script_dir/lib/external-asset-library-common.sh"
opencaw_resolve_paths
external_asset_library_validate_id "$library_id"
project_root="$OPENCAW_PROJECT_ROOT_RESOLVED"
style_file="${style_file:-$project_root/STYLE.md}"
[[ -f "$style_file" ]] || { echo "Missing STYLE.md: $style_file" >&2; exit 1; }
[[ ! -L "$style_file" ]] || { echo 'STYLE.md must not be a symbolic link.' >&2; exit 1; }
style_real="$(realpath "$style_file")"
case "$style_real" in "$project_root"/*) ;; *) echo 'STYLE.md must stay inside the resolved project root.' >&2; exit 1 ;; esac
bash "$script_dir/validate-style-contract.sh" "$style_file" >/dev/null
library_path="$(external_asset_library_get_path "$style_file" "$library_id")"
node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || { echo 'Node.js is required to copy external assets.' >&2; exit 1; }
library_for_node="$(external_asset_library_path_for_node "$library_path" "$node_bin")"
project_for_node="$(external_asset_library_path_for_node "$project_root" "$node_bin")"
engine_for_node="$(external_asset_library_path_for_node "$script_dir/lib/external-asset-library.js" "$node_bin")"
style_sha256="$(external_asset_library_sha256 "$style_file")"
evidence_for_node='-'
if [[ -n "$evidence" ]]; then
  [[ "$evidence" == /* || "$evidence" =~ ^[A-Za-z]:[\\/] ]] || evidence="$project_root/$evidence"
  evidence_for_node="$(external_asset_library_path_for_node "$evidence" "$node_bin")"
fi
"$node_bin" "$engine_for_node" copy "$library_for_node" "$project_for_node" "$library_id" "$asset_path" "$style_sha256" "$evidence_for_node"
