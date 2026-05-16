#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/create-subagent-plan.sh "<task_name>" ["agent_count"] [--dry-run]

Creates ../.ai/tasks/<task_name>/SUBAGENTS.md when it does not already exist.
Use --dry-run to print the plan scaffold without writing files.
EOF
}

task_name=""
agent_count=""
dry_run=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      dry_run=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -z "$task_name" ]]; then
        task_name="$1"
      elif [[ -z "$agent_count" ]]; then
        agent_count="$1"
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

if [[ -n "$agent_count" && ! "$agent_count" =~ ^[1-9][0-9]*$ ]]; then
  echo "agent_count must be a positive integer: $agent_count" >&2
  exit 1
fi

task_dir="../.ai/tasks/$task_name"
target="$task_dir/SUBAGENTS.md"
requested="${agent_count:-unspecified}"
lane_count="${agent_count:-1}"

write_plan() {
  cat <<EOF
# Subagent Plan: $task_name

## Capacity
- Requested: $requested
- Effective lanes: $lane_count
- Reason: TODO

## Rules
- Resolve each lane role with \`./commands/resolve-role.sh\` before delegation.
- Use \`explorer\` for read-only lanes and \`worker\` for implementation lanes when Codex subagents are available.
- Worker lanes must declare disjoint write sets.
- Keep the main agent responsible for orchestration, critical-path blockers, integration, final verification, and user communication.

## Lanes
EOF

  local i
  for ((i = 1; i <= lane_count; i++)); do
    cat <<EOF

### lane-$i
- Role: TODO
- Agent type: TODO
- Status: planned
- Scope: TODO
- Write set: TODO
- Dependencies: none
- Expected output: TODO
- Verification: TODO
EOF
  done

  cat <<EOF

## Integration
- Merge order: TODO
- Conflict risks: TODO
- Final verification: TODO

## Results
EOF
}

if [[ $dry_run -eq 1 ]]; then
  echo "Dry run: would create $target"
  echo
  write_plan
  exit 0
fi

mkdir -p "$task_dir"

if [[ -f "$target" ]]; then
  echo "$target already exists"
  exit 0
fi

write_plan > "$target"
echo "Created $target"
