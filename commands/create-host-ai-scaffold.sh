#!/usr/bin/env bash
set -euo pipefail

mkdir -p ../.ai/FRAGMENTS ../.ai/LEARNINGS ../.ai/TASKS/active ../.ai/TASKS/completed ../tasks

[[ -f ../.ai/MEMORY.md ]] || printf "# Project Memory\n\n" > ../.ai/MEMORY.md
[[ -f ../.ai/RULES.md ]] || printf "# Rules\n\n" > ../.ai/RULES.md
[[ -f ../.ai/DEBUG.md ]] || printf "# Debug History\n\n" > ../.ai/DEBUG.md
[[ -f ../.ai/FRAGMENTS/repo-map.md ]] || printf "# Repository Map\n\n" > ../.ai/FRAGMENTS/repo-map.md
[[ -f ../.ai/FRAGMENTS/conventions.md ]] || printf "# Conventions\n\n" > ../.ai/FRAGMENTS/conventions.md
[[ -f ../.ai/FRAGMENTS/gotchas.md ]] || printf "# Gotchas\n\n" > ../.ai/FRAGMENTS/gotchas.md
[[ -f ../.ai/LEARNINGS/workflows.md ]] || printf "# Workflows\n\n" > ../.ai/LEARNINGS/workflows.md
[[ -f ../.ai/LEARNINGS/bugs.md ]] || printf "# Bug Patterns\n\n" > ../.ai/LEARNINGS/bugs.md
[[ -f ../tasks/TODO.md ]] || printf "# TODO\n\n1. [ ] Example first task (`tasks/example-task/TASK.md`)\n" > ../tasks/TODO.md
