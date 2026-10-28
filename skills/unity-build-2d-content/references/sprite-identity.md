# Sprite imports and identity

Read this before scripted slicing or editing an existing sprite sheet. Match the installed `com.unity.2d.sprite` API and importer type; the Sprite Editor Data Provider API is an Editor concern, not a player assembly dependency.

## Retained content

Capture the texture's `.meta` GUID and each consumed sprite's GUID/local file identifier through `AssetDatabase.TryGetGUIDAndLocalFileIdentifier`. Also record name, `SpriteRect.spriteID`, rectangle, pivot and border. A texture GUID alone does not establish that animation clips or prefab subasset references survive a reslice.

Use `SpriteDataProviderFactories` to obtain and initialize the importer's `ISpriteEditorDataProvider`. Read the current rectangles before editing. Reuse existing `spriteID` values for retained logical sprites, including deliberate renames. A coincidental rectangle index is not a durable identity. Resolve ambiguous matching before writing rather than replacing all IDs.

On versions providing `ISpriteNameFileIdDataProvider`, keep its name/GUID pairs consistent with the retained and newly created rectangles. Preserve unrelated entries; remove pairs only for explicit removals. Call the provider's `Apply` and reimport the actual target importer. Avoid an unbounded postprocessor reimport loop. Apply other supported secondary textures, outline, bone and mesh providers only when those changes are in scope.

For destructive sheet reorganizations, create a mapping and update every consumer in the same reviewed change. Do not delete and recreate the texture or invent serialized YAML to hide missing subassets. Native import and consumer reload are required to verify the result.

## Import decisions and evidence

Set source alpha, sRGB versus data usage, pixels per unit, mesh type, extrusion, borders, read/write access and platform compression from actual use. Read/write adds retained CPU memory; enable it only for a recorded consumer. Check thin transparent edges after platform compression and atlas packing. Nine-slice borders and pivot changes require representative UI/animation checks even when identity is preserved.

Keep a before/after identity table and a native reload result. A useful fixture modifies a pivot or rectangle while retaining two named sprites, reimports, and asserts that both consumed GUID/local-ID pairs and provider IDs remain unchanged. Add a new sprite and prove it receives a distinct ID. Source text matching cannot supply that evidence.

## Versioned API sources

- [Sprite Editor Data Provider API, 2D Sprite 1.0](https://docs.unity3d.com/Packages/com.unity.2d.sprite@1.0/manual/DataProvider.html).
- [ISpriteNameFileIdDataProvider](https://docs.unity3d.com/Packages/com.unity.2d.sprite@1.0/api/UnityEditor.U2D.Sprites.ISpriteNameFileIdDataProvider.html).
- [AssetDatabase identity lookup](https://docs.unity3d.com/6000.0/Documentation/ScriptReference/AssetDatabase.TryGetGUIDAndLocalFileIdentifier.html).

These links identify API families; use the documentation matching the installed package and Editor rather than treating the linked versions as an upgrade request.
