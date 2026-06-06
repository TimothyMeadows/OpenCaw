#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/validate-style-contract.sh [STYLE.md]

Validates that a host STYLE.md references existing OpenCaw .styles templates.
Defaults to ../STYLE.md when run from the mounted OpenCaw directory.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
opencaw_root="$(cd "$script_dir/.." && pwd)"
host_root="$(cd "$opencaw_root/.." && pwd)"
styles_dir="$opencaw_root/.styles"
index_file="$styles_dir/INDEX.md"
style_file="${1:-$host_root/STYLE.md}"

if [[ ! -f "$style_file" ]]; then
  echo "Missing STYLE.md: $style_file" >&2
  exit 1
fi

if [[ ! -d "$styles_dir" ]]; then
  echo "Missing styles directory: $styles_dir" >&2
  exit 1
fi

if [[ ! -f "$index_file" ]]; then
  echo "Missing styles index: $index_file" >&2
  exit 1
fi

status=0

if ! grep -q '^# STYLE\.md$' "$style_file"; then
  echo "STYLE.md is missing the expected top-level heading." >&2
  status=1
fi

mapfile -t selected_styles < <(
  awk '
    /^Generated from OpenCaw style templates:/ { in_list=1; next }
    /^---$/ { in_list=0 }
    in_list && /^- / {
      sub(/^- /, "")
      gsub(/\r$/, "")
      print
    }
  ' "$style_file"
)

if [[ ${#selected_styles[@]} -eq 0 ]]; then
  echo "STYLE.md does not list any generated OpenCaw style templates." >&2
  status=1
fi

for style_name in "${selected_styles[@]}"; do
  template_path="$styles_dir/${style_name}.md"
  if [[ ! "$style_name" =~ ^[A-Z0-9]+(_[A-Z0-9]+)*$ ]]; then
    echo "Invalid style template name in STYLE.md: $style_name" >&2
    status=1
    continue
  fi

  if [[ ! -f "$template_path" ]]; then
    echo "Missing referenced style template: $template_path" >&2
    status=1
  fi

  if ! grep -q -- "- ${style_name}" "$index_file"; then
    echo "Referenced style template is not listed in .styles/INDEX.md: $style_name" >&2
    status=1
  fi
done

if grep -q '^This document intentionally stays concise by referencing selected templates\.$' "$style_file"; then
  for style_name in "${selected_styles[@]}"; do
    if ! grep -q "\.styles/${style_name}\.md" "$style_file"; then
      echo "Link-mode STYLE.md is missing a read directive for: $style_name" >&2
      status=1
    fi
  done
fi

mapfile -t read_directives < <(
  grep -Eo '\.styles/[A-Z0-9_]+\.md' "$style_file" | sed 's#^.styles/##; s#\.md$##' | sort -u
)

for directive_style in "${read_directives[@]}"; do
  if [[ ! -f "$styles_dir/${directive_style}.md" ]]; then
    echo "STYLE.md read directive points to a missing style template: $directive_style" >&2
    status=1
  fi
done

if [[ $status -eq 0 ]]; then
  echo "Style contract validation passed."
  printf 'Referenced styles:'
  for style_name in "${selected_styles[@]}"; do
    printf ' %s' "$style_name"
  done
  printf '\n'
fi

exit $status
