#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/brainstorm-common.sh"

usage() {
  cat <<'EOF'
Usage: ./commands/validate-brainstorm.sh [--phase active|inactive]

Validates repository-root BRAINSTORM.md. In inactive phase, also requires a
current hash-bound BRAINSTORM_SUMMARY.md.
EOF
}

phase='any'
while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase)
      phase="${2:-}"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done
case "$phase" in any|active|inactive) ;; *) echo "Invalid phase: $phase" >&2; exit 1 ;; esac

brainstorm_validate_file "$OPENCAW_BRAINSTORM_FILE" "$phase"
if [[ "$phase" == 'inactive' || ( "$phase" == 'any' && "$OPENCAW_BRAINSTORM_MODE_STATUS" == 'inactive' ) ]]; then
  brainstorm_validate_summary "$OPENCAW_BRAINSTORM_FILE" "$OPENCAW_BRAINSTORM_SUMMARY_FILE"
fi
echo "Brainstorm validation passed (state=$OPENCAW_BRAINSTORM_MODE_STATUS branches=$OPENCAW_BRAINSTORM_BRANCH_COUNT elements=$OPENCAW_BRAINSTORM_ELEMENT_COUNT)."
