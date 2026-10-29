#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/generate-media-contract.sh [--inline] [--output PATH] CLOUD [LOCAL]

Generates an optional host MEDIA.md. Link directives are used by default;
--inline embeds the selected pipeline templates. CLOUD must be first.
EOF
}

mode="link"
output=""
backends=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --inline) mode="inline"; shift ;;
    --output) [[ $# -ge 2 ]] || { echo "--output requires a path" >&2; exit 1; }; output="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; while [[ $# -gt 0 ]]; do backends+=("$1"); shift; done ;;
    -*) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    *) backends+=("$1"); shift ;;
  esac
done

[[ ${#backends[@]} -ge 1 ]] || { usage >&2; exit 1; }

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/memory-common.sh"
source "$script_dir/lib/art-pipeline-common.sh"
opencaw_resolve_paths
opencaw_root="$OPENCAW_ROOT"
host_root="$OPENCAW_PROJECT_ROOT_RESOLVED"
mount_dir_name="$(basename "$opencaw_root")"
if [[ "$opencaw_root" == "$host_root" ]]; then mount_path_from_host='.'; else mount_path_from_host="./${mount_dir_name}"; fi
target="${output:-$host_root/MEDIA.md}"

backend_template_relative_path() {
  case "$1" in
    CLOUD) printf '%s\n' ".styles/.pipelines/cloud/PIPELINE.md" ;;
    LOCAL) printf '%s\n' ".styles/.pipelines/local/PIPELINE.md" ;;
    *) return 1 ;;
  esac
}

selected=()
for raw in "${backends[@]}"; do
  name="$(art_pipeline_normalize "$raw")" || { echo "Unknown media pipeline: $raw" >&2; exit 1; }
  case "$name" in CLOUD|LOCAL) ;; *) echo "MEDIA.md supports only CLOUD and LOCAL: $raw" >&2; exit 1 ;; esac
  template_relative_path="$(backend_template_relative_path "$name")"
  [[ -f "$opencaw_root/$template_relative_path" ]] || { echo "Missing media template: $name ($template_relative_path)" >&2; exit 1; }
  for existing in "${selected[@]:-}"; do [[ "$existing" != "$name" ]] || { echo "Duplicate media pipeline: $name" >&2; exit 1; }; done
  selected+=("$name")
done

[[ "${selected[0]}" == "CLOUD" ]] || { echo "CLOUD must be the first media pipeline." >&2; exit 1; }
if [[ ${#selected[@]} -gt 2 || (${#selected[@]} -eq 2 && "${selected[1]}" != "LOCAL") ]]; then
  echo "Supported media composition is CLOUD with optional LOCAL." >&2
  exit 1
fi

mkdir -p "$(dirname "$target")"
{
  echo "# MEDIA.md"
  echo
  echo "This file is the canonical generative media contract for this repository. STYLE.md remains the visual authority."
  echo
  echo "Generated from OpenCaw media pipeline templates:"
  for name in "${selected[@]}"; do echo "- $name"; done
  echo
  echo "---"
  echo
  echo "## Pipeline Availability"
  echo
  echo "- CLOUD is the default generated-media capability for each supported modality. STYLE.md remains authoritative for visual pipeline selection."
  if [[ ${#selected[@]} -eq 2 ]]; then
    echo "- LOCAL is available when inspection confirms the requested modality is viable."
    echo "- When both pipelines are viable, ask the user to choose before generation. Never switch or fall back across this boundary silently."
  else
    echo "- No local pipeline is configured. Do not infer or silently add one."
  fi
  echo
  echo "## Capability Matrix"
  echo
  echo "Record image, music, sound-effect, and voice availability independently, including tool/model/workflow versions or explicit unavailable markers."
  echo
  echo "## Destinations And Budgets"
  echo
  echo "Record non-runtime staging locations, intended runtime destinations, dimensions or durations, formats, file-size and performance budgets, and generation cost limits before each batch."
  echo
  echo "## Rights, Consent, And Provenance"
  echo
  echo "Record input sources, rights, identity or voice consent, provider/pipeline, disclosed revisions, parameters, seeds, workflow digests, and staged output hashes. Never persist credentials."
  echo
  echo "## Review And Promotion"
  echo
  echo "Use contact sheets or listen-through reviews, exact coverage and geometry checks, explicit acceptance or rejection, and a separate human-reviewed promotion action."
  echo
  if [[ "$mode" == "link" ]]; then
    echo "## Read Pipeline Instructions"
    echo
    for name in "${selected[@]}"; do
      template_relative_path="$(backend_template_relative_path "$name")"
      echo "Read \`${mount_path_from_host}/${template_relative_path}\` instructions"
    done
  else
    echo "## Inlined Pipeline Instructions"
    echo
    for name in "${selected[@]}"; do
      template_relative_path="$(backend_template_relative_path "$name")"
      echo "<!-- BEGIN MEDIA PIPELINE: $name -->"
      echo
      cat "$opencaw_root/$template_relative_path"
      echo
      echo "<!-- END MEDIA PIPELINE: $name -->"
      echo
    done
  fi
} > "$target"

echo "Wrote $target"
echo "Mode: $mode."
