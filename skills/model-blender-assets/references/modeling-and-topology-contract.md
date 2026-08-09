# Modeling and topology contract

## Construction choice

- Use direct or modifier-led hard-surface modeling for controlled planes and manufactured transitions.
- Use organic surface modeling where edge flow and deformation are primary.
- Use sculpt-and-retopology when high-frequency form exploration exceeds the target topology budget.
- Use modular pieces when repetition, reuse, or procedural assembly is part of the target.

## Topology acceptance

Record object scale, vertex/edge/face/triangle totals, manifold policy, ngon policy, normals, UV readiness, and required deformation zones. Check duplicate vertices, zero-area faces, loose geometry, self-intersection, non-manifold edges, inverted normals, accidental internal surfaces, extreme poles, and unsupported modifiers.

Quads are not an absolute goal. Topology must instead support its next operation: deformation, subdivision, baking, shading, or static export. Triangulation policy must be stable before normal-map baking and final export.

## Required views

Review front, side, back, top, perspective silhouette, close shading, wireframe, and any deformation extremes. Compare blockout and final at target camera distance so detail does not mask proportion drift.
