# Native UI integration

Use this for UMG/Slate screens, HUD adapters, controller navigation or interface architecture. Discover the existing screen owner, local-player policy, widget classes and input stack before choosing implementation. CommonUI and Model View ViewModel are optional plugins with version-specific behavior, not prerequisites for every Unreal interface.

## Screens and local players

Create `UUserWidget` instances with the intended owning player. `AddToPlayerScreen` and `AddToViewport` serve different layering scopes; global viewport UI is not automatically player-specific. Keep the owner explicit through split-screen, possession and travel. A widget must not discover its controller through an unconditional player index zero.

Give one screen-stack owner responsibility for modal order, input mode, cursor, pause and restoration. `FInputModeGameOnly`, `FInputModeUIOnly` and `FInputModeGameAndUI` express routing choices, not a complete modal policy. Register which screen acquired each restriction and release only that restriction. Closing a settings modal must not unpause a still-active pause menu or return gameplay focus behind another modal.

Use user focus for the actual owning controller and distinguish it from global keyboard focus. Restore to a live, visible, enabled focusable target; if a remembered widget was rebuilt or removed, choose the screen's explicit fallback. Slate `FReply::Handled` consumes an input event; returning unhandled can trigger a second action in a lower layer. Test press/release/repeat semantics, escape/back and controller/pointer switching against the chosen routing policy.

## State and lifetime

Keep authoritative game state outside widgets. On activation, subscribe once and read an initial snapshot so an update before subscription does not leave a stale HUD. Rebind when possession, inventory source or local player changes. Treat pooled/hidden screens deliberately: `NativeConstruct`, activation, removal and `NativeDestruct` are distinct from a UObject's final destruction. Retain/remove delegate handles and unbind obsolete sources.

If CommonUI is selected, fit the established activatable-widget stack and action routing rather than building a second competing stack. If MVVM is selected, verify FieldNotify/view-model setup, binding ownership and source replacement. Neither plugin automatically solves server authority, screen lifecycle or controller focus. Avoid per-frame getter bindings for values whose source already has bounded change events.

## Layout, accessibility and cost

Test anchors and containers with the project's DPI curve, safe zones, split-screen rectangles, aspect ratios, long localized strings and text scaling. World-space WidgetComponents need a separate size/distance/occlusion assessment. Define binding-aware action labels instead of hardcoded button names.

Set supported widget accessibility properties and text alternatives, but record native assistive-technology checks separately. Keyboard/gamepad traversal needs actual focus events and submit/back behavior; screenshots and browser tools cannot prove it. Slate invalidation and Retainer Panel caching are selected performance techniques; measure their refresh/input behavior and avoid blindly caching animated or frequently changing content.

## Acceptance

Exercise nested modal close order, held submit during replacement, disabled/deleted focus targets, controller reconnect, HUD source destruction, respawn and travel. Assert subscription counts and state synchronization where automation can observe them. Capture native navigation and accessibility review on the real target. Record layout/prepass/tick costs under representative HUD activity; empty headless tests do not establish native usability.

Official references, with version matching:

- [UMG and Slate optimization](https://dev.epicgames.com/documentation/en-us/unreal-engine/optimization-guidelines-for-umg-in-unreal-engine)
- [CommonUI](https://dev.epicgames.com/documentation/en-us/unreal-engine/common-ui-plugin-for-advanced-user-interfaces-in-unreal-engine)
- [UMG Viewmodel](https://dev.epicgames.com/documentation/en-us/unreal-engine/umg-viewmodel-for-unreal-engine)
