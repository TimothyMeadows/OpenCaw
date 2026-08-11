#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/validate-style-contract.sh [STYLE.md]

Validates that a host STYLE.md references existing OpenCaw .styles templates.
Defaults to ../STYLE.md when run from the mounted OpenCaw directory.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/memory-common.sh"
source "$script_dir/lib/art-pipeline-common.sh"
source "$script_dir/lib/external-asset-library-common.sh"
opencaw_resolve_paths
opencaw_root="$OPENCAW_ROOT"
host_root="$OPENCAW_PROJECT_ROOT_RESOLVED"
styles_dir="$opencaw_root/.styles"
pipelines_dir="$styles_dir/.pipelines"
index_file="$styles_dir/INDEX.md"
style_file="${1:-$host_root/STYLE.md}"

if [[ ! -f "$style_file" ]]; then
  echo "Missing STYLE.md: $style_file" >&2
  exit 1
fi

if [[ ! -d "$styles_dir" ]]; then
  echo "Missing styles directory: $styles_dir" >&2
  exit 1
fi

if [[ ! -f "$index_file" ]]; then
  echo "Missing styles index: $index_file" >&2
  exit 1
fi

status=0

if ! awk '{ sub(/\r$/, ""); if ($0 == "# STYLE.md") found=1 } END { exit !found }' "$style_file"; then
  echo "STYLE.md is missing the expected top-level heading." >&2
  status=1
fi

mapfile -t selected_styles < <(
  awk '
    /^Generated from OpenCaw style templates:/ { in_list=1; next }
    /^Primary OpenCaw art pipeline:/ { in_list=0 }
    in_list && /^- / {
      sub(/^- /, "")
      gsub(/\r$/, "")
      print
    }
  ' "$style_file"
)

mapfile -t primary_pipelines < <(
  awk '
    /^Primary OpenCaw art pipeline:/ { in_list=1; next }
    /^Allowed OpenCaw art pipelines:/ { in_list=0 }
    in_list && /^- / { sub(/^- /, ""); sub(/\r$/, ""); print }
  ' "$style_file"
)

mapfile -t allowed_pipelines < <(
  awk '
    /^Allowed OpenCaw art pipelines:/ { in_list=1; next }
    /^---$/ { in_list=0 }
    in_list && /^- / { sub(/^- /, ""); sub(/\r$/, ""); print }
  ' "$style_file"
)

if [[ ${#selected_styles[@]} -eq 0 ]]; then
  echo "STYLE.md does not list any generated OpenCaw style templates." >&2
  status=1
fi

if [[ ${#primary_pipelines[@]} -ne 1 ]]; then
  echo "STYLE.md must list exactly one primary OpenCaw art pipeline." >&2
  status=1
fi

if [[ ${#allowed_pipelines[@]} -eq 0 ]]; then
  echo "STYLE.md must list at least one allowed OpenCaw art pipeline." >&2
  status=1
fi

declare -A seen_pipelines=()
for pipeline in "${allowed_pipelines[@]:-}"; do
  if ! canonical="$(art_pipeline_normalize "$pipeline")" || [[ "$canonical" != "$pipeline" ]]; then
    echo "Invalid canonical art pipeline in STYLE.md: $pipeline" >&2
    status=1
    continue
  fi
  if [[ -n "${seen_pipelines[$pipeline]:-}" ]]; then
    echo "Duplicate allowed art pipeline in STYLE.md: $pipeline" >&2
    status=1
  fi
  seen_pipelines[$pipeline]=1
  relative="$(art_pipeline_contract_relative_path "$pipeline")"
  [[ -f "$opencaw_root/$relative" ]] || { echo "Missing referenced art pipeline contract: $relative" >&2; status=1; }
  grep -Fq -- "- \`$pipeline\`" "$pipelines_dir/INDEX.md" || { echo "Art pipeline is not indexed: $pipeline" >&2; status=1; }
done

if [[ ${#primary_pipelines[@]} -eq 1 ]]; then
  primary_pipeline="${primary_pipelines[0]}"
  if [[ -z "${seen_pipelines[$primary_pipeline]:-}" ]]; then
    echo "Primary art pipeline is not present in the allowed pipeline list: $primary_pipeline" >&2
    status=1
  fi
fi

for style_name in "${selected_styles[@]}"; do
  template_path="$styles_dir/${style_name}.md"
  if [[ ! "$style_name" =~ ^[A-Z0-9]+(_[A-Z0-9]+)*$ ]]; then
    echo "Invalid style template name in STYLE.md: $style_name" >&2
    status=1
    continue
  fi

  if [[ ! -f "$template_path" ]]; then
    echo "Missing referenced style template: $template_path" >&2
    status=1
  fi

  if ! grep -q -- "- ${style_name}" "$index_file"; then
    echo "Referenced style template is not listed in .styles/INDEX.md: $style_name" >&2
    status=1
  fi
done

if grep -q '^This document intentionally stays concise by referencing selected style and pipeline templates\.' "$style_file"; then
  for style_name in "${selected_styles[@]}"; do
    if ! grep -q "\.styles/${style_name}\.md" "$style_file"; then
      echo "Link-mode STYLE.md is missing a read directive for: $style_name" >&2
      status=1
    fi
  done
  for pipeline in "${allowed_pipelines[@]:-}"; do
    relative="$(art_pipeline_contract_relative_path "$pipeline")"
    grep -Fq "$relative" "$style_file" || { echo "Link-mode STYLE.md is missing a pipeline read directive for: $pipeline" >&2; status=1; }
  done
fi

mapfile -t read_directives < <(
  grep -Eo '\.styles/[A-Z0-9_]+\.md' "$style_file" | sed 's#^.styles/##; s#\.md$##' | sort -u
)

for directive_style in "${read_directives[@]}"; do
  if [[ ! -f "$styles_dir/${directive_style}.md" ]]; then
    echo "STYLE.md read directive points to a missing style template: $directive_style" >&2
    status=1
  fi
done

grep -Eiq 'prompt override.*does not rewrite|prompt.*does not rewrite.*STYLE\.md' "$style_file" || {
  echo "STYLE.md lacks the task-local prompt override rule." >&2
  status=1
}
grep -Eiq 'never (switch or )?fall back.*silently|never.*silently.*fall back' "$style_file" || {
  echo "STYLE.md lacks the no-silent-fallback rule." >&2
  status=1
}

external_library_heading_count="$(grep -Ec '^## External Asset Libraries\r?$' "$style_file" || true)"
if [[ "$external_library_heading_count" -gt 1 ]]; then
  echo 'STYLE.md contains more than one External Asset Libraries section.' >&2
  status=1
fi

external_library_entries_output=''
if ! external_library_entries_output="$(external_asset_library_entries "$style_file")"; then
  status=1
fi
external_library_ids=()
external_library_paths=()
while IFS=$'\t' read -r library_id library_path; do
  [[ -n "$library_id" ]] || continue
  external_library_ids+=("$library_id")
  external_library_paths+=("$library_path")
done <<< "$external_library_entries_output"

if [[ "$external_library_heading_count" -eq 1 && ${#external_library_ids[@]} -eq 0 ]]; then
  echo 'External Asset Libraries section must contain at least one configured library.' >&2
  status=1
fi

declare -A seen_external_library_ids=()
declare -A seen_external_library_paths=()
for index in "${!external_library_ids[@]}"; do
  library_id="${external_library_ids[$index]}"
  library_path="${external_library_paths[$index]}"
  external_asset_library_validate_id "$library_id" || status=1
  external_asset_library_validate_path "$library_path" || status=1
  if [[ -n "${seen_external_library_ids[$library_id]:-}" ]]; then
    echo "Duplicate external asset library id in STYLE.md: $library_id" >&2
    status=1
  fi
  path_key="$library_path"
  [[ "$library_path" =~ ^[A-Za-z]:[\\/] || "$library_path" =~ ^\\\\ ]] && path_key="${library_path,,}"
  if [[ -n "${seen_external_library_paths[$path_key]:-}" ]]; then
    echo "Duplicate external asset library path in STYLE.md: $library_path" >&2
    status=1
  fi
  seen_external_library_ids[$library_id]=1
  seen_external_library_paths[$path_key]=1
done

if [[ ${#external_library_ids[@]} -gt 0 ]]; then
  grep -Eiq 'external librar(y|ies).*before creating or downloading|before creating or downloading.*external librar(y|ies)' "$style_file" || {
    echo 'STYLE.md external asset policy must prefer configured libraries before creating or downloading models.' >&2
    status=1
  }
  grep -Eiq 'external librar(y|ies).*read-only|read-only.*external librar(y|ies)' "$style_file" || {
    echo 'STYLE.md external asset policy must declare libraries read-only.' >&2
    status=1
  }
  grep -Eiq 'assets/models/.+before (loading|importing|editing)|before (loading|importing|editing).+assets/models/' "$style_file" || {
    echo 'STYLE.md external asset policy must require copying into assets/models before use.' >&2
    status=1
  }
fi

if [[ $status -eq 0 ]]; then
  echo "Style contract validation passed."
  printf 'Referenced styles:'
  for style_name in "${selected_styles[@]}"; do
    printf ' %s' "$style_name"
  done
  printf '\n'
  printf 'Primary art pipeline: %s\n' "${primary_pipelines[0]}"
  printf 'Allowed art pipelines:'; printf ' %s' "${allowed_pipelines[@]}"; printf '\n'
  printf 'External asset libraries:'
  if [[ ${#external_library_ids[@]} -eq 0 ]]; then printf ' none'; else printf ' %s' "${external_library_ids[@]}"; fi
  printf '\n'
fi

exit $status
