# Hard-surface assemblies

## Establish construction

Start from approved dimensions, target cameras, material intent and required motion. Make a part ledger containing each part's identity, parent, function, visible boundaries, wall thickness, pivot/axis, permitted movement, neighboring clearance and geometry budget. Mark unseen construction as inference; a plausible mechanism does not establish what the source contains. A static product shell and an articulated mechanism need different delivery geometry.

Build the load-bearing volumes and outer silhouette first. Check their relative dimensions in orthographic and representative perspective views before adding openings or decoration. Resolve each seam as an actual part boundary, a shallow recess or texture detail according to its silhouette, parallax and motion requirements. Put detail that must move, cast a distinctive shadow or reveal a cavity into geometry. Keep finer surface pattern in the selected material/bake path when it survives the required camera distance.

## Author readable surfaces

1. Separate parts at real construction or articulation boundaries. Preserve joint interiors and undersides that become visible in motion; do not fuse adjacent parts simply to remove a shading seam.
2. Keep cutter objects and modifier ownership identifiable on the working copy. Check the evaluated result after Boolean operations for slivers, coplanar faces, lost cavities and broken material boundaries. Retain an editable source before applying delivery modifiers.
3. Set bevel width from physical edge size and intended highlight, then choose enough segments for the target view. Inspect narrow gaps and multi-edge intersections; overlap clamping can alter widths and does not prove uniform edge treatment. A shader bevel is not replacement silhouette geometry for a consumer that cannot reproduce it.
4. Choose sharp edges, smooth shading and normal treatment from the desired planes and curvature. Blender 4.5 uses current smooth-by-angle tooling; do not prescribe the removed legacy Auto Smooth checkbox. Weighted normals are an optional shading treatment, not a topology repair or mandatory final modifier.
5. Repeat manufactured elements through explicit spacing and ownership. Keep fasteners aligned with supporting surfaces, plates visibly layered, and gear teeth regular around their actual rotation centers. Avoid scattered decorative detail that obscures construction or intersects unrelated parts.

## Check articulation before detail approval

Verify the actual mesh pivots and full declared movement ranges, including adjacent panels, tubes, shafts and fasteners. For meshing gears, declare compatible tooth geometry, axis spacing, relative direction and rotation ratio; a decorative gear need not pretend to transmit motion. Do not substitute physics claims for an authored visual mechanism. Hand the ledger and visible clearance evidence to rigging/motion ownership before animation.

Deliver the editable assembly, evaluated candidate, part ledger and matched wide/close views. Review silhouette, highlight continuity, seam depth, wall thickness, cavity integrity and moving clearances in neutral light as well as final light. Record a defect against the responsible part and operation; reject filled cavities, doubled surfaces, smeared repeated detail or missing articulation even when the total triangle count passes.

## Blender references

- [Blender 4.5 Bevel modifier API](https://docs.blender.org/api/4.5/bpy.types.BevelModifier.html): width methods, segment count and overlap clamping.
- [Blender 4.1 modeling changes](https://developer.blender.org/docs/release_notes/4.1/modeling/): replacement of legacy Auto Smooth. Use the actual Blender 4.5 controls and inspect the evaluated result.

These are authoring decisions under the selected pipeline, not authorization to execute arbitrary scripts or alter a fixed finishing bundle.
