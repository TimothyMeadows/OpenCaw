# Renderer extension and resource ownership

Discover the effective renderer and installed package before selecting APIs. URP compatibility-mode passes, URP Render Graph, HDRP custom passes and Built-in command buffers have different contracts. A newer documentation example is not evidence that an older project supports it. Do not toggle compatibility mode as an undocumented workaround for an unfinished port.

## Render Graph

For URP 17/Core RP 17, use graph resource types consistently. `TextureHandle.GetDescriptor(renderGraph)` yields a `TextureDesc`; it is not a `RenderTextureDescriptor`. Some pipeline utilities explicitly convert a `RenderTextureDescriptor` into graph resources. Choose the API matching the value actually held, rather than casting unrelated descriptor types or copying an outdated namespace.

Read the frame's camera/resource data, confirm the required source is available and create the destination for that frame. Declare every sampled input and attachment write through the applicable graph builder. Avoid reading from and writing to the same texture unless the supported pass type and backend explicitly permit that operation. Declare depth, MSAA, dynamic scaling, format and clear behavior from the intended effect, not arbitrary copied defaults.

Transient graph textures are graph-owned. A handle must not become a persistent cross-frame cache. Imported resources retain external ownership: release their RTHandles, materials, compute resources and event registrations through the renderer feature's actual disposal path. Handle resize and device/resource recreation without keeping stale native objects. Only use unsafe passes or graph-culling overrides when a concrete side effect requires them and its dependencies are documented.

An offscreen camera target can exercise allocation and resize, but it does not verify a custom graph pass ran. Capture graph/pass diagnostics and observable output for the selected renderer. Compare enabled, disabled, multiple-camera and teardown cases. Build for the actual graphics API, including platforms where backbuffer access, depth sampling or compute is restricted.

## Other rendering paths

In a compatibility-mode URP pass, own temporary RTHandles and matching cleanup, use supported blit utilities and respect camera stacking/XR targets. In Built-in, pair command-buffer attachment/removal with the owning camera and lifetime. For HDRP, follow its custom-pass injection/resource rules. Do not mix their APIs because class names appear similar.

## Sources

- [Core RP 17 TextureHandle](https://docs.unity3d.com/Packages/com.unity.render-pipelines.core@17.0/api/UnityEngine.Rendering.RenderGraphModule.TextureHandle.html).
- [URP 17 Render Graph](https://docs.unity3d.com/Packages/com.unity.render-pipelines.universal@17.0/manual/render-graph.html).
- [URP custom renderer features](https://docs.unity3d.com/6000.0/Documentation/Manual/urp/renderer-features/intro-to-scriptable-render-passes.html).

Use the installed package's source/API documentation to resolve signatures and supported pass types.
