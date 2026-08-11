# CSS3 Art Pipeline

## Intent

Create web-native visual assets with CSS, mathematical layout, and inline SVG/vector geometry. This is OpenCaw's default art pipeline for new style contracts.

## Inputs

- The active `STYLE.md`, semantic purpose, target surfaces, responsive sizes, and accessibility requirements.
- A defined token system for color, stroke, spacing, radius, depth, and motion.

## Production Rules

- Use semantic HTML, CSS custom properties, gradients, transforms, masks, clip paths, pseudo-elements, and inline SVG paths or shapes.
- Keep geometry resolution-independent and derive repeated measurements from shared tokens or formulas.
- Preserve meaningful DOM order, keyboard behavior, reduced-motion alternatives, and non-color state indicators.
- Do not use raster images, canvas, WebGL, generated-image dependencies, or downloaded visual libraries as final art.
- Stop when the requirement needs continuous 3D depth, generated raster media, or local model inference. Never switch pipelines silently.

## Output Contract

- Deliver maintainable CSS and semantic HTML/SVG components that remain editable as source.
- Document token names, supported sizes, view boxes, responsive behavior, and accessibility fallbacks.

## Acceptance Checks

- Verify sharp rendering across density and zoom levels, responsive layout, contrast, focus, reduced motion, and absence of raster/canvas/WebGL dependencies.
- Validate SVG structure when SVG is used.

## Role Fit

Use with `css-vector-artist`, `frontend-developer`, `web-experience-designer`, and `qa-engineer`.
