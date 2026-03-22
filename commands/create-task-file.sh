#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/create-task-file.sh "<unique_task_name>" ["Task Title"] [--no-issue]
EOF
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
task_name=""
title=""
create_issue=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-issue)
      create_issue=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -z "$task_name" ]]; then
        task_name="$1"
      elif [[ -z "$title" ]]; then
        title="$1"
      else
        usage >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$task_name" ]]; then
  usage >&2
  exit 1
fi

if [[ -z "$title" ]]; then
  title="$task_name"
fi

mkdir -p "../.ai/tasks/$task_name"
target="../.ai/tasks/$task_name/TASK.md"
created=0

if [[ ! -f "$target" ]]; then
  cat > "$target" <<EOF
# $title

## Goal

## Scope

## Assumptions

## Work Instructions

## Verification

## Review

## Issue
EOF
  created=1
fi

if [[ $create_issue -eq 1 ]]; then
  issue_url="$(bash "$script_dir/create-task-issue.sh" "$task_name" "$title")"
  echo "Issue created/linked: $issue_url"
fi

if [[ $created -eq 0 ]]; then
  echo "$target already exists"
fi

echo "$target"
