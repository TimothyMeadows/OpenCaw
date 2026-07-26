#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/memory-common.sh"

opencaw_resolve_paths

echo "OPENCAW_PROJECT_ROOT=$OPENCAW_PROJECT_ROOT_RESOLVED"
echo "OPENCAW_PROJECT_AI_DIR=$OPENCAW_PROJECT_AI_DIR"
echo "SYSTEM_MEMORY_FILE=$OPENCAW_SYSTEM_MEMORY_FILE"
echo "PROJECT_MEMORY_FILE=$OPENCAW_PROJECT_MEMORY_FILE"
echo "REPO_MAP_FILE=$OPENCAW_REPO_MAP_FILE"
