#!/usr/bin/env bash
set -euo pipefail

skills_dir="./skills"
schema_file="./skills/SCHEMA.md"

if [[ ! -d "$skills_dir" ]]; then
  echo "Missing skills directory: $skills_dir" >&2
  exit 1
fi

if [[ ! -f "$schema_file" ]]; then
  echo "Missing skills schema: $schema_file" >&2
  exit 1
fi

status=0
skill_count=0

while IFS= read -r -d '' skill_md; do
  skill_count=$((skill_count + 1))
  skill_dir="$(basename "$(dirname "$skill_md")")"

  if [[ ! "$skill_dir" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
    echo "Invalid skill folder name: $skill_dir" >&2
    status=1
  fi

  if ! grep -q '^---' "$skill_md"; then
    echo "Missing metadata block in $skill_md" >&2
    status=1
  fi

  if ! grep -q '^name:[[:space:]]' "$skill_md"; then
    echo "Missing name field in $skill_md" >&2
    status=1
  else
    declared_name="$(grep '^name:[[:space:]]' "$skill_md" | head -n1 | sed 's/^name:[[:space:]]*//' | tr -d '\r')"
    if [[ "$declared_name" != "$skill_dir" ]]; then
      echo "Skill name mismatch in $skill_md (folder=$skill_dir, name=$declared_name)" >&2
      status=1
    fi
  fi

  if ! grep -q '^description:[[:space:]]' "$skill_md"; then
    echo "Missing description field in $skill_md" >&2
    status=1
  fi

  if ! grep -q '^## When to use' "$skill_md"; then
    echo "Missing '## When to use' in $skill_md" >&2
    status=1
  fi

done < <(find "$skills_dir" -mindepth 2 -maxdepth 2 -name SKILL.md -print0)

if [[ $skill_count -eq 0 ]]; then
  echo "No skills found below $skills_dir" >&2
  status=1
fi

if ! ./commands/validate-skill-safety.sh "$skills_dir"; then
  status=1
fi

if [[ $status -eq 0 ]]; then
  echo "Skills validation passed."
fi

exit $status
