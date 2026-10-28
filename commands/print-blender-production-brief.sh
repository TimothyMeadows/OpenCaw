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
- Applicability: mark unused fields not applicable with a reason; required unavailable work stays blocked/not-run
- Supported Blender: 4.5 LTS
- Authoring backend: unresolved (compatible connected Blender tool required)
- Source .blend: unresolved immutable repository-relative path
- Working copy: unresolved repository-relative path
- Backup checkpoints: unresolved repository-relative path
- Staging output: unresolved repository-relative path
- Runtime output: unresolved repository-relative path or not applicable
- Active STYLE.md: required for visual decisions
- Active MEDIA.md: required only for generated or rendered media
- Selected ENGINE.md and importer/shader versions: unresolved or not applicable to non-runtime output
- Original/reference rights and immutable identities: unresolved
- Observed features, inferred hidden structure and uncertainties: unresolved
- Construction method and independently moving assemblies: unresolved or not applicable
- Detail priorities at target camera distance: unresolved
- Comparison cameras, neutral lighting and feature close-ups: unresolved
- Delivery format: unresolved
- Geometry/material/texture/render budgets: unresolved
- Required views and acceptance evidence: unresolved
- Blocked/not-run checks and remaining defects: unresolved
- Human promotion review: required
EOF

case "$profile" in
  static-asset)
    cat <<'EOF'
- Primary masses, relevant seams and wall thickness: unresolved or not applicable
- Mechanism pivots, contact/clearance and concealed surfaces: unresolved or not applicable
- High/low identities, UV density, bake settings and target texture channels: unresolved or not applicable
EOF
    ;;
  rigged-actor)
    cat <<'EOF'
- Skinned/articulated/rigid profile and actual model readiness: unresolved
- Bind pose, axes, control/deform ownership and attachment identities: unresolved
- Subject-specific deformation extremes, contacts and complete motion review: unresolved
EOF
    ;;
  procedural-scene)
    cat <<'EOF'
- Module dimensions, grid, pivots and corner/junction coverage: unresolved or not applicable
- Node-group inputs/outputs, seed, stable IDs and worst-case bounds: unresolved or not applicable
- Instance/realization policy, regeneration and manual override ownership: unresolved
- Vegetation coverage, wind masks, alpha/overdraw and LOD review: unresolved or not applicable
EOF
    ;;
  render-scene)
    cat <<'EOF'
- Matched camera assumptions and locked exposure/color transform: unresolved
- Required passes, alpha interpretation and compositor ownership: unresolved
- Representative frames, temporal stability and output inventory: unresolved
EOF
    ;;
  simulation)
    cat <<'EOF'
- Solver, input geometry, collision proxies and diagnostic quality: unresolved
- Cloth density, pin gradients, collision separation and settling: unresolved or not applicable
- Cache owner/path, invalidation, storage budget and clean replay: unresolved
EOF
    ;;
esac
