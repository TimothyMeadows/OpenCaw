#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo 'Usage: ./commands/repo-map-status.sh [--stamp]'
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/memory-common.sh"

stamp='false'
while [[ $# -gt 0 ]]; do
  case "$1" in
    --stamp)
      stamp='true'
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

opencaw_resolve_paths
current_fingerprint="$(opencaw_compute_repo_fingerprint)"

if [[ ! -f "$OPENCAW_REPO_MAP_FILE" ]]; then
  echo 'REPO_MAP_STATUS=MISSING'
  echo "CURRENT_FINGERPRINT=$current_fingerprint"
  exit 0
fi

entry_count="$(grep -Ec '^-[[:space:]]+\[' "$OPENCAW_REPO_MAP_FILE" || true)"
stored_fingerprint="$(sed -nE 's/^<!-- OPENCAW_REPO_MAP_FINGERPRINT: ([^ ]+) -->$/\1/p' "$OPENCAW_REPO_MAP_FILE" | head -n1)"

if [[ "$stamp" == 'true' ]]; then
  [[ "$entry_count" -gt 0 ]] || { echo 'Refusing to stamp an empty semantic repository map.' >&2; exit 1; }
  if grep -q '^<!-- OPENCAW_REPO_MAP_FINGERPRINT:' "$OPENCAW_REPO_MAP_FILE"; then
    sed -E "s/^<!-- OPENCAW_REPO_MAP_FINGERPRINT: [^ ]+ -->$/<!-- OPENCAW_REPO_MAP_FINGERPRINT: $current_fingerprint -->/" \
      "$OPENCAW_REPO_MAP_FILE" > "$OPENCAW_REPO_MAP_FILE.tmp"
  else
    awk -v marker="<!-- OPENCAW_REPO_MAP_FINGERPRINT: $current_fingerprint -->" '
      NR == 1 { print; print ""; print marker; next }
      { print }
    ' "$OPENCAW_REPO_MAP_FILE" > "$OPENCAW_REPO_MAP_FILE.tmp"
  fi
  mv "$OPENCAW_REPO_MAP_FILE.tmp" "$OPENCAW_REPO_MAP_FILE"
  stored_fingerprint="$current_fingerprint"
fi

if [[ "$entry_count" -eq 0 ]]; then
  status='EMPTY'
elif [[ "$stored_fingerprint" == "$current_fingerprint" ]]; then
  status='CURRENT'
else
  status='STALE'
fi

echo "REPO_MAP_STATUS=$status"
echo "STORED_FINGERPRINT=${stored_fingerprint:-missing}"
echo "CURRENT_FINGERPRINT=$current_fingerprint"
echo "SEMANTIC_ENTRIES=$entry_count"
