#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/validate-media-contract.sh [MEDIA.md]

Validates a configured host generative-media contract. Defaults to ../MEDIA.md.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage; exit 0; fi
[[ $# -le 1 ]] || { usage >&2; exit 1; }

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
opencaw_root="$(cd "$script_dir/.." && pwd)"
host_root="$(cd "$opencaw_root/.." && pwd)"
media_file="${1:-$host_root/MEDIA.md}"
[[ -f "$media_file" ]] || { echo "Missing MEDIA.md: $media_file" >&2; exit 1; }

status=0
for heading in "# MEDIA.md" "## Backend Selection" "## Capability Matrix" "## Destinations And Budgets" "## Rights, Consent, And Provenance" "## Review And Promotion"; do
  grep -Fqx "$heading" "$media_file" || { echo "MEDIA.md is missing: $heading" >&2; status=1; }
done

mapfile -t selected < <(awk '
  /^Generated from OpenCaw media backend templates:/ { list=1; next }
  /^---$/ { list=0 }
  list && /^- / { sub(/^- /, ""); sub(/\r$/, ""); print }
' "$media_file")

[[ ${#selected[@]} -ge 1 ]] || { echo "MEDIA.md does not list a backend." >&2; status=1; }
if [[ ${#selected[@]} -ge 1 && "${selected[0]}" != "CLOUD_SESSION" ]]; then
  echo "CLOUD_SESSION must be the first backend." >&2; status=1
fi
for backend in "${selected[@]:-}"; do
  case "$backend" in CLOUD_SESSION|COMFYUI_LOCAL) ;; *) echo "Unknown backend in MEDIA.md: $backend" >&2; status=1; continue ;; esac
  [[ -f "$opencaw_root/.media/$backend.md" ]] || { echo "Missing backend template: $backend" >&2; status=1; }
done

if printf '%s\n' "${selected[@]:-}" | grep -qx 'COMFYUI_LOCAL'; then
  grep -Eiq 'ask the user to choose|require the user to choose' "$media_file" || { echo "Hybrid MEDIA.md lacks an explicit backend choice gate." >&2; status=1; }
  grep -Eiq 'never (switch or )?fall back.*silently|never.*silently.*fall back' "$media_file" || { echo "Hybrid MEDIA.md lacks a no-silent-fallback rule." >&2; status=1; }
fi

if grep -Eiq '(api[_ -]?key|access[_ -]?token|hf[_ -]?token)[[:space:]]*[:=][[:space:]]*[A-Za-z0-9_/-]{12,}' "$media_file"; then
  echo "MEDIA.md appears to contain a persisted credential." >&2; status=1
fi

if [[ $status -eq 0 ]]; then
  echo "Media contract validation passed."
  printf 'Configured backends:'; printf ' %s' "${selected[@]}"; printf '\n'
fi
exit $status
