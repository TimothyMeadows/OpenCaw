# Rigged Actor Manifest

Author the manifest as strict JSON and validate it with:

```bash
./commands/validate-rigged-actor-manifest.sh path/to/actor.json [--root path/to/repository] [--require-verified]
```

## Contract

Use exactly these top-level fields:

- `schemaVersion`: `opencaw-rigged-actor/v1`.
- `actor`: stable `id`, human-readable `displayName`, `kind` (`character` or `monster`), and `deliveryStage` (`source`, `integration`, or `shipped`).
- `files`: hashed `source` and `runtime` records. Paths use forward-slash repository-relative notation. GLB, GLTF, and FBX are accepted.
- `coordinateSystem`: positive `unitsPerMeter`, distinct signed `upAxis` and `forwardAxis`, `handedness`, `pivot`, and `grounding`.
- `skeleton`: stable `id`, declared `rootBone`, named `bindPose`, complete unique `bones`, and positive `maxInfluencesPerVertex`.
- `sockets`: unique IDs, declared parent bones, and purposes.
- `clips`: unique IDs, semantic roles, matching `skeletonId`, loop and root-motion policy, and unique timed events.
- `equipment`: required only for characters. Each item resolves a socket and carries a hashed asset path.
- `detachableParts`: required only for monsters. Each part resolves a socket and carries a hashed asset path.
- `colliders`: unique navigation, hurt, attack, and targeting records with a `bone:<id>` or `socket:<id>` parent reference and a named shape.
- `budgets`: positive limits for triangles, bones, materials, texture bytes, and runtime bytes.
- `provenance`: source URI, author, license, rights basis (`owned`, `licensed`, or `cleared`), and ISO date-time capture.
- `verification`: `pending`, `verified`, or `rejected`, with verifier, date, and hashed evidence records.

Every actor requires the clip roles `idle`, `locomotion`, `attack`, `hit-react`, and `death`. Every actor also requires collider roles `navigation`, `hurt`, `attack`, and `targeting`.

## File verification

All declared paths must be normalized relative paths. Absolute paths, drive-qualified paths, backslashes, dot segments, and repository escapes are invalid.

When `--root` is present, every declared asset and evidence file must:

- resolve inside the real repository root;
- exist as a regular non-symbolic-link file;
- match its declared lowercase SHA-256.

A `shipped` manifest requires `--root` so shipment cannot be validated without inspecting its files.

## Verified evidence

A manifest with `verification.status` set to `verified` requires an identified verifier, an ISO verification date, and at least one valid evidence record. `--require-verified` additionally requires all four evidence types:

- `automated-test`
- `runtime-capture`
- `gameplay-review`
- `performance-profile`

Evidence paths and hashes bind the claim to durable artifacts. Notes must state what was observed rather than only asserting that a check passed.
