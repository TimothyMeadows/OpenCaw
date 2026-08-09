#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/print-blender-production-brief.sh <asset-kind> <target> --profile <static-asset|rigged-actor|procedural-scene|render-scene|simulation>

Prints a deterministic Blender 4.5 LTS production brief to stdout.
EOF
}

[[ "${1:-}" != "-h" && "${1:-}" != "--help" ]] || { usage; exit 0; }
[[ $# -ge 4 ]] || { usage >&2; exit 1; }
asset_kind="$1"
target="$2"
shift 2
profile=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      [[ $# -ge 2 && -z "$profile" ]] || { echo "--profile requires one value." >&2; exit 1; }
      profile="$2"
      shift 2
      ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

[[ -n "$asset_kind" && "$asset_kind" != *$'\n'* && "$asset_kind" != *$'\r'* ]] || { echo "asset-kind must be one non-empty line." >&2; exit 1; }
[[ -n "$target" && "$target" != *$'\n'* && "$target" != *$'\r'* ]] || { echo "target must be one non-empty line." >&2; exit 1; }
case "$profile" in
  static-asset|rigged-actor|procedural-scene|render-scene|simulation) ;;
  *) echo "Unsupported Blender production profile: $profile" >&2; exit 1 ;;
esac

cat <<EOF
# Blender production brief

- Asset kind: $asset_kind
- Target: $target
- Profile: $profile
- Supported Blender: 4.5 LTS
- Authoring backend: unresolved (compatible connected Blender tool required)
- Source .blend: unresolved immutable repository-relative path
- Working copy: unresolved repository-relative path
- Backup checkpoints: unresolved repository-relative path
- Staging output: unresolved repository-relative path
- Runtime output: unresolved repository-relative path or not applicable
- Active STYLE.md: required for visual decisions
- Active MEDIA.md: required only for generated or rendered media
- Delivery format: unresolved
- Geometry/material/texture/render budgets: unresolved
- Required views and acceptance evidence: unresolved
- Human promotion review: required
EOF
