# CLOUD Art Pipeline

## Intent

Use image or audio generation exposed by the active assistant or IDE session without coupling the repository contract to a named provider.

## Inputs

- A visual or audio brief with exact coverage, dimensions or duration, runtime destination, and budget.
- Authorized source material with recorded rights and applicable identity or voice consent.
- The active `STYLE.md` for image work and `MEDIA.md` for generated image or audio runs.

## Production Rules

- Discover image, music, sound-effect, and voice capability separately.
- Record the session capability, disclosed model or tool version, parameters, seed, input provenance, and cost or token budget. Mark undisclosed values unavailable instead of inventing them.
- Stage results outside runtime asset directories until human review is complete.
- Keep credentials in the session or environment.
- Stop when the capability is unavailable or fails. Never fall back to another art pipeline silently.

## Output Contract

- Generated candidates remain staged with hashes and a generation manifest.
- Every candidate records acceptance or rejection and its intended runtime target.
- Promotion is a separate, explicitly reviewed action.

## Acceptance Checks

- Verify coverage, geometry or duration, format, file size, runtime cost, accessibility, rights, consent, and provenance.
- Review images through contact sheets and audio through listen-through evidence.

## Role Fit

Use with `generative-art-designer`, `generative-media-pipeline-engineer`, `art-director`, and audio-production roles.
