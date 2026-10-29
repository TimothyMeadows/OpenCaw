#!/usr/bin/env bash
set -euo pipefail

asset_type="${1:-game-art-asset}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/engine-common.sh"
resolve_args=()
[[ -z "${2:-}" ]] || resolve_args+=(--assert-engine "$2")
selection="$(engine_run resolve "${resolve_args[@]}")"
engine="$(printf '%s' "$selection" | sed -n 's/.*"effectiveEngine": "\([A-Z]*\)".*/\1/p')"

cat <<EOF
# Game Art Handoff: ${asset_type}

## Summary
- Owner role:
- Target engine/runtime: ${engine}
- Target scene/feature:
- Active STYLE.md templates:
- Source asset path:
- Runtime export path:

## Asset Metadata
| Field | Value |
| --- | --- |
| asset_id |  |
| asset_type | ${asset_type} |
| dimensions |  |
| frame_grid |  |
| atlas_key |  |
| padding |  |
| pivot |  |
| anchor/contact_point |  |
| sorting_layer/depth_key |  |
| collision_hint |  |
| animation_names |  |
| loop_rules |  |
| compression/export_format |  |
| license/source |  |

## Isometric Fields
Complete when the project uses an isometric or 2.5D style.

- projection:
- tile_width_depth:
- elevation_step:
- footprint:
- wall_floor_roof_layers:
- occlusion_strategy:
- walkability_notes:

## Validation
- STYLE.md checked:
- transparency/background checked:
- readability checked in scene:
- seams or loop checked:
- animation playback checked:
- sorting/occlusion checked:
- contrast/accessibility checked:
- performance budget checked:
- licensing checked:

## Downstream Responsibilities
- art:
- game design:
- engineering:
- QA:
- documentation:
EOF
