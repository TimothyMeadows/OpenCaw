# Rigid static normal export contract

Contract identifier: `opencaw-rigid-static-normals/v1`.

This contract applies to the fixed rigid-parts finisher's static GLB export.
It distinguishes preservation of the working mesh, serialization into glTF,
and the approximations introduced by importing glTF into another DCC mesh.
It does not establish geometric-normal accuracy or visual acceptance.

## Working mesh preservation

Preserve the LOW mesh's original local geometry and raw/decoded corner-normal
data when placing it under its semantic pivot. Use an explicit child transform
instead of rewriting local vertices and normals. Reject unsupported relative
shear. Parent/frame changes must preserve world positions within one micrometre
and world normal components within `2e-5`.

UV packing operates on a temporary helper. Verify the real LOW meshes before
and after UV scatter, including their original raw/decoded normal data. Helper
coverage normals belong to its geometric coverage bake, not to runtime shading.
Failed packing restores owned state and does not produce an accepted mesh.

## Stored GLB verification

Before export, capture each explicitly selected mesh's local position, normal,
UV, material and frame correspondence. Bind that context with hashes and verify
that export leaves its source data unchanged. Output normals must never be used
to construct their own expectations.

The audited native exporter rounds normal components to four decimals in
float32, normalizes them in float32 and maps axes into glTF's Y-up frame. Verify
the installed exporter implementation hashes before relying on that codec.
An unrecognized revision blocks this check until it is separately audited.

Compare every actual indexed NORMAL corner against the independently derived
codec result at `2e-5` maximum component residual in both local and independently
transformed world frames. Check finite values, unit representation, oriented
position/material/UV ancestry, accessor ranges and complete mesh coverage.
Numeric equality and bit equality are distinct; record signed-zero differences.
Reject missing, changed, stale, ambiguous or unsupported data, including output
attributes or extensions whose correspondence the checker cannot establish.
This route supports its declared static applied meshes and static hierarchy;
it does not silently discard colors, morphs, skins or animation.

Record actual source-to-codec and source-to-stored directional loss for every
indexed corner. A zero codec residual is not zero source loss. This contract
does not certify a geometric-normal error limit; any separately required limit
needs its own measurement and acceptance.

## Independent native reimport and acceptance

Keep the native geometry, UV, material, hierarchy, pivot, bounds and collision
checks. Report DCC normal reencoding differences and the original strict normal
comparison outcome separately. Preserve the strict `verify_corners` routine for
consumers that require it; never relabel a failing DCC comparison as lossless.

Hash the actual exported bytes and retain the source-context identity, installed
codec pins, options, residuals and directional-loss measurements in the report.
Small fixtures and structural checks cannot approve metal shading, source
likeness, animation or runtime quality. Independent review and the separate
human production gates remain required.
