# Visual review contract

## Required evidence

Select views by profile:

- Static asset: orthographic sides, perspective, silhouette, wireframe, close shading, pivot and scale context.
- Rigged actor: bind pose, weighted extremes, action contacts, root motion, sockets, detachable equipment, and runtime representative view.
- Procedural scene: minimum, representative, maximum, repeated-seed, and realized or export candidate.
- Render scene: neutral diagnostic, final cameras, aspect variants, representative frames, passes, alpha, and composite.
- Simulation: diagnostic start, contact, peak action, completion, restart, cache replay, and loop seam when applicable.

For source matching, use the [reference comparison contract](../../direct-blender-production/references/reference-comparison-contract.md). Lock projection/framing, neutral-light exposure and target display size; include required feature close-ups and the independently re-imported export. Separate observed source features from inferred hidden construction. Review structure before surface detail and keep visible remaining defects in the verdict.

Add subject-specific evidence when applicable: mechanism pivots/clearance and gear contact; facial or creature deformation extremes; hair-card/foliage coverage and alpha at distance; kit corners/junctions; cloth pins, settling and cache replay. Unneeded checks are explicitly not applicable, while required unavailable checks remain blocked/not-run. Review complete motion and transitions rather than infer them from stills.

## Defects and verdict

Every defect has severity, stable code, subject, evidence, impact, owner, correction, and retest condition. `error` blocks delivery; `warning` is a bounded risk requiring explicit acceptance; `info` records context.

Issue one verdict: `ship`, `ship-with-warnings`, or `block`. Bind it to source and staged-output hashes. Reference comparison measures declared properties and must not direct reproduction of protected identity or distinctive expression.
