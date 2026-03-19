#!/usr/bin/env bash
set -euo pipefail
cd ..
if [[ $# -eq 0 ]]; then
  dotnet test
else
  dotnet test "$@"
fi
