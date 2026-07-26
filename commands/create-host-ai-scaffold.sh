#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/memory-common.sh"
source "$script_dir/lib/platform-common.sh"
opencaw_resolve_paths

opencaw_root="$OPENCAW_ROOT"
host_root="$OPENCAW_PROJECT_ROOT_RESOLVED"
host_ai_dir="$host_root/.ai"
host_agents_file="$host_root/AGENTS.md"

ensure_file() {
  local path="$1"
  local title="$2"
  [[ -f "$path" ]] || printf "%s\n\n" "$title" > "$path"
}

ensure_host_agents_bootstrap() {
  local mount_dir_name fallback_mount_path

  if [[ "$host_root" == "$opencaw_root" ]]; then
    echo "Standalone OpenCaw checkout detected; host bootstrap already resolves to $host_agents_file"
    return
  fi

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

ensure_windows_bash_guidance() {
  local baseline_relative installer_reference guidance_file guidance_content

  opencaw_is_windows_host || return 0

  if [[ "$host_root" == "$opencaw_root" ]]; then
    installer_reference='./commands/install-windows-bash.ps1'
  else
    baseline_relative="${opencaw_root#"$host_root"/}"
    installer_reference="./$baseline_relative/commands/install-windows-bash.ps1"
  fi

  guidance_file="$host_ai_dir/WINDOWS_BASH.md"
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
  "$host_ai_dir/goals" \
  "$host_ai_dir/tasks" \
  "$host_ai_dir/archive/goals" \
  "$host_ai_dir/archive/tasks" \
  "$host_ai_dir/archive/context-snapshots" \
  "$host_ai_dir/archive/memory" \
  "$host_ai_dir/archive/memory-v1" \
  "$host_ai_dir/migrations" \
  "$host_ai_dir/reports"

opencaw_ensure_system_memory
opencaw_ensure_project_files
ensure_windows_bash_guidance

mkdir -p "$host_ai_dir/tasks/example-task"

if [[ ! -f "$host_ai_dir/tasks/TODO.md" ]]; then
  cat > "$host_ai_dir/tasks/TODO.md" <<'EOF'
# TODO

1. [ ] Example first task (`.ai/tasks/example-task/TASK.md`)
EOF
fi

[[ -f "$host_ai_dir/tasks/OPEN_ISSUES.md" ]] || : > "$host_ai_dir/tasks/OPEN_ISSUES.md"

[[ -f "$host_ai_dir/tasks/example-task/TASK.md" ]] || cat > "$host_ai_dir/tasks/example-task/TASK.md" <<'EOF'
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
  || [[ -d "$host_ai_dir/FRAGMENTS" ]] \
  || [[ -d "$host_ai_dir/LEARNINGS" ]]; then
  migration_required='true'
fi

echo "OPENCAW_PROJECT_ROOT=$host_root"
echo "SYSTEM_MEMORY_FILE=$OPENCAW_SYSTEM_MEMORY_FILE"
echo "PROJECT_MEMORY_FILE=$OPENCAW_PROJECT_MEMORY_FILE"
echo "REPO_MAP_FILE=$OPENCAW_REPO_MAP_FILE"
echo "MEMORY_MIGRATION_REQUIRED=$migration_required"
