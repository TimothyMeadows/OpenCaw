# PAPER_DIORAMA.md

## Intent

Compose scenes as shallow shadow boxes with separated paper planes, clear apertures, and controlled depth.

## Production Rules

- Plan a backboard, distant layer, midground, focal layer, and foreground aperture; add planes only when they improve depth or readability.
- Keep critical subjects, controls, and text outside foreground occlusion and aspect-ratio crop zones.
- Use coherent plane spacing, cast-shadow direction, cut-edge treatment, scale, and atmospheric falloff.
- Export layers independently with overlap, masks, registration points, and enough bleed for restrained parallax.
- Limit parallax to depth communication; define equivalent static composition for reduced-motion contexts.
- Check wide, square, tall, and target runtime crops before approving the master composition.

## Acceptance Checks

- No seams, transparent fringes, holes, duplicated edges, or accidental occlusion appear during camera motion.
- Foreground framing supports the focal subject instead of trapping navigation or hiding state changes.
- Layer geometry, export coverage, registration, safe zones, and target dimensions are exact.
- The static and reduced-motion presentation preserves hierarchy and meaning.

## Role Fit

Use with `papercraft-art-director`, `parallax-background-artist`, `generative-art-designer`, and runtime roles implementing layered scenes.
