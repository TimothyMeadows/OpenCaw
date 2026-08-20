# Browser evidence adapter

Use a task-local, self-contained JavaScript ESM adapter to connect host-native character code to the deterministic evidence harness. The adapter exports:

```js
export async function createCodeCharacterEvidenceAdapter({ THREE, stage, profile, seed })
```

The returned object implements these methods:

- `capture({ view, pixelHeight, kind, partId? })`: render one deterministic canvas below `stage`; `kind` is `whole`, `semantic-mask`, or `isolated`.
- `sampleStructure(config)`: return semantic parts and parents, joints, sockets, colliders, normalized ground measurements, declared attachment gaps, and declared symmetry deviations.
- `sampleMotion(config)`: return the actual motion mode, skeleton identity, maximum influences, roles, contacts and normalized errors, and moving-part count.
- `sampleRuntime(config)`: measure the exact representative actor count and contextual draw, geometry, material, texture, rig, clip, shader, memory, CPU, and GPU facts.
- `constructionHash({ run, ...config })`: independently construct the actor and return a stable semantic hash without object identities or timestamps.
- `lifecycleCycle({ cycle, ...config })`: perform create, update, animation, attachment, and dispose work and return `{ cycle, resourceDelta, staleCallbacks }`.
- `dispose()`: release the live capture subject, renderer, listeners, callbacks, materials, geometries, and owned textures.

The harness serves only repository-contained JavaScript and the host-installed Three.js browser build on `127.0.0.1` using an OS-assigned port. It blocks service workers and external requests, launches Chromium with its sandbox enabled, confines outputs to a new repository directory, and locks that directory against concurrent capture. Do not import remote modules, fetch assets, install packages, disable the sandbox, reuse a production server, or write outside the requested output.

Fixture analysis calibrates the measurement semantics but is marked untrusted. Only a successful browser capture is trusted machine evidence, and even trusted evidence cannot decide identity, silhouette readability, form readability, materials, style, appeal, or other aesthetic questions.

Treat `not-applicable` as a reasoned outcome, not an omission. Static actors have no animation-role/contact checks; articulated actors prove declared moving parts and roles; skinned actors also prove skeleton identity and influence limits. The observed mode must match the frozen profile, so declaring a simpler mode cannot bypass required behavior.
