#!/usr/bin/env bash
set -euo pipefail
cd ..
msg="${1:-}"
if [[ -z "$msg" ]]; then
  echo 'Usage: ./commands/git-commit.sh "type(scope): summary"'
  exit 1
fi
git add -A
git commit -m "$msg"
