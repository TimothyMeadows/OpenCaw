#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
baseline="$(cd "$script_dir/.." && pwd)"
configuration="${1:-Release}"
[[ "$configuration" == Release || "$configuration" == Debug ]] || { echo 'Use Release or Debug.' >&2; exit 1; }
node "$script_dir/lib/bubo-runtime.cjs" resource proof-to-model/manifest.schema.json >/dev/null
command -v dotnet >/dev/null 2>&1 || { echo 'An existing .NET 10 SDK is required for this explicit build; no software was installed.' >&2; exit 1; }
case "${OSTYPE:-}" in
  msys*|cygwin*)
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$baseline/runtime/bubo/scripts/build.ps1" -Configuration "$configuration"
    ;;
  *) bash "$baseline/runtime/bubo/scripts/build.sh" "$configuration" ;;
esac
node "$script_dir/lib/bubo-runtime.cjs" verify
