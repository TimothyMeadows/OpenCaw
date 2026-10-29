#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
baseline="$(cd "$script_dir/.." && pwd)"
[[ $# -eq 0 ]] || { echo 'Usage: initialize-bubo-runtime.sh (recorded commit only; no --remote).' >&2; exit 1; }
git -C "$baseline" submodule update --init --recursive --checkout runtime/bubo
node "$script_dir/lib/bubo-runtime.cjs" resource proof-to-model/manifest.schema.json >/dev/null
echo 'Initialized the recorded Bubo revision. Build explicitly with build-bubo-runtime.sh; no native tools/models were installed.'
