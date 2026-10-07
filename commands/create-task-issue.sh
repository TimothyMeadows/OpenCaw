#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v python3 >/dev/null 2>&1; then
  echo 'Python 3.9+ is required for task execution commands; no software was installed.' >&2
  exit 1
fi
# Help must work even outside an initialized host repository.
if [[ "${1:-}" == '-h' || "${1:-}" == '--help' ]]; then
  exec python3 "$script_dir/lib/task-execution.py" --root . create-issue --help
fi
source "$script_dir/lib/brainstorm-common.sh"
brainstorm_require_delivery_creation_allowed 'Task issue creation'
exec python3 "$script_dir/lib/task-execution.py" --root "$OPENCAW_PROJECT_ROOT_RESOLVED" create-issue "$@"
