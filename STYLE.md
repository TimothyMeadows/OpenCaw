# STYLE.md

This file is the canonical art style contract for this repository.

Generated from Hephaera style templates:
- CEL_SHADED_COMIC

Primary Hephaera art pipeline:
- PROOF_TO_MODEL

Allowed Hephaera art pipelines:
- PROOF_TO_MODEL
- CLOUD
- LOCAL
- CODE
- BLENDER

---

## Art Pipeline Policy

- Use PROOF_TO_MODEL unless the current user prompt explicitly selects another registered art pipeline.
- A prompt override applies only to that task and does not rewrite this STYLE.md.
- Stop if the selected pipeline is unavailable or fails. Never switch or fall back to another pipeline silently.

This document intentionally stays concise by referencing selected style and pipeline templates.

## Read Style Instructions

Read `./.styles/CEL_SHADED_COMIC.md` instructions

## Read Art Pipeline Instructions

Read `./.styles/.pipelines/proof-to-model/PIPELINE.md` instructions
Read `./.styles/.pipelines/cloud/PIPELINE.md` instructions
Read `./.styles/.pipelines/local/PIPELINE.md` instructions
Read `./.styles/.pipelines/code/PIPELINE.md` instructions
Read `./.styles/.pipelines/blender/PIPELINE.md` instructions

Add repository-specific art style instructions below these read directives.
