---
name: direct-blender-production
description: Direct safe Blender 4.5 LTS production from a repository-confined brief through staged, reviewed handoff. Use when starting, resuming, coordinating, or choosing a backend for Blender modeling, texturing, procedural, rigging, simulation, lighting, rendering, or export work.
---

# Direct Blender Production

## When to use

Use when a Blender production request spans multiple art stages, needs backend selection or resumption, or requires checkpoint, staging, inspection, and handoff ownership.

## Workflow

1. Read the repository architecture, active `STYLE.md`, and `MEDIA.md` only when generated or rendered media is in scope.
2. Run `./commands/print-blender-production-brief.sh <asset-kind> <target> --profile <profile>` and resolve every open field before authoring.
3. Preserve the source `.blend`; create declared working, backup, staging, and runtime destinations inside the repository.
4. Select one backend. Prefer typed connected Blender operations; use an exact validated `bpy` script only when typed operations are insufficient.
5. Route work through the applicable stage skills and record checkpoints at stage boundaries.
6. Inspect the working scene, validate its report, stage renders or exports, and wait for human review before promotion.

Read [production-session-contract.md](references/production-session-contract.md) for backend, checkpoint, and handoff rules.

## Guardrails

- Support Blender 4.5 LTS only; never install Blender, addons, packages, or providers.
- If no compatible connected tool exists, continue with briefs and read-only CLI inspection but block live authoring.
- Never mutate the source file, silently switch backends, or promote unreviewed output.
