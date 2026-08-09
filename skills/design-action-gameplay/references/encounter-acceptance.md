# Encounter Acceptance

## Encounter contract

- State the encounter's player knowledge, available verbs, spatial objective, failure condition, recovery opportunity, and intended emotional arc.
- Compose enemies by readable role: pressure, denial, pursuit, support, disruption, protection, or objective control. Give every role a distinct tell and counterplay.
- Define spawn, activation, reinforcement, retreat, surrender, victory, reset, and cleanup transitions as inspectable state.
- Budget simultaneous threats, incoming damage opportunities, crowd control, navigation contention, effects, audio voices, and camera demands.

## Fair state transitions

- Do not activate a threat until the player can perceive its tell through at least one supported feedback channel.
- Preserve minimum reaction time between actionable anticipation and consequence, adjusted deliberately for difficulty.
- Cancel or transform attacks consistently when actors die, stagger, lose valid targets, leave bounds, or encounter blocked paths.
- Define recovery windows after pressure peaks. Escalation should change decisions, not only multiply health or damage.
- Keep reinforcements and hidden actors from causing unavoidable damage during introduction.

## Space and pacing

- Validate navigation routes, retreat space, sight lines, cover, hazards, objective access, and camera readability at representative actor sizes.
- Prevent one role from accidentally blocking the counterplay required for another unless the combination is the explicit challenge.
- Separate authored pacing beats from frame timing and animation completion callbacks.
- Define upper bounds for encounter duration and stalled states, with an observable recovery or failure path.

## Tuning record

- Store tuning values in bounded data with units and semantic names.
- Record the hypothesis behind each change and compare evidence from a stable scenario rather than relying on aggregate feel alone.
- Segment observations by player capability, input mode, difficulty, camera, and performance constraints when those variables affect outcomes.
- Treat repeated player confusion, unreadable hits, or unavoidable damage as contract failures rather than preferences.

## Deterministic fixtures

- Fix scenario seed, geometry, spawn order, player loadout, AI rules, and timing source.
- Assert legal transition order, threat caps, reaction windows, target validity, victory/reset cleanup, and absence of post-completion damage.
- Test enemy removal, path failure, target loss, simultaneous phase completion, pause/resume, save/load where supported, and scene teardown.
- Pair deterministic checks with representative playtests and captures; automation proves rules, while human review proves readability and counterplay.
