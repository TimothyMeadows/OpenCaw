#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/generate-style.sh [--inline] [--pipeline PIPELINE] [--allow-pipeline PIPELINE ...] [--asset-library ID=ABSOLUTE_PATH ... | --clear-asset-libraries] "<STYLE1>" ["STYLE2" ...]

Defaults to concise link-based output in ../STYLE.md.
CSS3 is the default primary art pipeline when --pipeline is omitted.
Existing external asset libraries are preserved unless explicitly replaced or cleared.
Use --inline to embed full style template contents.
EOF
}

mode='link'
styles=()
primary_pipeline=''
allowed_pipeline_inputs=()
external_library_specs=()
clear_external_libraries=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --inline)
      mode='inline'
      shift
      ;;
    --pipeline)
      [[ $# -ge 2 ]] || { echo "--pipeline requires a value" >&2; exit 1; }
      [[ -z "$primary_pipeline" ]] || { echo "--pipeline may be supplied only once" >&2; exit 1; }
      primary_pipeline="$2"
      shift 2
      ;;
    --allow-pipeline)
      [[ $# -ge 2 ]] || { echo "--allow-pipeline requires a value" >&2; exit 1; }
      allowed_pipeline_inputs+=("$2")
      shift 2
      ;;
    --asset-library)
      [[ $# -ge 2 ]] || { echo "--asset-library requires ID=ABSOLUTE_PATH" >&2; exit 1; }
      external_library_specs+=("$2")
      shift 2
      ;;
    --clear-asset-libraries)
      clear_external_libraries=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        styles+=("$1")
        shift
      done
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      styles+=("$1")
      shift
      ;;
  esac
done

if [[ "${#styles[@]}" -eq 0 ]]; then
  usage >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/memory-common.sh"
source "$script_dir/lib/art-pipeline-common.sh"
source "$script_dir/lib/external-asset-library-common.sh"
opencaw_resolve_paths
opencaw_root="$OPENCAW_ROOT"
host_root="$OPENCAW_PROJECT_ROOT_RESOLVED"
mount_dir_name="$(basename "$opencaw_root")"
if [[ "$opencaw_root" == "$host_root" ]]; then mount_path_from_host='.'; else mount_path_from_host="./${mount_dir_name}"; fi
style_target="$host_root/STYLE.md"

if [[ $clear_external_libraries -eq 1 && ${#external_library_specs[@]} -gt 0 ]]; then
  echo '--clear-asset-libraries cannot be combined with --asset-library.' >&2
  exit 1
fi

external_library_ids=()
external_library_paths=()
if [[ ${#external_library_specs[@]} -gt 0 ]]; then
  for raw_spec in "${external_library_specs[@]}"; do
    external_asset_library_parse_spec "$raw_spec"
    external_library_ids+=("$EXTERNAL_ASSET_LIBRARY_ID")
    external_library_paths+=("$EXTERNAL_ASSET_LIBRARY_PATH")
  done
elif [[ $clear_external_libraries -eq 0 && -f "$style_target" ]]; then
  preserved_external_libraries="$(external_asset_library_entries "$style_target")" || exit 1
  while IFS=$'\t' read -r library_id library_path; do
    [[ -n "$library_id" ]] || continue
    external_library_ids+=("$library_id")
    external_library_paths+=("$library_path")
  done <<< "$preserved_external_libraries"
fi

declare -A seen_library_ids=()
declare -A seen_library_paths=()
for index in "${!external_library_ids[@]}"; do
  library_id="${external_library_ids[$index]}"
  library_path="${external_library_paths[$index]}"
  external_asset_library_validate_id "$library_id"
  external_asset_library_validate_path "$library_path"
  [[ -z "${seen_library_ids[$library_id]:-}" ]] || { echo "Duplicate external asset library id: $library_id" >&2; exit 1; }
  path_key="$library_path"
  [[ "$library_path" =~ ^[A-Za-z]:[\\/] || "$library_path" =~ ^\\\\ ]] && path_key="${library_path,,}"
  [[ -z "${seen_library_paths[$path_key]:-}" ]] || { echo "Duplicate external asset library path: $library_path" >&2; exit 1; }
  seen_library_ids[$library_id]=1
  seen_library_paths[$path_key]=1
done

selected=()
for name in "${styles[@]}"; do
  normalized_name="${name//-/_}"
  normalized_name="${normalized_name// /_}"
  upper_name="${normalized_name^^}"
  template_path="$opencaw_root/.styles/${upper_name}.md"
  if [[ ! -f "$template_path" ]]; then
    echo "Missing style template: $template_path" >&2
    exit 1
  fi
  for existing in "${selected[@]:-}"; do
    [[ "$existing" != "$upper_name" ]] || { echo "Duplicate style template: $upper_name" >&2; exit 1; }
  done
  selected+=("$upper_name")
done

primary_pipeline="$(art_pipeline_normalize "${primary_pipeline:-CSS3}")" || {
  echo "Unknown art pipeline: ${primary_pipeline:-CSS3}" >&2
  exit 1
}

allowed_pipelines=("$primary_pipeline")
for raw in "${allowed_pipeline_inputs[@]:-}"; do
  [[ -n "$raw" ]] || continue
  pipeline="$(art_pipeline_normalize "$raw")" || { echo "Unknown art pipeline: $raw" >&2; exit 1; }
  duplicate=0
  for existing in "${allowed_pipelines[@]}"; do
    [[ "$existing" != "$pipeline" ]] || duplicate=1
  done
  [[ $duplicate -eq 0 ]] || { echo "Duplicate allowed art pipeline: $pipeline" >&2; exit 1; }
  allowed_pipelines+=("$pipeline")
done

for pipeline in "${allowed_pipelines[@]}"; do
  relative="$(art_pipeline_contract_relative_path "$pipeline")"
  [[ -f "$opencaw_root/$relative" ]] || { echo "Missing art pipeline contract: $opencaw_root/$relative" >&2; exit 1; }
done

{
  echo "# STYLE.md"
  echo
  echo "This file is the canonical art style contract for this repository."
  echo
  echo "Generated from OpenCaw style templates:"
  for name in "${selected[@]}"; do
    echo "- $name"
  done
  echo
  echo "Primary OpenCaw art pipeline:"
  echo "- $primary_pipeline"
  echo
  echo "Allowed OpenCaw art pipelines:"
  for pipeline in "${allowed_pipelines[@]}"; do
    echo "- $pipeline"
  done
  echo
  echo "---"
  echo

  echo "## Art Pipeline Policy"
  echo
  echo "- Use $primary_pipeline unless the current user prompt explicitly selects another registered art pipeline."
  echo "- A prompt override applies only to that task and does not rewrite this STYLE.md."
  echo "- Stop if the selected pipeline is unavailable or fails. Never switch or fall back to another pipeline silently."
  echo

  if [[ ${#external_library_ids[@]} -gt 0 ]]; then
    echo "## External Asset Libraries"
    echo
    echo "Configured read-only library roots:"
    for index in "${!external_library_ids[@]}"; do
      echo "- ${external_library_ids[$index]}: \`${external_library_paths[$index]}\`"
    done
    echo
    echo "### External Asset Library Policy"
    echo
    echo "- Inspect configured external libraries before creating or downloading another 3D model, rig, or animation."
    echo "- Treat every configured external library as read-only. Never edit, rename, delete, generate into, or otherwise write beneath it."
    echo "- Copy each selected asset into \`assets/models/<library-id>/...\` before loading, importing, editing, executing, or using it."
    echo "- Use a repository-local copy as-is or as a template only when asset-level rights, the selected art pipeline, and repository architecture permit it."
    echo
  fi

  if [[ "$mode" == 'link' ]]; then
    echo "This document intentionally stays concise by referencing selected style and pipeline templates."
    echo
    echo "## Read Style Instructions"
    echo
    for name in "${selected[@]}"; do
      echo "Read \`${mount_path_from_host}/.styles/${name}.md\` instructions"
    done
    echo
    echo "## Read Art Pipeline Instructions"
    echo
    for pipeline in "${allowed_pipelines[@]}"; do
      relative="$(art_pipeline_contract_relative_path "$pipeline")"
      echo "Read \`${mount_path_from_host}/${relative}\` instructions"
    done
    echo
    echo "Add repository-specific art style instructions below these read directives."
  else
    echo "## Inlined Style Templates"
    echo
    for name in "${selected[@]}"; do
      template_path="$opencaw_root/.styles/${name}.md"
      echo "<!-- BEGIN TEMPLATE: ${name} -->"
      echo
      cat "$template_path"
      echo
      echo "<!-- END TEMPLATE: ${name} -->"
      echo
      echo "---"
      echo
    done
    echo "## Inlined Art Pipeline Templates"
    echo
    for pipeline in "${allowed_pipelines[@]}"; do
      relative="$(art_pipeline_contract_relative_path "$pipeline")"
      echo "<!-- BEGIN ART PIPELINE: ${pipeline} -->"
      echo
      cat "$opencaw_root/$relative"
      echo
      echo "<!-- END ART PIPELINE: ${pipeline} -->"
      echo
    done
  fi
} > "$style_target"

echo "Wrote $style_target"
if [[ "$mode" == 'link' ]]; then
  echo "Mode: link (default)."
else
  echo "Mode: inline."
fi
