#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/inspect-blender-scene.sh <scene.blend> --root <repo> --profile <profile> [--blender <executable>] [--output <report>] [--replace] [--dry-run]

Runs Blender 4.5.x read-only with safe background flags and emits an
opencaw-blender-scene/v1 report. Live scene authoring is not supported.
EOF
}

[[ "${1:-}" != "-h" && "${1:-}" != "--help" ]] || { usage; exit 0; }
[[ $# -ge 1 ]] || { usage >&2; exit 1; }
scene="$1"; shift
root=""; profile=""; blender="blender"; output=""; replace="false"; dry_run="false"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) [[ $# -ge 2 && -z "$root" ]] || { echo "--root requires one path." >&2; exit 1; }; root="$2"; shift 2 ;;
    --profile) [[ $# -ge 2 && -z "$profile" ]] || { echo "--profile requires one value." >&2; exit 1; }; profile="$2"; shift 2 ;;
    --blender) [[ $# -ge 2 && "$blender" == "blender" ]] || { echo "--blender requires one executable." >&2; exit 1; }; blender="$2"; shift 2 ;;
    --output) [[ $# -ge 2 && -z "$output" ]] || { echo "--output requires one path." >&2; exit 1; }; output="$2"; shift 2 ;;
    --replace) [[ "$replace" == "false" ]] || { echo "--replace may be provided once." >&2; exit 1; }; replace="true"; shift ;;
    --dry-run) [[ "$dry_run" == "false" ]] || { echo "--dry-run may be provided once." >&2; exit 1; }; dry_run="true"; shift ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done
case "$profile" in static-asset|rigged-actor|procedural-scene|render-scene|simulation) ;; *) echo "Unsupported Blender inspection profile: $profile" >&2; exit 1 ;; esac
[[ -n "$root" && -d "$root" && ! -L "$root" ]] || { echo "--root must be a non-symlink directory." >&2; exit 1; }
[[ -f "$scene" && ! -L "$scene" && "${scene,,}" == *.blend ]] || { echo "Scene must be a regular non-symlink .blend file." >&2; exit 1; }
[[ "$(realpath -s "$root")" == "$(realpath "$root")" ]] || { echo "Repository root path contains a symlink." >&2; exit 1; }
[[ "$(realpath -s "$scene")" == "$(realpath "$scene")" ]] || { echo "Scene path contains a symlink." >&2; exit 1; }
root_abs="$(realpath "$root")"
scene_abs="$(realpath "$scene")"
case "$scene_abs" in "$root_abs"/*) ;; *) echo "Scene escapes repository root." >&2; exit 1 ;; esac
scene_relative="${scene_abs#"$root_abs"/}"
[[ "$scene_relative" != *'..'* ]] || { echo "Unsafe scene path." >&2; exit 1; }

blender_bin="$(command -v "$blender" 2>/dev/null || true)"
if [[ -z "$blender_bin" && -f "$blender" && ! -L "$blender" ]]; then blender_bin="$(realpath "$blender")"; fi
[[ -n "$blender_bin" ]] || { echo "Blender executable not found: $blender" >&2; exit 1; }
version_output="$("$blender_bin" --version 2>&1)" || { echo "Unable to query Blender version." >&2; exit 1; }
version_line="${version_output%%$'\n'*}"
[[ "$version_line" =~ ^Blender[[:space:]]4\.5\.[0-9]+ ]] || { echo "Blender 4.5.x is required; found: $version_line" >&2; exit 1; }

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
inspector="$script_dir/lib/inspect-blender-scene.py"
[[ -f "$inspector" && ! -L "$inspector" ]] || { echo "Bundled scene inspector is unavailable." >&2; exit 1; }
output_abs=""
output_dir=""
if [[ -n "$output" ]]; then
  output_parent_input="$(dirname "$output")"
  [[ -d "$output_parent_input" && ! -L "$output_parent_input" ]] || { echo "Output parent must be an existing non-symlink directory." >&2; exit 1; }
  [[ "$(realpath -s "$output_parent_input")" == "$(realpath "$output_parent_input")" ]] || { echo "Output parent path contains a symlink." >&2; exit 1; }
  if [[ -e "$output" ]]; then
    [[ -f "$output" && ! -L "$output" ]] || { echo "Output must be a regular non-symlink file." >&2; exit 1; }
    [[ "$(realpath -s "$output")" == "$(realpath "$output")" ]] || { echo "Output path contains a symlink." >&2; exit 1; }
    [[ "$replace" == "true" ]] || { echo "Output exists; use --replace to overwrite it." >&2; exit 1; }
    output_abs="$(realpath "$output")"
    output_dir="$(dirname "$output_abs")"
  else
    output_dir="$(dirname "$output")"
    output_dir="$(realpath "$output_dir")"
    output_abs="$output_dir/$(basename "$output")"
  fi
  case "$output_abs" in "$root_abs"/*) ;; *) echo "Output escapes repository root." >&2; exit 1 ;; esac
  [[ "$output_abs" != "$scene_abs" ]] || { echo "Output must not replace the scene." >&2; exit 1; }
fi

if [[ "$dry_run" == "true" ]]; then
  printf 'Blender: %s\nVersion: %s\nScene: %s\nProfile: %s\nOutput: %s\nFlags: --background --factory-startup --disable-autoexec --offline-mode --python-exit-code 4\n' "$blender_bin" "$version_line" "$scene_relative" "$profile" "${output_abs:-stdout}"
  exit 0
fi

temp_report=""
cleanup() { [[ -z "$temp_report" || ! -e "$temp_report" ]] || rm -f -- "$temp_report"; }
trap cleanup EXIT
if [[ -n "$output_abs" ]]; then temp_report="$(mktemp "$output_dir/.opencaw-blender-report.XXXXXX.tmp")"; else temp_report="$(mktemp "$root_abs/.opencaw-blender-report.XXXXXX.tmp")"; fi

root_arg="$root_abs"; scene_arg="$scene_abs"; inspector_arg="$inspector"; temp_arg="$temp_report"
if [[ "$blender_bin" == *.exe && -n "$(command -v wslpath 2>/dev/null || true)" ]]; then
  root_arg="$(wslpath -w "$root_abs")"; scene_arg="$(wslpath -w "$scene_abs")"; inspector_arg="$(wslpath -w "$inspector")"; temp_arg="$(wslpath -w "$temp_report")"
fi
"$blender_bin" --background --factory-startup --disable-autoexec --offline-mode "$scene_arg" --python-exit-code 4 --python "$inspector_arg" -- --root "$root_arg" --scene-relative "$scene_relative" --profile "$profile" --output "$temp_arg"
[[ -s "$temp_report" && ! -L "$temp_report" ]] || { echo "Blender did not produce a scene report." >&2; exit 1; }
"$script_dir/validate-blender-scene-report.sh" "$temp_report" --root "$root_abs" >/dev/null
if [[ -n "$output_abs" ]]; then mv -f -- "$temp_report" "$output_abs"; temp_report=""; printf '%s\n' "$output_abs"; else cat "$temp_report"; fi
