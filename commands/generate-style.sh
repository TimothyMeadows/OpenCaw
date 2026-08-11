#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/generate-style.sh [--inline] [--pipeline PIPELINE] [--allow-pipeline PIPELINE ...] "<STYLE1>" ["STYLE2" ...]

Defaults to concise link-based output in ../STYLE.md.
CSS3 is the default primary art pipeline when --pipeline is omitted.
Use --inline to embed full style template contents.
EOF
}

mode='link'
styles=()
primary_pipeline=''
allowed_pipeline_inputs=()

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
opencaw_resolve_paths
opencaw_root="$OPENCAW_ROOT"
host_root="$OPENCAW_PROJECT_ROOT_RESOLVED"
mount_dir_name="$(basename "$opencaw_root")"
if [[ "$opencaw_root" == "$host_root" ]]; then mount_path_from_host='.'; else mount_path_from_host="./${mount_dir_name}"; fi
style_target="$host_root/STYLE.md"

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
