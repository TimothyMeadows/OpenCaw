#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/validate-media-contract.sh [MEDIA.md]

Validates a configured host generated-media contract. Defaults to the resolved project MEDIA.md.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage; exit 0; fi
[[ $# -le 1 ]] || { usage >&2; exit 1; }

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/memory-common.sh"
source "$script_dir/lib/art-pipeline-common.sh"
opencaw_resolve_paths
opencaw_root="$OPENCAW_ROOT"
host_root="$OPENCAW_PROJECT_ROOT_RESOLVED"
media_file="${1:-$host_root/MEDIA.md}"
[[ -f "$media_file" ]] || { echo "Missing MEDIA.md: $media_file" >&2; exit 1; }

backend_template_path() {
  case "$1" in
    CLOUD) printf '%s\n' "$opencaw_root/.styles/.pipelines/cloud/PIPELINE.md" ;;
    LOCAL) printf '%s\n' "$opencaw_root/.styles/.pipelines/local/PIPELINE.md" ;;
    *) return 1 ;;
  esac
}

status=0
for heading in "# MEDIA.md" "## Pipeline Availability" "## Capability Matrix" "## Destinations And Budgets" "## Rights, Consent, And Provenance" "## Review And Promotion"; do
  awk -v expected="$heading" '{ sub(/\r$/, ""); if ($0 == expected) found=1 } END { exit !found }' "$media_file" || { echo "MEDIA.md is missing: $heading" >&2; status=1; }
done

mapfile -t selected < <(awk '
  /^Generated from OpenCaw media pipeline templates:/ { list=1; next }
  /^---$/ { list=0 }
  list && /^- / { sub(/^- /, ""); sub(/\r$/, ""); print }
' "$media_file")

[[ ${#selected[@]} -ge 1 ]] || { echo "MEDIA.md does not list a pipeline." >&2; status=1; }
if [[ ${#selected[@]} -ge 1 && "${selected[0]}" != "CLOUD" ]]; then
  echo "CLOUD must be the first media pipeline." >&2; status=1
fi
for backend in "${selected[@]:-}"; do
  case "$backend" in CLOUD|LOCAL) ;; *) echo "Unknown pipeline in MEDIA.md: $backend" >&2; status=1; continue ;; esac
  template_path="$(backend_template_path "$backend")"
  [[ -f "$template_path" ]] || { echo "Missing pipeline template: $backend ($template_path)" >&2; status=1; }
done

if printf '%s\n' "${selected[@]:-}" | grep -qx 'LOCAL'; then
  grep -Eiq 'ask the user to choose|require the user to choose' "$media_file" || { echo "Hybrid MEDIA.md lacks an explicit pipeline choice gate." >&2; status=1; }
  grep -Eiq 'never (switch or )?fall back.*silently|never.*silently.*fall back' "$media_file" || { echo "Hybrid MEDIA.md lacks a no-silent-fallback rule." >&2; status=1; }
fi

if grep -Eiq '(api[_ -]?key|access[_ -]?token|hf[_ -]?token)[[:space:]]*[:=][[:space:]]*[A-Za-z0-9_/-]{12,}' "$media_file"; then
  echo "MEDIA.md appears to contain a persisted credential." >&2; status=1
fi

if [[ $status -eq 0 ]]; then
  echo "Media contract validation passed."
  printf 'Configured media pipelines:'; printf ' %s' "${selected[@]}"; printf '\n'
fi
exit $status
