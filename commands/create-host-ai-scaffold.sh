#!/usr/bin/env bash
set -euo pipefail

mkdir -p ../.ai/FRAGMENTS ../.ai/LEARNINGS ../.ai/tasks ../.ai/archive/tasks ../.ai/archive/context-snapshots ../.ai/reports

[[ -f ../.ai/MEMORY.md ]] || printf "# Project Memory\n\n" > ../.ai/MEMORY.md
[[ -f ../.ai/RULES.md ]] || printf "# Rules\n\n" > ../.ai/RULES.md
[[ -f ../.ai/DEBUG.md ]] || printf "# Debug History\n\n" > ../.ai/DEBUG.md
[[ -f ../.ai/FRAGMENTS/repo-map.md ]] || printf "# Repository Map\n\n" > ../.ai/FRAGMENTS/repo-map.md
[[ -f ../.ai/FRAGMENTS/conventions.md ]] || printf "# Conventions\n\n" > ../.ai/FRAGMENTS/conventions.md
[[ -f ../.ai/FRAGMENTS/gotchas.md ]] || printf "# Gotchas\n\n" > ../.ai/FRAGMENTS/gotchas.md
[[ -f ../.ai/LEARNINGS/workflows.md ]] || printf "# Workflows\n\n" > ../.ai/LEARNINGS/workflows.md
[[ -f ../.ai/LEARNINGS/bugs.md ]] || printf "# Bug Patterns\n\n" > ../.ai/LEARNINGS/bugs.md
mkdir -p ../.ai/tasks/example-task

if [[ ! -f ../.ai/tasks/TODO.md ]]; then
  cat > ../.ai/tasks/TODO.md <<'EOF'
# TODO

1. [ ] Example first task (`.ai/tasks/example-task/TASK.md`)
EOF
fi

[[ -f ../.ai/tasks/example-task/TASK.md ]] || cat > ../.ai/tasks/example-task/TASK.md <<'EOF'
# Example first task

## Goal

## Scope

## Assumptions

## Work Instructions

## Verification

## Review
EOF
