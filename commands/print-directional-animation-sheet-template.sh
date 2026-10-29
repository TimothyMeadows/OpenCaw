#!/usr/bin/env bash
set -euo pipefail

character_name="${1:-character}"
direction_count="${2:-8}"
frames_per_action="${3:-15}"
cell_size="${4:-128}"
layout_profile="${5:-action-separated}"

case "$direction_count" in
  4)
    directions="north east south west"
    ;;
  6)
    directions="north north-east south-east south south-west north-west"
    ;;
  8)
    directions="north north-east east south-east south south-west west north-west"
    ;;
  16)
    directions="north north-north-east north-east east-north-east east east-south-east south-east south-south-east south south-south-west south-west west-south-west west west-north-west north-west north-north-west"
    ;;
  *)
    directions="custom-direction-1 custom-direction-2 custom-direction-3"
    ;;
esac

if [[ "$direction_count" =~ ^[0-9]+$ && "$frames_per_action" =~ ^[0-9]+$ && "$cell_size" =~ ^[0-9]+$ ]]; then
  sheet_width=$((frames_per_action * cell_size))
  sheet_height=$((direction_count * cell_size))
else
  sheet_width="custom"
  sheet_height="custom"
fi

cat <<EOF
# Directional Animation Sheet Plan: ${character_name}

## Summary
- Active STYLE.md templates:
- Direction count: ${direction_count}
- Directions: ${directions}
- Frames per action: ${frames_per_action}
- Cell size: ${cell_size}x${cell_size}
- Sheet dimensions: ${sheet_width}x${sheet_height}
- Packaging: ${layout_profile}
- Anchor/contact point:
- Source path:
- Runtime export path:
- Target engine/runtime:

## Sky-Knight-Compatible Defaults
Use this profile when the project wants sheets like assets/sky-knight.

- one action per PNG
- 8 direction rows
- 15 frame columns
- 128x128 cells
- 1920x1024 sheet size
- transparent PNG background
- kebab-case action filenames

## Sheet Layout
| Field | Value |
| --- | --- |
| row_order | direction-first |
| column_order | frame sequence |
| row_count | ${direction_count} |
| column_count | ${frames_per_action} |
| transparent_padding |  |
| atlas_padding |  |
| pivot |  |
| foot_anchor |  |
| shadow_layer |  |
| equipment_layers |  |
| naming_pattern |  |

## Action States
| Action | Frames | Frame Duration | Loop | Event Frames | Notes |
| --- | --- | --- | --- | --- | --- |
| idle |  |  | yes |  |  |
| walk |  |  | yes | footstep |  |
| run |  |  | yes | footstep |  |
| attack |  |  | no | anticipation, hit, recovery |  |
| cast |  |  | no | cast_start, release |  |
| hit |  |  | no | impact |  |
| death |  |  | no | death_end |  |
| interact |  |  | no | interact |  |

## Action Files
Use one row set per direction inside each action file when using action-separated sheets.

- idle.png
- walk.png
- run.png
- run-backwards.png
- strafe-left.png
- strafe-right.png
- crouch-idle.png
- crouch-run.png
- melee.png
- melee-2.png
- melee-run.png
- melee-spin.png
- kick.png
- pummel.png
- cast-spell.png
- shield-block-start.png
- shield-block-mid.png
- take-damage.png
- die.png
- slide-start.png
- slide.png
- slide-end.png
- rolling.png
- front-flip.png
- 180-turn.png
- unsheath-sword.png
- special-1.png
- special-2.png

## Isometric Fields
- projection:
- tile_scale:
- elevation_step:
- facing_angle_policy:
- mirrored_frames_allowed:
- depth_sort_contact_point:
- contact_shadow_policy:

## Runtime Metadata
- animation_names:
- direction_to_row_map:
- action_to_row_map:
- frame_rate:
- hitbox_policy:
- hurtbox_policy:
- attachment_points:
- VFX_spawn_points:

## Validation
- anchor stability:
- facing readability:
- silhouette check:
- animation timing check:
- sorting check:
- terrain/background contrast check:
- UI overlay readability check:
- style contract check:
- licensing/source check:
EOF
