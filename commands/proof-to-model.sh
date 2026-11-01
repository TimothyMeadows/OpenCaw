#!/usr/bin/env bash
set -euo pipefail
command_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ $# -eq 0 ]]; then set -- --help; fi
has_root=false
is_help=false
for argument in "$@"; do
  [[ "$argument" != '--root' ]] || has_root=true
  [[ "$argument" != '--help' && "$argument" != 'help' ]] || is_help=true
done
if [[ "$has_root" == false && "$is_help" == false ]]; then
  source "$command_dir/lib/memory-common.sh"
  hephaera_resolve_paths
  set -- "$@" --root "$HEPHAERA_PROJECT_ROOT_RESOLVED"
fi
exec node "$command_dir/lib/bubo-host-adapter.cjs" proof-to-model "$@"
