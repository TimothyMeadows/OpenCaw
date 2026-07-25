#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/validate-gameplay-review.sh <report>

Validates the required sections and non-placeholder evidence in a gameplay review.
EOF
}

report="${1:-}"
if [[ -z "$report" || "$report" == "-h" || "$report" == "--help" ]]; then
  usage
  [[ -z "$report" ]] && exit 1 || exit 0
fi
[[ $# -eq 1 ]] || { usage >&2; exit 1; }
[[ -f "$report" ]] || { echo "Gameplay review does not exist: $report" >&2; exit 1; }

required_sections=(
  "Summary"
  "Controls And Accessibility"
  "Gameplay Systems"
  "Performance"
  "Evidence"
  "Risks And Recommendation"
)
status=0
for section in "${required_sections[@]}"; do
  if ! grep -Eq "^##[[:space:]]+${section}[[:space:]]*$" "$report"; then
    echo "Missing required section: $section" >&2
    status=1
    continue
  fi
  content="$(awk -v heading="## $section" '
    $0 == heading { active=1; next }
    active && /^##[[:space:]]/ { exit }
    active { print }
  ' "$report" | sed -E '/^[[:space:]]*$/d')"
  if [[ -z "$content" ]] || printf '%s\n' "$content" | grep -Eiq '^[[:space:]]*(-[[:space:]]*)?(todo|tbd|n/?a|<[^>]+>)[[:space:]]*$'; then
    echo "Section is empty or contains only placeholder content: $section" >&2
    status=1
  fi
done

if [[ $status -eq 0 ]]; then
  echo "Gameplay review validation passed: $report"
fi
exit $status
