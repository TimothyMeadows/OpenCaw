#!/usr/bin/env bash
set -euo pipefail

target_dir="${1:-.}"

if [[ ! -d "$target_dir" ]]; then
  echo "Target directory not found: $target_dir" >&2
  exit 1
fi

mapfile -d '' svg_files < <(find "$target_dir" -type f -name "*.svg" -print0)

if [[ ${#svg_files[@]} -eq 0 ]]; then
  echo "No SVG files found under: $target_dir"
  echo "Nothing to validate."
  exit 0
fi

total=0
failures=0

for svg in "${svg_files[@]}"; do
  total=$((total + 1))
  file_failed=0

  if ! grep -qi '<svg[^>]*viewBox=' "$svg"; then
    echo "FAIL: missing viewBox -> $svg" >&2
    file_failed=1
  fi

  if grep -qi '<image[[:space:]>]' "$svg"; then
    echo "FAIL: raster image tag found (<image>) -> $svg" >&2
    file_failed=1
  fi

  if grep -qi 'data:image/' "$svg"; then
    echo "FAIL: raster data URI found (data:image/) -> $svg" >&2
    file_failed=1
  fi

  if [[ $file_failed -eq 0 ]]; then
    echo "PASS: $svg"
  else
    failures=$((failures + 1))
  fi
done

echo "Checked SVG files: $total"
echo "Failures: $failures"

if [[ $failures -gt 0 ]]; then
  echo "Vector validation failed." >&2
  exit 1
fi

echo "Vector validation passed."
