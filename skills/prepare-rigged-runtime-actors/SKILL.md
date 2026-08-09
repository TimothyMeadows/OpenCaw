---
name: prepare-rigged-runtime-actors
description: Prepare, integrate, and verify rigged GLB or FBX characters and creatures as production runtime actors. Use when defining skeleton, animation, attachment, collider, asset-budget, provenance, loading, disposal, or gameplay-proof contracts for a skinned 3D actor.
---

# Prepare Rigged Runtime Actors

## When to use

- Converting a skinned character or creature from source art into a runtime package.
- Establishing scale, axes, pivots, grounding, bones, sockets, clips, or collider contracts.
- Diagnosing animation compatibility, equipment attachment, detachable-part, or lifecycle failures.
- Reviewing whether a rigged actor is ready for representative gameplay and shipment.

## Workflow

1. Read the active architecture, style, runtime asset, and gameplay contracts.
2. Keep the authored source immutable and produce a separately identified runtime artifact.
3. Freeze coordinates, skeleton identity, bind pose, bone names, socket ownership, and attachment behavior before integrating animation.
4. Define semantic clip roles, looping, root motion, contact events, and skeleton compatibility.
5. Define navigation, hurt, attack, and targeting colliders independently from the render mesh.
6. Measure geometry, skeleton, material, texture, and package budgets on a representative target.
7. Record provenance and verification in an `opencaw-rigged-actor/v1` manifest.
8. Run `./commands/validate-rigged-actor-manifest.sh <manifest> --root <repo>`; add `--require-verified` before claiming production readiness.

Read [runtime-actor-contract.md](references/runtime-actor-contract.md) when designing the handoff or diagnosing runtime behavior. Read [rigged-actor-manifest.md](references/rigged-actor-manifest.md) when authoring or validating the durable manifest.

## Output

- An immutable source asset and an optimized, versioned runtime asset.
- A validated skeleton, animation, attachment, collider, budget, and provenance contract.
- Loader and disposal ownership plus deterministic runtime and gameplay evidence.

## Guardrails

- Do not infer gameplay truth, hit timing, or collision from rendered geometry alone.
- Do not silently retarget clips across different skeleton identities.
- Do not overwrite source art with optimized output or discard provenance.
- Do not claim shipment readiness without repository-confined files, matching hashes, and complete verification evidence.
