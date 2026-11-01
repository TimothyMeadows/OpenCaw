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

hephaera_resolve_paths
current_fingerprint="$(hephaera_compute_repo_fingerprint)"

if [[ ! -f "$HEPHAERA_REPO_MAP_FILE" ]]; then
  echo 'REPO_MAP_STATUS=MISSING'
  echo "CURRENT_FINGERPRINT=$current_fingerprint"
  exit 0
fi

entry_count="$(grep -Ec '^-[[:space:]]+\[' "$HEPHAERA_REPO_MAP_FILE" || true)"
stored_fingerprint="$(sed -nE 's/\r$//; s/^<!-- HEPHAERA_REPO_MAP_FINGERPRINT: ([^ ]+) -->$/\1/p' "$HEPHAERA_REPO_MAP_FILE" | head -n1)"

if [[ "$stamp" == 'true' ]]; then
  [[ "$entry_count" -gt 0 ]] || { echo 'Refusing to stamp an empty semantic repository map.' >&2; exit 1; }
  if grep -q '^<!-- HEPHAERA_REPO_MAP_FINGERPRINT:' "$HEPHAERA_REPO_MAP_FILE"; then
    sed -E "s/\r$//; s/^<!-- HEPHAERA_REPO_MAP_FINGERPRINT: [^ ]+ -->$/<!-- HEPHAERA_REPO_MAP_FINGERPRINT: $current_fingerprint -->/" \
      "$HEPHAERA_REPO_MAP_FILE" > "$HEPHAERA_REPO_MAP_FILE.tmp"
  else
    awk -v marker="<!-- HEPHAERA_REPO_MAP_FINGERPRINT: $current_fingerprint -->" '
      NR == 1 { print; print ""; print marker; next }
      { print }
    ' "$HEPHAERA_REPO_MAP_FILE" > "$HEPHAERA_REPO_MAP_FILE.tmp"
  fi
  mv "$HEPHAERA_REPO_MAP_FILE.tmp" "$HEPHAERA_REPO_MAP_FILE"
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
