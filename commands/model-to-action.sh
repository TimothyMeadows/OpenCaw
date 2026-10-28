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
command -v dotnet >/dev/null 2>&1 || { echo 'MODEL_TO_ACTION requires the existing .NET10 SDK; nothing was installed.' >&2; exit 1; }
exec dotnet run --project "$command_dir/lib/model-to-action/ModelToAction.csproj" --no-launch-profile -- "$@" --baseline-root "$command_dir/.."
