#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/memory-common.sh"
source "$script_dir/lib/platform-common.sh"
opencaw_resolve_paths

opencaw_root="$OPENCAW_ROOT"
host_root="$OPENCAW_PROJECT_ROOT_RESOLVED"
host_cache_dir="$OPENCAW_PROJECT_CACHE_DIR"
host_agents_file="$host_root/AGENTS.md"

ensure_file() {
  local path="$1"
  local title="$2"
  [[ -f "$path" ]] || printf "%s\n\n" "$title" > "$path"
}

ensure_host_agents_bootstrap() {
  if [[ "$host_root" == "$opencaw_root" ]]; then
    echo "Standalone maintainer checkout detected; baseline instructions are $host_agents_file"
    return
  fi

  local bootstrap_block
  bootstrap_block="$(cat <<'EOF'
<!-- OPENCAW_BOOTSTRAP_START -->
## OpenCaw Bootstrap (Managed)

Read and follow `./.opencaw/AGENTS.md` before repository-local instructions.
OpenCaw is installed only in `./.opencaw/`. Project-local durable memory, tasks,
workflow state and reports are stored only in `./.opencaw/.cache/`.
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

  if grep -Fq "OPENCAW_BOOTSTRAP_START" "$host_agents_file"; then
    echo "Host AGENTS bootstrap already present: $host_agents_file"
    return
  fi

  printf "\n\n%s\n" "$bootstrap_block" >> "$host_agents_file"
  echo "Appended OpenCaw bootstrap to existing host AGENTS: $host_agents_file"
}

# Validate every scaffold destination before adding host instructions or state.
opencaw_assert_project_path "$host_agents_file" file
opencaw_assert_project_path "$host_cache_dir/tasks/example-task" dir
opencaw_assert_project_path "$host_cache_dir/tasks/example-task/TASK.md" file
ensure_host_agents_bootstrap

ensure_windows_bash_guidance() {
  local baseline_relative installer_reference guidance_file guidance_content

  opencaw_is_windows_host || return 0

  if [[ "$host_root" == "$opencaw_root" ]]; then
    installer_reference='./commands/install-windows-bash.ps1'
  else
    installer_reference='./.opencaw/commands/install-windows-bash.ps1'
  fi

  guidance_file="$host_cache_dir/WINDOWS_BASH.md"
  if [[ ! -f "$guidance_file" ]]; then
    guidance_content="$(cat <<'EOF'
# Windows Bash Setup

OpenCaw commands use Bash. On Windows, prefer Git Bash for native Windows filesystem performance; use WSL when Linux tool compatibility is more important.

The scaffold never installs software automatically. Run these commands from the repository root in PowerShell.

## Check for an existing provider

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "__OPENCAW_WINDOWS_BASH_INSTALLER__"
```

## Install native Git Bash (recommended)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "__OPENCAW_WINDOWS_BASH_INSTALLER__" -Provider GitBash -Install
```

## Install WSL Bash

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "__OPENCAW_WINDOWS_BASH_INSTALLER__" -Provider WSL -Install
```

WSL installation can require elevation or a restart.

## Run the OpenCaw scaffold

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "__OPENCAW_WINDOWS_BASH_INSTALLER__" -Provider GitBash -RunScaffold -ProjectRoot .
```

Linux and macOS should run `./commands/create-host-ai-scaffold.sh` directly; this Windows bootstrap is not needed there.
EOF
)"
    guidance_content="${guidance_content//__OPENCAW_WINDOWS_BASH_INSTALLER__/$installer_reference}"
    printf '%s\n' "$guidance_content" > "$guidance_file"
  fi

  echo "WINDOWS_BASH_GUIDANCE=$guidance_file"
}

mkdir -p \
  "$host_cache_dir/gauntlets" \
  "$host_cache_dir/goals" \
  "$host_cache_dir/tasks" \
  "$host_cache_dir/archive/gauntlets" \
  "$host_cache_dir/archive/goals" \
  "$host_cache_dir/archive/tasks" \
  "$host_cache_dir/archive/context-snapshots" \
  "$host_cache_dir/archive/memory" \
  "$host_cache_dir/archive/memory-v1" \
  "$host_cache_dir/migrations" \
  "$host_cache_dir/reports"

opencaw_ensure_system_memory
opencaw_ensure_project_files
ensure_windows_bash_guidance

mkdir -p "$host_cache_dir/tasks/example-task"

if [[ ! -f "$host_cache_dir/tasks/TODO.md" ]]; then
  cat > "$host_cache_dir/tasks/TODO.md" <<'EOF'
# TODO

1. [ ] Example first task (`.opencaw/.cache/tasks/example-task/TASK.md`)
EOF
fi

[[ -f "$host_cache_dir/tasks/OPEN_ISSUES.md" ]] || : > "$host_cache_dir/tasks/OPEN_ISSUES.md"

[[ -f "$host_cache_dir/tasks/example-task/TASK.md" ]] || cat > "$host_cache_dir/tasks/example-task/TASK.md" <<'EOF'
# Example first task

## Goal

## Scope

## Assumptions

## Work Instructions

## Verification

## Review

## Issue
EOF

migration_required='false'
if grep -Eq '^-[[:space:]]+[^[]' "$OPENCAW_PROJECT_MEMORY_FILE" \
  || [[ -d "$host_cache_dir/FRAGMENTS" ]] \
  || [[ -d "$host_cache_dir/LEARNINGS" ]]; then
  migration_required='true'
fi

echo "OPENCAW_PROJECT_ROOT=$host_root"
echo "OPENCAW_INSTALL_DIR=$OPENCAW_INSTALL_DIR"
echo "OPENCAW_PROJECT_CACHE_DIR=$host_cache_dir"
echo "SYSTEM_MEMORY_FILE=$OPENCAW_SYSTEM_MEMORY_FILE"
echo "PROJECT_MEMORY_FILE=$OPENCAW_PROJECT_MEMORY_FILE"
echo "REPO_MAP_FILE=$OPENCAW_REPO_MAP_FILE"
echo "MEMORY_MIGRATION_REQUIRED=$migration_required"
