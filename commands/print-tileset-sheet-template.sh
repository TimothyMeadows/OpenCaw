#!/usr/bin/env bash
set -euo pipefail

tileset_name="${1:-environment-tileset}"
orientation="${2:-isometric}"

cat <<EOF
# Tileset Sheet Plan: ${tileset_name}

## Summary
- Active STYLE.md templates:
- Orientation: ${orientation}
- Tile size:
- Elevation step:
- Atlas size target:
- Source path:
- Runtime export path:
- Target engine/runtime:

## Tile Families
| Family | Required Tiles | Notes |
| --- | --- | --- |
| base terrain | center, variants |  |
| terrain transitions | edges, corners, inner corners, diagonals |  |
| roads/paths | straight, corner, tee, cross, end caps |  |
| water/shore | water, shore edges, foam, deep/shallow variants |  |
| cliffs/elevation | wall bands, ledges, ramps, stairs |  |
| structures | floors, walls, doors, windows, roofs |  |
| vegetation/props | small, medium, tall, sliced variants |  |
| hazards/objectives | hazard, pickup, interactable, objective |  |

## Metadata
| Field | Value |
| --- | --- |
| tile_width |  |
| tile_height |  |
| grid_orientation | ${orientation} |
| collision_property |  |
| walkability_property |  |
| elevation_property |  |
| biome_property |  |
| atlas_padding |  |
| naming_pattern |  |

## Isometric Fields
- projection:
- footprint:
- base_anchor:
- wall_floor_roof_layer_policy:
- depth_sort_key:
- roof_or_tall_prop_slicing:

## Validation
- seam stress test:
- transition coverage:
- repeated-pattern check:
- collision overlay check:
- character readability check:
- UI marker readability check:
- style contract check:
- licensing/source check:
EOF
