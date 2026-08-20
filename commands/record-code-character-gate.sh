#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/record-code-character-gate.sh PROFILE.json --gate ID --decision DECISION --summary TEXT --strategy TEXT --evidence KIND=FILE [options]

Decisions: pass, revise-spec, revise-code, request-input, stop
Options:
  --remaining-gaps TEXT
  --failure-class ID           Required for every non-pass decision
  --evidence KIND=FILE         Repeatable, immutable task-local evidence
  --reviewer-id ID             Required for reviewer gates; must differ from builders
  --reviewer-type VALUE        agent or human
  --reviewer-packet FILE       Required for reviewer gates and repeated as reviewer-packet evidence
  --observed-answer TEXT       Reviewer's answer to the frozen gate question
EOF
}

[[ $# -gt 0 ]] || { usage >&2; exit 1; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/memory-common.sh"
opencaw_resolve_paths
node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || { echo "Node.js is required for code-character gate evidence." >&2; exit 1; }
node_root="$OPENCAW_PROJECT_ROOT_RESOLVED"
node_cli="$script_dir/lib/code-character-cli.cjs"
if [[ "$node_bin" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then
  node_root="$(wslpath -w "$node_root")"
  node_cli="$(wslpath -w "$node_cli")"
fi
"$node_bin" "$node_cli" record "$node_root" "$@"
