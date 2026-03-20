#!/usr/bin/env bash
set -euo pipefail

task_name="${1:-}"
title="${2:-}"

if [[ -z "$task_name" ]]; then
  echo 'Usage: ./commands/create-task-file.sh "<unique_task_name>" ["Task Title"]'
  exit 1
fi

mkdir -p "../.ai/tasks/$task_name"
target="../.ai/tasks/$task_name/TASK.md"

if [[ -f "$target" ]]; then
  echo "$target already exists"
  exit 0
fi

if [[ -z "$title" ]]; then
  title="$task_name"
fi

cat > "$target" <<EOF
# $title

## Goal

## Scope

## Assumptions

## Work Instructions

## Verification

## Review
EOF
echo "$target"
