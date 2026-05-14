#!/usr/bin/env bash
set -euo pipefail

host_root="${OPENCAW_HOST_ROOT:-$(pwd)}"
cd "$host_root"

if ! command -v node >/dev/null 2>&1; then
  echo "Node.js is required to install Playwright browsers." >&2
  exit 1
fi

if [[ ! -f package.json ]]; then
  echo "No package.json found in $host_root. Run this from a Node/Playwright host repository or set OPENCAW_HOST_ROOT." >&2
  exit 1
fi

args=("$@")
if [[ ${#args[@]} -eq 0 ]]; then
  args=("install")
else
  args=("install" "${args[@]}")
fi

echo "Running: npx playwright ${args[*]}"
npx playwright "${args[@]}"
