---
name: source-licensed-visual-assets
description: Select visual assets with documented source, license, intended use, crop, ratio, and accessibility requirements. Use when a design needs stock imagery, icons, textures, audio, video, fonts, or other third-party media that must be safe to hand off and redistribute.
---

# Source Licensed Visual Assets

## When to use

- Choosing third-party media for product or marketing surfaces.
- Replacing placeholder assets with traceable production candidates.
- Auditing whether an asset handoff includes sufficient rights and metadata.

## Workflow

1. Define the subject, emotional role, medium, dimensions, crop, color treatment, resolution, and performance budget.
2. For 3D assets, check optional external libraries in `STYLE.md` with `use-external-asset-library` before searching for or downloading another asset.
3. Use only repository-approved sources and verify the license at the asset level.
4. Record the canonical source, creator, license or terms, retrieval date, and modification limits.
5. Evaluate composition, readability, responsive crops, alt text, and fallback behavior.
6. Prepare optimized derivatives only when the license and task authority permit it.
7. Add provenance and usage notes to the host project handoff.

## Output

- A short candidate list with preview, intended use, ratio, and tradeoffs.
- A complete provenance record for the selected asset.
- Delivery paths, optimization notes, alt text, and license constraints.

## Guardrails

- Do not assume a repository-level license covers third-party media.
- Do not hotlink assets unless the provider and host policy permit it.
- Do not include assets with unclear ownership, model releases, or redistribution rights.
- Never load or modify a configured external-library asset directly; copy it into `assets/models/` first.
