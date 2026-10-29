#!/usr/bin/env bash
set -euo pipefail
command_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec node "$command_dir/lib/bubo-inspection-adapter.cjs" "$@"
