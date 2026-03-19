#!/usr/bin/env bash
set -euo pipefail

cd ..

if [[ $# -eq 0 ]]; then
  echo "Listing outdated NuGet packages for the current solution context..."
  dotnet list package --outdated
else
  target="$1"
  shift || true
  echo "Listing outdated NuGet packages for: $target"
  dotnet list "$target" package --outdated "$@"
fi
