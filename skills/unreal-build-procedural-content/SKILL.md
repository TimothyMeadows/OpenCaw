---
name: unreal-build-procedural-content
description: Author Unreal PCG and procedural geometry with explicit plugins, deterministic inputs, owned generated resources and verified regeneration.
engines: [UNREAL]
---

# Unreal Build Procedural Content

## When to use

Build or revise PCG graphs, procedural geometry and repeatable content-generation workflows inside an Unreal project. Use this skill for generator inputs, output ownership and regeneration; world streaming and ordinary authored asset imports retain their own responsibilities.

## Activation and inputs

Run `commands/resolve-engine.sh` and `commands/resolve-skill.sh unreal-build-procedural-content`; require effective `UNREAL` and `compatible: true` before edits or tools. Honor validated task overrides and output boundaries; record discovered context under `.hephaera/.cache` without replacing `ENGINE.md`.

Inspect actual engine/plugin versions and explicitly selected PCG, Geometry Script, Dynamic Mesh or other implementations. Their runtime/editor availability differs by release and target. Do not enable a plugin, install middleware or switch a CPU graph to GPU execution implicitly. Record generation domain, seed policy, source rights, recipe hash, output types, geometry/collision/texture budgets and authority.

## Workflow

1. Read [determinism and resource ownership](references/determinism-and-resources.md) for the chosen generator. Prefer a small controlled graph/mesh fixture before running a large world recipe.
2. Define reproducible input ordering, coordinate space, seed derivation and stable instance identities. Record external sampling dependencies and version limitations; a seed alone cannot reproduce changed source geometry or graph settings.
3. Author real graph, mesh and material packages through matching native tools. Keep source inputs immutable and generated outputs separately owned; regeneration must not erase authored decoration or edits outside its declared domain.
4. Select editor-baked versus runtime generation deliberately. Bind completion, cleanup and cancellation to the owning world/actor generation; avoid publishing partial geometry or stale callbacks after teardown.
5. Validate topology, normals/tangents, UV/material assignments, collision, navigation and platform support as applicable. Build/cook only intended resources and retain ancestry/recipe evidence for any baked artifacts.

## Verification and output

Deliver the native generator/graph and intended outputs with input/recipe hashes, selected dependencies, resource counts and performance evidence. Compare repeated same-input runs; alter one seed or source input and verify the intended change. Exercise regeneration, cancellation, owner destruction, streaming unload and restoration, checking for duplicated instances, leaked generated resources and damaged authored content.

A nonempty, stable output and native completion evidence are required; a graph that never executes cannot pass. Missing Editor/plugin/assets block the affected native check. Headless CPU fixture results cannot establish GPU graph correctness, final art quality or packaged-world performance.
