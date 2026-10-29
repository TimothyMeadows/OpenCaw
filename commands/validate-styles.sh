#!/usr/bin/env bash
set -euo pipefail

styles_dir="./.styles"
index_file="$styles_dir/INDEX.md"

if [[ ! -d "$styles_dir" ]]; then
  echo "Missing styles directory: $styles_dir" >&2
  exit 1
fi

if [[ ! -f "$index_file" ]]; then
  echo "Missing styles index: $index_file" >&2
  exit 1
fi

status=0
style_count=0

while IFS= read -r -d '' style_md; do
  file_name="$(basename "$style_md")"

  if [[ "$file_name" == "INDEX.md" ]]; then
    continue
  fi

  style_count=$((style_count + 1))
  style_name="${file_name%.md}"

  if [[ ! "$file_name" =~ ^[A-Z0-9]+(_[A-Z0-9]+)*\.md$ ]]; then
    echo "Invalid style template name: $file_name" >&2
    status=1
  fi

  if ! grep -q "^# ${style_name}\\.md" "$style_md"; then
    echo "Missing matching top-level heading in $style_md" >&2
    status=1
  fi

  for section in "## Intent" "## Production Rules" "## Acceptance Checks" "## Role Fit"; do
    if ! grep -q "^${section}" "$style_md"; then
      echo "Missing required section ($section) in $style_md" >&2
      status=1
    fi
  done

  if ! grep -q -- "- ${style_name}" "$index_file"; then
    echo "Style template not listed in INDEX.md: $style_name" >&2
    status=1
  fi
done < <(find "$styles_dir" -maxdepth 1 -type f -name "*.md" -print0)

if [[ $style_count -eq 0 ]]; then
  echo "No style templates found under $styles_dir." >&2
  status=1
fi

if [[ $status -eq 0 ]]; then
  echo "Styles validation passed."
fi

exit $status
