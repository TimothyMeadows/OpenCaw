# LAYERED_PAPERCRAFT.md

## Intent

Create tactile cut-paper visuals from discrete, readable planes with convincing stock, edges, and restrained physical depth.

## Production Rules

- Use matte paper stock, subtle fibers, visible cut cores, and small thickness changes; reserve gloss for an explicitly different material.
- Build forms from a limited stack of deliberate planes instead of simulated continuous sculpting.
- Keep one coherent light direction and shadow softness across assets, UI, states, and composites.
- Preserve silhouette, value grouping, and focal hierarchy at thumbnail and runtime scale.
- Express interactive states through shape, position, iconography, and value as well as color; keep runtime text separate from generated imagery.
- Export clean masks, transparent edges, bleed allowances, and layer names when assets will be animated or recomposed.

## Acceptance Checks

- Paper fibers, cut cores, thickness, and shadows remain legible without becoming noisy.
- No unintended glossy plastic, polished metal, glass, airbrushed volume, or falsely photographic material treatment appears.
- Layer order, edge halos, state coverage, dimensions, pivots, and runtime budgets match the asset plan.
- The composition remains readable in grayscale, at target size, and against representative backgrounds.

## Role Fit

Use with `papercraft-art-director`, `art-director`, `generative-art-designer`, and implementation roles responsible for layered runtime assets.
