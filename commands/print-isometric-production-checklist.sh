#!/usr/bin/env bash
set -euo pipefail

asset_type="${1:-isometric-asset}"

cat <<EOF
Isometric production checklist: ${asset_type}
------------------------------------------
Use this before approving isometric or 2.5D game art.

style_contract_checked=false
projection_locked=false
tile_width_depth_documented=false
elevation_step_documented=false
camera_angle_documented=false
lighting_direction_consistent=false

anchors
- feet_or_base_anchor_defined=false
- pivot_exported=false
- contact_shadow_consistent=false
- prop_footprint_documented=false

layers_and_sorting
- floor_wall_roof_separated=false
- tall_props_sliced_when_needed=false
- occlusion_strategy_documented=false
- sorting_layer_or_depth_key_defined=false
- foreground_overlay_policy_defined=false

gameplay_readability
- walkable_ground_distinct=false
- blockers_distinct=false
- hazards_distinct=false
- doors_stairs_cover_interactables_distinct=false
- ui_markers_readable_over_asset=false
- character_readability_checked=false

runtime_handoff
- atlas_padding_defined=false
- transparent_background_ok=false
- collision_or_navigation_hints_documented=false
- engine_loader_assumptions_documented=false
- qa_scene_context_identified=false
EOF

echo
echo "Fail the asset if projection, anchors, sorting, or gameplay readability are unresolved."
