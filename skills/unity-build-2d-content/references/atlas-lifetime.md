# Atlas builds and deferred loading

## Build ownership

Inspect Sprite Atlas V1/V2 mode and platform settings before editing. Configure packables, padding, rotation, tight packing, mip/filter behavior, format overrides and variant scale against actual sprites. UI borders, tiled sprites and pixel art can impose different packing constraints. Compare the packed result and player memory; a packed preview alone proves neither delivery nor absence of duplicated textures.

Select built-in inclusion, AssetBundles or the project's explicitly selected Addressables workflow. For deferred binding, exclude direct inclusion intentionally and establish how sprites and their matching atlas are delivered. When Addressables is selected, inspect the package's content-build policy: some configurations build on player build; others require a separate content build. Verify successful target-specific content output and catalog identity before accepting the player build. Do not assume a previous platform's content is usable.

## Deferred request lifetime

`SpriteAtlasManager.atlasRequested` provides a tag and a registration callback. Loading an atlas into a variable does not register it for the requesting sprite; deliver the successfully loaded atlas through each live callback. `atlasRegistered` is an observation of registration, not permission to release content that sprites still consume.

Maintain one owned record per loading identity: tag/address, operation handle, pending callbacks, completion/failure, generation and consumer references. Coalesce requests only when they identify the same atlas and delivery version. Preserve every callback when several requests arrive before completion; never overwrite a single global operation handle with the next request. Distinct atlases may finish out of order.

Treat release of a handle as releasing a reference, not proof that underlying I/O was canceled. On disable/unload, detach owned event handlers, invalidate the owner's generation and prevent late completion from registering into dead consumers. Completion still owns disposal of operations already started. Keep the atlas/bundle or Addressables handle alive for its actual sprite users; avoid invalidating shared consumers by unloading the bundle with asset destruction.

For failure, record the tag, delivery identity and provider error. Do not invoke the callback with unrelated atlas content or silently switch to an arbitrary Resources path. Define project-specific retry and user-visible behavior. A retry must not leak the failed handle or duplicate existing callbacks.

## Required tests

Run two simultaneous requests for one atlas, two distinct atlas requests completing in reverse order, missing content, wrong-tag content and teardown before completion. Check callback counts, registration, visible sprites, handle/reference cleanup and subsequent scene reload. An Editor fixture that directly exercises a request dispatcher is a contract simulation; actual `atlasRequested` behavior must be observed from a correctly built late-bound player or equivalent native content fixture.

## Versioned API sources

- [SpriteAtlasManager](https://docs.unity3d.com/6000.0/Documentation/ScriptReference/U2D.SpriteAtlasManager.html).
- [Late binding](https://docs.unity3d.com/6000.0/Documentation/Manual/sprite/atlas/distribution/late-binding.html).
- [Addressables memory management, 1.21](https://docs.unity3d.com/Packages/com.unity.addressables@1.21/manual/MemoryManagement.html).
- [Addressables build content](https://docs.unity3d.com/Packages/com.unity.addressables@1.21/manual/BuildContent.html).

Confirm version-specific build and release semantics in the selected package.
