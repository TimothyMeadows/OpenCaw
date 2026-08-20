#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/create-code-character-profile.sh CHARACTER_ID --manifest FILE --brief TEXT --intended-use TEXT [options]

Creates a task-local opencaw-code-character/v1 profile linked to an existing CODE manifest.

Options:
  --output FILE                 Profile below .ai/tasks (default: .ai/tasks/CHARACTER_ID/code-character.json)
  --title TEXT                  Human-readable title
  --kind VALUE                  character or creature (default: character)
  --presentation-distance VALUE close, mid, far, or mixed (default: mixed)
  --representative-actors N     Runtime actor count represented by evidence (default: 1)
  --temperament TEXT            Character temperament
  --identity TEXT               Frozen identity statement
  --signature-part ID           Repeatable semantic part from the CODE manifest
  --builder ID                  Repeatable active builder identity
  --view VIEW                   Repeatable required view
  --pixel-height N              Repeatable target presentation height
  --motion-mode VALUE           static, articulated, or skinned (default: static)
  --skeleton-id ID              Skeleton identity for skinned motion
  --max-influences N            Maximum skin influences per vertex
  --animation-role ID           Repeatable required animation role
  --grounding-tolerance-ratio N Normalized ground-contact tolerance (default: 0.01)
  --contact-tolerance-ratio N   Normalized animation-contact tolerance (default: 0.02)
  --construction-runs N         Determinism calibration runs, minimum 2 (default: 3)
  --lifecycle-cycles N          Repeated ownership cycles (default: 3)
  --max-gate-attempts N         Maximum attempts per character gate (default: 3)
  --repeated-failure-limit N     Escalation threshold for one failure class (default: 2)
EOF
}

[[ $# -gt 0 ]] || { usage >&2; exit 1; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/memory-common.sh"
opencaw_resolve_paths
node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || { echo "Node.js is required for code-character profiles." >&2; exit 1; }
node_root="$OPENCAW_PROJECT_ROOT_RESOLVED"
node_cli="$script_dir/lib/code-character-cli.cjs"
if [[ "$node_bin" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then
  node_root="$(wslpath -w "$node_root")"
  node_cli="$(wslpath -w "$node_cli")"
fi
"$node_bin" "$node_cli" create "$node_root" "$@"
