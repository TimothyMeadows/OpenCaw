#!/usr/bin/env bash
set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo 'Usage: ./commands/generate-architecture.sh "<TEMPLATE1>" ["TEMPLATE2" ...]'
  exit 1
fi

arch_target="../ARCHITECTURE.md"

{
  echo "# ARCHITECTURE.md"
  echo
  echo "This file is the canonical architecture contract for this repository."
  echo
  echo "Generated from OpenCaw architecture templates:"
  for name in "$@"; do
    echo "- ${name^^}"
  done
  echo
  echo "---"
  echo
  for name in "$@"; do
    template="./.architecture/${name^^}.md"
    if [[ ! -f "$template" ]]; then
      echo "Missing architecture template: $template" >&2
      exit 1
    fi
    echo "<!-- BEGIN TEMPLATE: ${name^^} -->"
    echo
    cat "$template"
    echo
    echo "<!-- END TEMPLATE: ${name^^} -->"
    echo
    echo "---"
    echo
  done
} > "$arch_target"

echo "Wrote $arch_target"
