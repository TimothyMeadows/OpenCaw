# Cloth preparation and review

## Declare the deliverable

Choose whether cloth supplies a static draped mesh, a rendered sequence, a supported baked geometry cache or a reference for separately authored runtime motion. Do not assume an exported GLB contains Blender's solver, cloth settings or a portable runtime simulation. The selected engine owner must implement and verify any live cloth behavior explicitly.

Record physical dimensions, fabric response, target camera distance, attached regions, interaction range, expected contact, frame rate, simulation range and time/storage budgets. Include a settling interval and identify the reviewed delivery range separately. Resolve these settings from the brief rather than adopting arbitrary subdivision or solver-quality constants.

## Prepare source geometry

1. Preserve the authored source; create a declared working copy and independent simulation mesh when the render surface is too costly or unsuitable. Record how that mesh drives the rendered result and verify the correspondence after edits.
2. Inspect scale, normals, duplicated vertices, degenerate faces, self-intersections and narrow triangles. Use sufficient, reasonably even simulation spacing to express the required folds and pass through the intended gaps. A dense decorative render mesh is not automatically a suitable solver mesh.
3. Keep seams, intended openings and attachment regions explicit. Retain deliberate sewing edges when the selected construction uses them; do not remove every loose edge as generic cleanup. Explain any solver-specific geometry in the inspection evidence.
4. Define modifier ordering before baking. For armature-driven attachments, inspect the animated pre-cloth surface and pin targets throughout the range. Add render thickness and smoothing at the declared stage so their cost and collision effect are understood. Record the evaluated subdivision level; changing evaluation geometry invalidates the cache.

## Attachments and collision

Create a named pin group that matches actual fastenings. Review its weights visually and while the attachment moves: a gradual transition can avoid an abrupt rigid-to-free boundary, but must not turn a loose garment into a fully constrained shell. Confirm that pinned regions follow the intended owner and that no unrelated region is captured. Bind attachment animation, pin weights and modifier settings into cache ancestry.

Use separate, sufficiently simple collision surfaces where appropriate. Check their placement, normals, motion and coverage; mark intentional exclusions. Enable and configure the participating collider physics and restrict the collision set deliberately. Choose collision distances relative to subject scale, cloth spacing and required gaps. Inflating the distance until penetration disappears may leave the cloth visibly floating, while a very small distance can miss motion.

Select self-collision when required by visible folds and interaction, with an explicit cost allowance. Inspect excluded collision groups rather than assuming every group name means inclusion. For fast or tightly confined motion, diagnose temporal resolution, collision iterations, initial intersections and geometry before increasing quality blindly. Stop a nonconverging diagnostic rather than masking instability with a more expensive final bake.

## Diagnostic sequence

Run a bounded low-cost sequence that includes the following applicable cases:

- Settle from a plausible initial state without interpenetration; move attachments into their starting pose gradually when needed.
- Exercise the strongest intended acceleration, turn, contact or gust, plus a quiet interval that exposes persistent jitter.
- Inspect attachment stretching, body penetration, floating gaps, tunneling, trapped folds, surface inversion and energy growth. Compare close contact views with the target-camera result.
- Check the transition from settling to delivery. A desired loop needs a reviewed seam; simply trimming the simulation or repeating its first frame does not create continuous cloth motion.

Correct the source geometry, attachment setup or settings responsible for a defect, invalidate the old cache and rebake a new version. Keep the failed evidence. Do not depend on unsupported cached-mesh editing or hide missing frames by relabeling the result complete.

## Final cache and review

Use the existing [simulation bake contract](simulation-bake-contract.md) for repository-local cache paths, input/settings fingerprints, file inventories, completion and clean-session replay. Preserve failed or superseded versions. Free only the declared working cache when a rebuild is required; never clear unrelated cache storage.

Reopen the saved working scene, resolve the exact final cache and replay the reviewed range without relying on an earlier interactive session. Check expected frame coverage, current source/settings identities, attachment and collision behavior, and representative rendered or exported output. A final-quality change requires new evidence even if the low-cost diagnostic passed. If exact rerun determinism is unavailable, state the tested replay/reproducibility limits rather than claiming bit-identical solver results.

Deliver the editable setup, accepted cache or frozen result, dependency inventory, diagnostic/final settings and defect review. Human acceptance and runtime promotion remain separate. Missing caches, changed input hashes, incomplete ranges or unavailable target support block the affected handoff.

## Blender 4.5 references

- [Cloth shape settings](https://docs.blender.org/manual/en/4.5/physics/cloth/settings/shape.html): pinning, rest-shape and attachment choices.
- [Cloth collisions](https://docs.blender.org/manual/en/4.5/physics/cloth/settings/collisions.html): participating objects, distances, quality and exclusions.
- [Collision settings API](https://docs.blender.org/api/4.5/bpy.types.ClothCollisionSettings.html): version-qualified property semantics, not authorization to execute scripts.
- [Cloth cache](https://docs.blender.org/manual/en/4.5/physics/cloth/settings/cache.html): bake invalidation and subdivision consistency.
