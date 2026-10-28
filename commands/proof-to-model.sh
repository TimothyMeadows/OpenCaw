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
  opencaw_resolve_paths
  set -- "$@" --root "$OPENCAW_PROJECT_ROOT_RESOLVED"
fi
if ! command -v dotnet >/dev/null 2>&1; then
  printf '%s\n' 'PROOF_TO_MODEL requires the .NET 10 SDK. No software was installed.' >&2
  exit 1
fi
exec dotnet run --project "$command_dir/lib/proof-to-model/ProofToModel.csproj" --no-launch-profile -- "$@" --baseline-root "$command_dir/.."
