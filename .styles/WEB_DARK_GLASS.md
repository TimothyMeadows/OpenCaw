# WEB_DARK_GLASS.md

## Intent

Create a layered dark interface with translucent surfaces and controlled luminous accents while preserving legibility and focus.

## Production Rules

- Start with opaque semantic colors, then add transparency only where the background remains predictable.
- Use blur sparingly and provide an opaque fallback for reduced transparency, performance limits, or unsupported rendering.
- Separate layers through luminance, borders, and spacing rather than glow alone.
- Limit bright accents to focus, status, and primary actions; avoid uniformly luminous text.
- Keep animation slow enough to read and disable decorative drift under reduced motion.

## Acceptance Checks

- Text, controls, and focus indicators remain legible over every allowed background.
- The interface remains usable when blur, transparency, and animation are disabled.
- Layer stacking and hit targets are unambiguous at mobile and desktop widths.
- Effects stay within the host performance budget on the target device profile.

## Role Fit

Use with `web-experience-designer`, `frontend-developer`, `art-director`, and `qa-engineer`.
