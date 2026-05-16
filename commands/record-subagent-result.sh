#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/record-subagent-result.sh "<task_name>" "<lane_id>" "<status>" "<summary_file>" [--dry-run]

Appends lane result evidence to ../.ai/tasks/<task_name>/SUBAGENTS.md.
EOF
}

task_name=""
lane_id=""
lane_status=""
summary_file=""
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
      elif [[ -z "$lane_id" ]]; then
        lane_id="$1"
      elif [[ -z "$lane_status" ]]; then
        lane_status="$1"
      elif [[ -z "$summary_file" ]]; then
        summary_file="$1"
      else
        usage >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$task_name" || -z "$lane_id" || -z "$lane_status" || -z "$summary_file" ]]; then
  usage >&2
  exit 1
fi

if [[ ! "$lane_id" =~ ^lane-[a-z0-9][a-z0-9-]*$ ]]; then
  echo "Invalid lane id: $lane_id" >&2
  exit 1
fi

if [[ ! "$lane_status" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
  echo "Invalid status: $lane_status" >&2
  exit 1
fi

if [[ ! -f "$summary_file" ]]; then
  echo "Missing summary file: $summary_file" >&2
  exit 1
fi

target="../.ai/tasks/$task_name/SUBAGENTS.md"
if [[ ! -f "$target" && $dry_run -eq 0 ]]; then
  echo "Missing subagent plan: $target" >&2
  exit 1
fi

if [[ -f "$target" ]] && ! grep -Eq "^###[[:space:]]+${lane_id}[[:space:]]*$" "$target"; then
  echo "Lane not found in $target: $lane_id" >&2
  exit 1
fi

timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

make_entry() {
  cat <<EOF

### Result: $lane_id - $lane_status - $timestamp
- Summary source: \`$summary_file\`

\`\`\`text
EOF
  sed -e 's/\r$//' "$summary_file"
  cat <<'EOF'
```
EOF
}

if [[ $dry_run -eq 1 ]]; then
  echo "Dry run: would append result to $target"
  if [[ ! -f "$target" ]]; then
    echo "Dry run note: $target does not exist, so lane existence was not checked."
  fi
  make_entry
  exit 0
fi

make_entry >> "$target"
echo "Recorded $lane_id result in $target"
