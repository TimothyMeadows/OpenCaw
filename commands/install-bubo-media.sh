#!/usr/bin/env bash
set -euo pipefail
command_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
[[ $# -gt 0 ]] || set -- --help
exec bash "$command_dir/bubo-media.sh" setup "$@"
