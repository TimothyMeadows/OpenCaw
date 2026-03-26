#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/generate-architecture.sh [--inline] "<TEMPLATE1>" ["TEMPLATE2" ...]

Defaults to concise link-based output in ../ARCHITECTURE.md.
Use --inline to embed full template contents.
EOF
}

mode='link'
templates=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --inline)
      mode='inline'
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        templates+=("$1")
        shift
      done
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      templates+=("$1")
      shift
      ;;
  esac
done

if [[ "${#templates[@]}" -eq 0 ]]; then
  usage >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
opencaw_root="$(cd "$script_dir/.." && pwd)"
host_root="$(cd "$opencaw_root/.." && pwd)"
mount_dir_name="$(basename "$opencaw_root")"
mount_path_from_host="./${mount_dir_name}"
arch_target="$host_root/ARCHITECTURE.md"

selected=()
for name in "${templates[@]}"; do
  normalized_name="${name//-/_}"
  normalized_name="${normalized_name// /_}"
  upper_name="${normalized_name^^}"
  template_path="$opencaw_root/.architecture/${upper_name}.md"
  if [[ ! -f "$template_path" ]]; then
    echo "Missing architecture template: $template_path" >&2
    exit 1
  fi
  selected+=("$upper_name")
done

{
  echo "# ARCHITECTURE.md"
  echo
  echo "This file is the canonical architecture contract for this repository."
  echo
  echo "Generated from OpenCaw architecture templates:"
  for name in "${selected[@]}"; do
    echo "- $name"
  done
  echo
  echo "---"
  echo

  if [[ "$mode" == 'link' ]]; then
    echo "This document intentionally stays concise by referencing selected templates."
    echo
    echo "## Read Template Instructions"
    echo
    for name in "${selected[@]}"; do
      echo "Read \`${mount_path_from_host}/.architecture/${name}.md\` instructions"
    done
    echo
    echo "Add repository-specific architecture instructions below these read directives."
  else
    echo "## Inlined Templates"
    echo
    for name in "${selected[@]}"; do
      template_path="$opencaw_root/.architecture/${name}.md"
      echo "<!-- BEGIN TEMPLATE: ${name} -->"
      echo
      cat "$template_path"
      echo
      echo "<!-- END TEMPLATE: ${name} -->"
      echo
      echo "---"
      echo
    done
  fi
} > "$arch_target"

echo "Wrote $arch_target"
if [[ "$mode" == 'link' ]]; then
  echo "Mode: link (default)."
else
  echo "Mode: inline."
fi
