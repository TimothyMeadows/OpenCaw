# CLOUD_SESSION.md

## Intent

Use image or audio generation already exposed by the active assistant or IDE session without assuming a named provider.

## Capability Discovery

- Check image, music, sound-effect, and voice support separately before planning a run.
- Treat this backend as the default for each supported modality.
- Record unavailable model, workflow, parameter, or seed data explicitly; do not invent reproducibility metadata.

## Production Rules

- Stage every result outside runtime asset directories until human review is complete.
- Record the session capability, disclosed model or tool version, prompt parameters, input provenance, rights, consent, cost budget, and staged output hash.
- Keep credentials in the session or environment. Never copy API keys, access tokens, or credential-bearing URLs into project files.
- If a compatible local backend is also viable, ask the user to choose cloud/session or local before generating.
- If the selected backend fails, report the failure and preserve staged evidence; never cross the cloud/local boundary silently.

## Promotion Gate

- Review contact sheets for images and listen-through sheets for audio.
- Check exact coverage, geometry, duration, loudness, file format, runtime budget, and accessibility requirements.
- Promote only explicitly accepted outputs through a separate human-reviewed action.
- Reject malformed candidates instead of destructively repairing them without approval.
