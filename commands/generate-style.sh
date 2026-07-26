#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/generate-style.sh [--inline] "<STYLE1>" ["STYLE2" ...]

Defaults to concise link-based output in ../STYLE.md.
Use --inline to embed full style template contents.
EOF
}

mode='link'
styles=()

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
        styles+=("$1")
        shift
      done
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      styles+=("$1")
      shift
      ;;
  esac
done

if [[ "${#styles[@]}" -eq 0 ]]; then
  usage >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/memory-common.sh"
opencaw_resolve_paths
opencaw_root="$OPENCAW_ROOT"
host_root="$OPENCAW_PROJECT_ROOT_RESOLVED"
mount_dir_name="$(basename "$opencaw_root")"
if [[ "$opencaw_root" == "$host_root" ]]; then mount_path_from_host='.'; else mount_path_from_host="./${mount_dir_name}"; fi
style_target="$host_root/STYLE.md"

selected=()
for name in "${styles[@]}"; do
  normalized_name="${name//-/_}"
  normalized_name="${normalized_name// /_}"
  upper_name="${normalized_name^^}"
  template_path="$opencaw_root/.styles/${upper_name}.md"
  if [[ ! -f "$template_path" ]]; then
    echo "Missing style template: $template_path" >&2
    exit 1
  fi
  selected+=("$upper_name")
done

{
  echo "# STYLE.md"
  echo
  echo "This file is the canonical art style contract for this repository."
  echo
  echo "Generated from OpenCaw style templates:"
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
      echo "Read \`${mount_path_from_host}/.styles/${name}.md\` instructions"
    done
    echo
    echo "Add repository-specific art style instructions below these read directives."
  else
    echo "## Inlined Templates"
    echo
    for name in "${selected[@]}"; do
      template_path="$opencaw_root/.styles/${name}.md"
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
} > "$style_target"

echo "Wrote $style_target"
if [[ "$mode" == 'link' ]]; then
  echo "Mode: link (default)."
else
  echo "Mode: inline."
fi
