#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/brainstorm-common.sh"

usage() {
  cat <<'EOF'
Usage: ./commands/show-brainstorm.sh [--markdown]

Default output is a Mermaid mindmap. --markdown prints BRAINSTORM.md verbatim.
EOF
}

format='mindmap'
while [[ $# -gt 0 ]]; do
  case "$1" in
    --markdown) format='markdown' ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

[[ -f "$OPENCAW_BRAINSTORM_FILE" ]] || { echo "Missing Brainstorm file: $OPENCAW_BRAINSTORM_FILE" >&2; exit 1; }
if [[ "$format" == 'markdown' ]]; then
  cat "$OPENCAW_BRAINSTORM_FILE"
  exit 0
fi

brainstorm_validate_file "$OPENCAW_BRAINSTORM_FILE" any

sanitize_label() {
  printf '%s' "$1" | sed -E 's/[\[\]"`]/ /g; s/[[:space:]]+/ /g; s/^[[:space:]]+//; s/[[:space:]]+$//'
}

print_branch() {
  local branch_id="$1" indent="$2" child idea_id label
  label="$(sanitize_label "${OPENCAW_BRAINSTORM_BRANCH_TITLE[$branch_id]}")"
  printf '%*s%s[%s]\n' "$indent" '' "${branch_id//-/_}" "$label"
  for idea_id in "${OPENCAW_BRAINSTORM_IDEA_IDS[@]}"; do
    [[ "${OPENCAW_BRAINSTORM_IDEA_BRANCH[$idea_id]}" == "$branch_id" ]] || continue
    label="$(sanitize_label "$idea_id: ${OPENCAW_BRAINSTORM_IDEA_TITLE[$idea_id]} (${OPENCAW_BRAINSTORM_IDEA_STATUS[$idea_id]})")"
    printf '%*s%s[%s]\n' "$((indent + 2))" '' "${idea_id//-/_}" "$label"
  done
  for child in "${OPENCAW_BRAINSTORM_BRANCH_IDS[@]}"; do
    [[ "${OPENCAW_BRAINSTORM_BRANCH_PARENT[$child]}" == "$branch_id" ]] || continue
    print_branch "$child" "$((indent + 2))"
  done
}

echo '```mermaid'
echo 'mindmap'
echo '  root((Brainstorm))'
if [[ ${#OPENCAW_BRAINSTORM_BRANCH_IDS[@]} -eq 0 ]]; then
  echo '    empty[No ideas yet]'
else
  for branch_id in "${OPENCAW_BRAINSTORM_BRANCH_IDS[@]}"; do
    [[ "${OPENCAW_BRAINSTORM_BRANCH_PARENT[$branch_id]}" == 'ROOT' ]] || continue
    print_branch "$branch_id" 4
  done
fi
echo '```'
