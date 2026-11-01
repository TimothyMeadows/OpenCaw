# Unity content/rendering native fixture family

`HephaeraUnityContentCases` contains real Unity Editor API probes driven by the feature runner's `IEnumerator` lifecycle. All case methods take `HephaeraUnityFeatureContext`; failed assertions fail the case and missing explicit prerequisites block it. No matching Unity Editor has been executed while authoring these sources. Compilation, native API behavior and player acceptance remain unverified until an actual configured run.

The runner owns its copied project, generated Assets directory and report output. Fixtures create PNG/import data, temporary GameObjects, local physics scenes and NavMesh data only within that scope. They do not install packages, change a host project's layer/physics/render settings, enable services or fabricate binary asset files. Native-authored prerequisite assets must already be in the fixture project. Settings below are exact context setting keys, not shell commands.

| Method | Explicit prerequisites | Actual probe and limits |
|---|---|---|
| `SpriteIdentity` | `HEPHAERA_UNITY_SPRITE`; compatible `com.unity.2d.sprite` data-provider APIs; Unity 2021.2+ name/GUID mapping | Generate/import a two-sprite PNG, apply a pivot change, reimport and compare real GUID/local-file-ID pairs and SpriteRect IDs. Does not certify every prefab/animation consumer. |
| `RuleTileTopology` | `HEPHAERA_UNITY_TILEMAP`; compatible `com.unity.2d.tilemap` and `com.unity.2d.tilemap.extras`; three assets below | Paint actual isolated/east-neighbor cells, assert declared sprite outputs, remove neighbor and assert restoration. It checks the supplied two-case grammar, not inferred artistic topology. |
| `AtlasLifecycle` | Graphics; real same-target sprite/atlas AssetBundles built separately; five settings below | Start both sprite loads, observe actual atlas requests, keep each callback/operation, register two tag-correct atlases and clean up owned listeners/bundles. Timeout is failure; no requests cannot be a pass. |
| `Physics3D` | Built-in 3D physics module, native scene support | Isolated 3D simulation, falling/contact, bounded floor raycast and nonzero-force wake/movement. No global timestep/layer changes. |
| `Physics2D` | Built-in classic 2D physics module, native scene support | Isolated classic 2D simulation/contact, bounded unsaturated query and impulse motion. This is not Physics Core acceptance. |
| `NavigationCancellation` | Built-in AI module and at least one agent build setting | Bake owned bounded NavMesh data; complete/unavailable destinations, actual agent path assignment/reset and disable. Editor inability to bind the agent blocks. Player-delayed requests remain separate. |
| `ShaderCompilation` | Graphics; `ContentShader` | Force-import a native shader and compile every pass for one current material keyword set; reject errors/uncompiled passes. Does not prove stripping, player support or visuals. |
| `RenderingConfiguration` | Graphics; `ContentExpectedPipeline`; supported render requests for selected SRP | Assert effective quality/default pipeline; render/read back different camera clear colors, release/recreate target and verify resized output. Custom Render Graph passes and migration parity are not certified. |

## Native content configuration

All asset paths below must be existing `Assets/...` files in the isolated source project; the runner additionally verifies project-local paths and rejects escaping links. Imported resources are read-only. Use Unity's actual asset authoring/build tools and preserve original `.meta` identities.

- `ContentRuleTile`: authored RuleTile with a deterministic isolated output and a distinct output when the same RuleTile is immediately east. Do not use randomized/animated output in this bounded case.
- `ContentRuleIsolatedSprite`, `ContentRuleNeighborSprite`: native Sprite assets matching those outcomes. For sliced subassets use separate fixture textures, or extend the fixture through a reviewed explicit subasset identity contract rather than ambiguous first-sprite selection.
- `ContentSpriteBundle`, `ContentAtlasBundle`: existing native-built AssetBundle files under `Assets/`, for the Editor's current platform. Each bundle is separate; sprites are bound to their atlases while those atlases are deliberately excluded from automatic/built-in delivery. Bundle duplication or direct atlas references invalidate the intended late-binding setup.
- `ContentSpriteNames`: two distinct comma-separated sprite asset names from the sprite bundle, each mapped to a different deferred atlas tag.
- `ContentAtlasTags`: two distinct comma-separated tags. Each atlas bundle asset name must equal its tag. The fixture requires actual engine events for both tags; it does not synthesize or directly invoke `atlasRequested`.
- `ContentShader`: native `.shader` or supported native shader asset that resolves as `Shader` and has a supported pass on this graphics API. A Shader Graph's importing/variant coverage needs version-qualified project fixtures as well.
- `ContentExpectedPipeline`: `builtin`, or the exact full CLR type name of the effective render-pipeline asset (Quality override before Graphics default). Do not choose a pipeline from a skill name or change settings to make this assertion pass.

The Sprite data-provider reference family is documented in `com.unity.2d.sprite` 1.0; RuleTile's relevant API family is present in Extras 3.x. These are API references, not universal compatible install pins. Resolve actual versions from `ProjectVersion.txt`, manifest and lock before selecting symbols. Render requests use the documented Unity 2022.2+ `RenderPipeline.StandardRequest` family where the selected pipeline declares support; unsupported versions block rather than switching pipelines.

## Additional production acceptance

The eight native smoke cases are bounded prerequisites. They do not replace these feature-specific checks:

- **Sprite/content:** preserved prefab/animation/UI consumers; target compression and pixel scrolling; same-tag concurrent requests, reverse-order distinct loads, wrong tag/missing content and teardown during loading; check callback and retained-handle counts in the actual selected Addressables/bundle player. Addressables content must be successfully built for the dependent player's target, and remote delivery requires its explicitly authorized development endpoint.
- **RuleTiles:** edge/corner/hole/narrow-path neighborhoods, transform priority, family equivalence and gameplay/collider outputs against a reviewed topology table. Never invent adjacency from names or a sprite-sheet heuristic.
- **Physics:** collision/trigger/query matrices, CCD, slopes/moving platforms and fixed-step pressure in real target players. For explicitly selected Physics Core, create a separate version-qualified native world/body/query fixture and record it separately; classic Rigidbody2D success cannot stand in for it.
- **Navigation:** Play Mode/player path pending/cancellation, owner disable during delayed completion, obstacle carving, link traversal interruption and additive-scene unload/reload. The synchronous Editor case cannot certify those async behaviors.
- **Rendering/materials:** native shader/player builds for required variants/graphics APIs; Render Graph pass dependency/resource diagnostics, resize/disposal and representative views. For Built-in-to-URP migrations, record recoverable originals and matched before/after scene captures. Review camera stacks, Volumes, transparency, lighting and target GPU/memory budgets with actual graphics. Offscreen clear-color changes do not establish migration equivalence or artistic approval.

Report each supplemental case's environment, scope, expected/observed outcome and artifact. Missing packages, assets, graphics hardware, player platform or device are explicit blocked/not-run results. Source checks and simulated process/report tests must remain labeled separately from these native cases.
