# Locale and resource ownership

Use this reference when binding localized content or importing tables. API availability belongs to the installed package version, not a universal Editor version.

## Startup and stable identity

Await `LocalizationSettings.InitializationOperation` and inspect success before reading `SelectedLocale`. Keep locale startup policy separate from the locale the user subsequently selects. A missing locale does not authorize switching the project's fallback policy.

Table collections have shared identity; entries have stable keys/IDs. Import into a reviewed collection instead of recreating it, preserving GUID references and serialized entry IDs. Detect duplicate keys, renamed placeholders and removed IDs before writing. Round-trip a representative collection and inspect consumers after reload.

For Smart Strings, record the arguments' names, types, escaping and plural/select behavior. Do not concatenate translated fragments or let translator text choose gameplay identifiers. Cover zero, one, other applicable plural categories, large numbers, locale-dependent formatting and rich-text sanitization.

## Async bindings and subscriptions

`LocalizedString.StringChanged` supports refreshed values after locale changes. Subscribe once per live binding and remove that exact handler on teardown. For `LocalizeStringEvent` or other UnityEvents, preserve existing persistent and runtime listeners; do not call broad listener removal to install an owned adapter.

Treat request identity as `(owner, generation, locale, table, entry)`. Capture it before requesting. Before applying a completion, check that the owner remains live and all identities still match. Invalidating a request prevents application; it does not prove the underlying load was physically cancelled. Ignore obsolete completions and complete their resource cleanup.

String-database operations and a localized reference's cached operations have package-defined ownership. Do not release borrowed handles blindly. If retaining an operation beyond its documented lifetime, acquire a reference through the supported Addressables API and release that reference exactly once. For `LocalizedAsset`/`LoadAssetAsync`, use the matching owned release path, retain the old visible asset until a valid replacement is ready, and prevent a stale load from releasing the replacement's handle. Record who owns table preload, asset and instance lifetimes separately.

Keep failure, empty translation and a legitimate empty string distinct. An explicit fallback receipt identifies requested/resolved locales and missing content; no success marker may conceal missing required translations.

## Fonts and UI

TMP font assets and UI Toolkit TextCore settings have different binding surfaces. Check the actual runtime stack and package versions before assigning fonts. Verify licensed font sources, fallback order, required glyph coverage, dynamic atlas growth and memory. A glyph-exists API check does not prove correct shaping, line breaking or bidirectional ordering. Review representative player renders with text scale, narrow layouts, controller focus and accessible alternatives.

## Evidence

Use distinct known translations for two configured locales and a real table. Request A, switch to B while work is outstanding, close/reopen the screen and verify only current results appear. Preserve an independent listener, remove the owned one, then change locale and prove the independent binding still receives updates. Measure cold and warm loads separately. Missing assets/packages remain blocked; simulated delayed callbacks prove adapter ordering only.

Official starting points, qualified to the installed version:

- [Localization 1.5 API](https://docs.unity3d.com/Packages/com.unity.localization@1.5/api/UnityEngine.Localization.LocalizedString.html).
- [Localization asynchronous operations](https://docs.unity3d.com/Packages/com.unity.localization@1.5/manual/Scripting.html).
- [Addressables operation handles](https://docs.unity3d.com/Packages/com.unity.addressables@2.2/manual/AddressableAssetsAsyncOperationHandle.html).
