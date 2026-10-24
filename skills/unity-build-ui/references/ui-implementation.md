# Stack, font and rebuild decisions

## uGUI and UI Toolkit

Keep the existing runtime stack unless the task explicitly includes migration. uGUI uses Canvas/RectTransform, GraphicRaycaster, selectable navigation and EventSystem; the chosen input module must support paired players and devices. UI Toolkit uses UIDocument, VisualElement trees, panel event handling and its version-specific focus/navigation APIs. Confirm runtime support for the actual controls and rendering mode; an Editor inspector control is not automatically available to players.

If both stacks are required, specify pointer/input routing, focus transfer and sorting/hit-test boundaries. A modal must retain one input owner, prevent gameplay actions leaking underneath and restore a still-valid element after close. Disabled, removed or virtualized elements cannot remain restoration targets. Define fallback focus and test split-screen ownership with actual input devices.

For uGUI, separate Canvas regions when measured rebuild/batching costs justify it. Avoid forcing layout every frame or nesting layout drivers that repeatedly invalidate one another. For UI Toolkit, update existing elements/bound properties instead of repeatedly replacing the tree. Pool list rows with complete callback unbinding/rebinding, retaining item identities as rows recycle. Record allocations and panel/layout costs under representative updates.

## Fonts, TMP and TextCore

uGUI commonly uses `TextMeshProUGUI`; UI Toolkit text uses the release's TextCore/Panel Text Settings surfaces. Select assets/settings for the active stack rather than assigning TMP assets to unsupported UI Toolkit properties. Inspect the installed Editor/package documentation for supported font asset conversion, fallback and dynamic population behavior.

Track font source rights, locale glyph sets, fallback order, atlas size/growth and material variants. Check composed characters, combining marks, bidirectional text, numerals and inline markup. A character-coverage API cannot establish shaping or reading order. Compare real player renders at small/large sizes, target DPI and localizable line wrapping; supply readable fallback and missing-glyph diagnostics.

HUD adapters initialize from a coherent state snapshot and then apply owned changes. Keep domain state separate from presentation strings and transient effects. Cache formatting when inputs are unchanged, update only changed values and avoid allocating every frame for static labels. Unsubscribe only owned delegates; shared UnityEvents and localization components may already have consumers.

## Evidence boundaries

Use native/player interaction tests for focus, input and accessible behavior. An Editor window test can exercise UI Toolkit focus ownership and teardown but does not certify runtime UIDocument dispatch. Include a real player scene for uGUI EventSystem ownership, HUD respawn and layout variations. Browser tests apply to the web player; they cannot certify a native accessibility API. Profiling and visual checks report environment, workload and budgets separately.

Official references, select the installed version:

- [UI system comparison](https://docs.unity3d.com/6000.0/Documentation/Manual/UI-system-compare.html).
- [UI Toolkit focus](https://docs.unity3d.com/6000.0/Documentation/Manual/UIE-focus-order.html).
- [TextMesh Pro font assets](https://docs.unity3d.com/Packages/com.unity.textmeshpro@3.0/manual/FontAssets.html).
- [UI Toolkit font assets](https://docs.unity3d.com/6000.0/Documentation/Manual/UIE-font-asset.html).
