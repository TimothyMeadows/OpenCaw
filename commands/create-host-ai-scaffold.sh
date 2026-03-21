#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
opencaw_root="$(cd "$script_dir/.." && pwd)"
host_root="$(cd "$opencaw_root/.." && pwd)"
host_ai_dir="$host_root/.ai"
host_agents_file="$host_root/AGENTS.md"

ensure_file() {
  local path="$1"
  local title="$2"
  [[ -f "$path" ]] || printf "%s\n\n" "$title" > "$path"
}

ensure_host_agents_bootstrap() {
  local mount_dir_name fallback_mount_path
  mount_dir_name="$(basename "$opencaw_root")"
  fallback_mount_path="./${mount_dir_name}/AGENTS.md"

  local bootstrap_block
  bootstrap_block="$(cat <<EOF
<!-- OPENCAW_BOOTSTRAP_START -->
## OpenCaw Bootstrap (Managed)

Load and follow OpenCaw baseline instructions before applying repository-local instructions.

Preferred baseline locations:
- \`./.codex/AGENTS.md\`
- \`./.cursor/AGENTS.md\`
- \`./.claude/AGENTS.md\`

Fallback for this repository:
- \`${fallback_mount_path}\`

If one of the paths exists, treat that file as the OpenCaw baseline source for the session.
<!-- OPENCAW_BOOTSTRAP_END -->
EOF
)"

  if [[ ! -f "$host_agents_file" ]]; then
    cat > "$host_agents_file" <<EOF
# AGENTS.md

$bootstrap_block
EOF
    echo "Created host AGENTS bootstrap: $host_agents_file"
    return
  fi

  if grep -Fq "OPENCAW_BOOTSTRAP_START" "$host_agents_file" \
    || grep -Fq "$fallback_mount_path" "$host_agents_file"; then
    echo "Host AGENTS bootstrap already present: $host_agents_file"
    return
  fi

  printf "\n\n%s\n" "$bootstrap_block" >> "$host_agents_file"
  echo "Appended OpenCaw bootstrap to existing host AGENTS: $host_agents_file"
}

ensure_host_agents_bootstrap

mkdir -p \
  "$host_ai_dir/FRAGMENTS" \
  "$host_ai_dir/LEARNINGS" \
  "$host_ai_dir/tasks" \
  "$host_ai_dir/archive/tasks" \
  "$host_ai_dir/archive/context-snapshots" \
  "$host_ai_dir/reports"

ensure_file "$host_ai_dir/MEMORY.md" "# Project Memory"
ensure_file "$host_ai_dir/RULES.md" "# Rules"
ensure_file "$host_ai_dir/DEBUG.md" "# Debug History"
ensure_file "$host_ai_dir/FRAGMENTS/repo-map.md" "# Repository Map"
ensure_file "$host_ai_dir/FRAGMENTS/conventions.md" "# Conventions"
ensure_file "$host_ai_dir/FRAGMENTS/gotchas.md" "# Gotchas"
ensure_file "$host_ai_dir/LEARNINGS/workflows.md" "# Workflows"
ensure_file "$host_ai_dir/LEARNINGS/bugs.md" "# Bug Patterns"

mkdir -p "$host_ai_dir/tasks/example-task"

if [[ ! -f "$host_ai_dir/tasks/TODO.md" ]]; then
  cat > "$host_ai_dir/tasks/TODO.md" <<'EOF'
# TODO

1. [ ] Example first task (`.ai/tasks/example-task/TASK.md`)
EOF
fi

[[ -f "$host_ai_dir/tasks/example-task/TASK.md" ]] || cat > "$host_ai_dir/tasks/example-task/TASK.md" <<'EOF'
# Example first task

## Goal

## Scope

## Assumptions

## Work Instructions

## Verification

## Review
EOF
