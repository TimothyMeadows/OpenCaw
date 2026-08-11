#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/list-external-asset-libraries.sh [--style STYLE.md] [--json]

Lists optional read-only external asset libraries configured in STYLE.md.
This command does not access or load library contents.
EOF
}

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
style_file="${style_file:-$OPENCAW_PROJECT_ROOT_RESOLVED/STYLE.md}"
[[ -f "$style_file" ]] || { echo "Missing STYLE.md: $style_file" >&2; exit 1; }
bash "$script_dir/validate-style-contract.sh" "$style_file" >/dev/null

ids=()
paths=()
while IFS=$'\t' read -r id library_path; do
  [[ -n "$id" ]] || continue
  ids+=("$id")
  paths+=("$library_path")
done < <(external_asset_library_entries "$style_file")

if [[ $json -eq 1 ]]; then
  node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
  [[ -n "$node_bin" ]] || { echo 'Node.js is required for JSON output.' >&2; exit 1; }
  "$node_bin" - "${ids[@]}" -- "${paths[@]}" <<'NODE'
const values=process.argv.slice(2); const split=values.indexOf('--');
const ids=values.slice(0,split); const paths=values.slice(split+1);
process.stdout.write(JSON.stringify(ids.map((id,index)=>({id,path:paths[index],readOnly:true})),null,2)+'\n');
NODE
else
  echo "EXTERNAL_ASSET_LIBRARY_COUNT=${#ids[@]}"
  for index in "${!ids[@]}"; do printf '%s\t%s\n' "${ids[$index]}" "${paths[$index]}"; done
fi
