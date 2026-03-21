#!/usr/bin/env bash
set -euo pipefail

status=0

files=(
  "./AGENTS.md"
  "./.roles/SCHEMA.md"
  "./skills/SCHEMA.md"
  "./commands/SCHEMA.md"
)

required_terms=(
  "GitHub"
  "GitHub Actions"
  "GCP"
  "Azure"
  "AWS"
)

for file in "${files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "Missing required file for cloud preference validation: $file" >&2
    status=1
    continue
  fi

  for term in "${required_terms[@]}"; do
    if ! grep -Fq "$term" "$file"; then
      echo "Missing required term '$term' in $file" >&2
      status=1
    fi
  done

  gcp_line="$(grep -n -m1 -E '\bGCP\b' "$file" | cut -d: -f1 || true)"
  azure_line="$(grep -n -m1 -E '\bAzure\b' "$file" | cut -d: -f1 || true)"
  aws_line="$(grep -n -m1 -E '\bAWS\b' "$file" | cut -d: -f1 || true)"

  if [[ -z "$gcp_line" || -z "$azure_line" || -z "$aws_line" ]]; then
    echo "Missing cloud ordering markers in $file" >&2
    status=1
    continue
  fi

  if ! [[ "$gcp_line" -lt "$azure_line" && "$azure_line" -lt "$aws_line" ]]; then
    echo "Cloud order violation in $file (expected GCP -> Azure -> AWS)" >&2
    status=1
  fi
done

if [[ "$status" -eq 0 ]]; then
  echo "Cloud preference validation passed."
fi

exit "$status"
