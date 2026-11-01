# MAUI web-game host

This packaging profile hosts a completed static HTML/JavaScript/CSS build in .NET 10 MAUI `HybridWebView`. The game keeps its selected engine and its JavaScript implementation. This directory supplies a native application shell, not another engine, a Node server, or a browser compatibility emulator.

## Targets

| Hephaera target | MAUI framework | Build host | Release output |
| --- | --- | --- | --- |
| WINDOWS | `net10.0-windows10.0.19041.0` | Windows with MAUI Windows tools and Windows SDK | Published application folder, or explicitly configured signed MSIX |
| MACOS | `net10.0-maccatalyst` | Mac with compatible Xcode and Mac Catalyst tools | `.app`, or configured signed `.pkg` |
| ANDROID | `net10.0-android` | Windows or Mac with compatible Android SDK/JDK and MAUI tools | `.apk` for installation or signed `.aab` for store distribution |
| IOS | `net10.0-ios` | Mac with compatible Xcode and iOS tools | Correctly provisioned/signed device `.ipa` for `ios-arm64` |

There is no Linux, TV, Tizen or browser packaging target. Running a Windows build through Wine or Proton is a user-selected compatibility experiment; this profile does not certify those environments. Windows WebView2 and Windows App SDK dependencies may prevent it from working.

Minimum OS declarations in this initial host are Windows 10 version 1809, Android API 24, iOS 15 and Mac Catalyst 15. These are shell declarations, not proof that a game's renderer, input or audio supports every such device. Verify the game's actual web APIs and system WebView on each target. Windows/Android use Chromium-based system components; Apple uses WKWebView. WebGPU, cross-origin isolation, service workers, codecs and pointer/fullscreen behavior are not universally portable.

## Template contract

Copy `template/` into a new explicitly owned host folder. Its project is `GameHost.csproj` and its namespace is `Hephaera.GameHost`. Hephaera's packaging command generates `HephaeraGame.props` with:

- `ApplicationId`: application/package identifier chosen by the host project.
- `ApplicationTitle`: display title.
- `ApplicationDisplayVersion`: release version, such as `1.2.0`.
- `ApplicationVersion`: positive monotonically increasing build number.
- `HephaeraDefaultFile`: relative packaged HTML entry, normally `index.html`.

The native project pins `MauiVersion` to `10.0.20` independently of the installed SDK's default. Updating this initial version requires a reviewed project/template change and fresh native validation; do not inherit an ambient workload package version silently.

The complete compiled web output belongs in `Resources/Raw/wwwroot`. Relative asset URLs must resolve against the packaged origin. The game must not depend on a development server, unshipped npm packages, runtime filesystem paths, or a server-rendered entry. The host does not build npm projects or rewrite game scripts. Entry identity is emitted as assembly metadata rather than interpolated into C# source.

Framework lists are narrowed explicitly for the selected build. A Windows host's default framework is Windows; a Mac host's default is Mac Catalyst. Select `--target ANDROID` or `--target IOS` in the packaging command to choose the corresponding framework. The initial CLI accepts only the iOS device RID `ios-arm64`; iOS simulator development uses separately reviewed direct MAUI/Xcode tooling and is outside this CLI's build/package receipts. No target selection installs a workload. Keep the MAUI package, SDK/workload and Xcode/Android tool versions compatible and record their actual versions in release evidence.

`HephaeraSigningProps` may name a separately supplied private MSBuild property file. The project imports it after generated application metadata. Do not put credentials in the command line, a checked-in property file, release receipts or task logs. Signing overrides are trusted build inputs and need separate review; MSBuild property files can execute build logic. This mechanism does not grant signing or publication authorization.

## Native behavior

The native page fills the available content area with no navigation bar or authored outer padding. `new SafeAreaEdges(SafeAreaRegions.Container)` explicitly keeps game content clear of native cutouts and system bars; .NET 10's page default would otherwise be edge-to-edge. The game owns responsive canvas sizing, touch controls and any additional CSS safe-area layout. Test actual device insets rather than assuming desktop viewport dimensions. Placeholder gamepad icon/splash resources are supplied so scaffolds build; replace them with reviewed release branding before shipping.

Top-level navigation is restricted to the MAUI local origin by exact scheme, host, default-port and empty-userinfo checks. It is `https://0.0.0.1/` on Windows/Android and `app://0.0.0.1/` on Apple. Popups are blocked; Windows downloads and native permission requests are denied. There is no arbitrary native invocation target, filesystem bridge, external-browser launcher or native save API. A game needing one requires a separate narrow, validated native capability.

Android installs a guarded `MauiHybridWebViewClient` subclass after MAUI's base `ConnectHandler`, preserving packaged-resource interception. Installing the client only in `WebViewInitialized` would be overwritten by MAUI. Its main-frame request interception also denies non-local POST requests, which Android does not deliver to the navigation-override callback; local and subresource requests still use MAUI's loader. Android does not expose every `blob:` or `javascript:` operation through these request callbacks, so they must not be interpreted as complete content isolation. Windows points the WebView2 user-data cache to writable application data before control creation; this also supports installation beneath Program Files. Apple retains explicit navigation/UI delegates for the web view's lifetime.

These controls do not constitute a network sandbox. The game may still request remote subresources or HTTPS APIs under the platform's network rules; configure and review its CSP, endpoints, permissions, privacy policy, offline requirements and store declarations separately. No blanket cleartext-network exception is enabled. Remote content must not be treated as trusted executable game content.

Native window activation/resumption and deactivation/stopping dispatch `hephaera:lifecycle` DOM events with `{state: "resume"}` or `{state: "suspend"}`. Initial page load receives the current state. The game must explicitly subscribe and pause/resume its own rendering, simulation and audio. It must also handle `visibilitychange`, lost graphics contexts and normal scene disposal. The shell does not guess how an engine pauses, save gameplay, or automatically unlock an `AudioContext`. Notification failure is bounded and does not crash the app.

The initial .NET 10 host uses partial trimming, enables the HybridWebView feature switch and disables Native AOT. Full trimming/AOT is rejected rather than silently removing the web view. Do not apply .NET 11 source-generation examples to this pinned .NET 10 host.

## Packaging and release

`dotnet publish` prepares local distribution artifacts. It never submits them to a store. Windows defaults to `WindowsPackageType=None` for a published application folder. For this pinned MAUI `10.0.20` host with Windows App SDK `1.7.250909003`, use `WindowsPackageType=MSIX` for MSIX packaging; that SDK rejects the `Package` value shown in some other-version examples. Distribution signing requires the correct publisher/certificate identity. Set the package manifest publisher/display identity to the project's actual distribution identity. A placeholder publisher is not a valid production certificate.

Android selects `AndroidPackageFormats=apk` or `aab`; release signing uses the project's protected keystore. iOS device distribution uses `BuildIpa=true`, the exact device RID, a valid signing identity and a matching provisioning profile. Mac Catalyst uses `CreatePackage=true` when a `.pkg` is required, plus the correct signing/provisioning/notarization route. A Mac is required for Apple native builds. App Store/Play/Store accounts, device registration, paid memberships and external uploads require their own prerequisites and authorization.

Retain input web hashes, application identity/version, exact native source/template changes, tool versions, target/RID/configuration, signing identity reference without credentials, artifact hashes and QA evidence. Test actual installed release artifacts for cold launch, offline asset loading, renderer capability, input/touch/gamepad, resize/orientation/safe areas, audio unlock, suspend/resume, storage, context loss, native navigation rejection and uninstall/upgrade behavior. Browser or fixture passes do not replace native target checks. A compile or successful package does not establish playability, Wine/Proton compatibility, signing validity on another device or store acceptance.

## Primary references

- [Official MAUI supported platforms](https://learn.microsoft.com/en-us/dotnet/maui/supported-platforms?view=net-maui-10.0)
- [HybridWebView behavior and platform differences](https://learn.microsoft.com/en-us/dotnet/maui/user-interface/controls/hybridwebview?view=net-maui-10.0)
- [MAUI deployment and testing](https://learn.microsoft.com/en-us/dotnet/maui/deployment/?view=net-maui-10.0)
- [MAUI trimming feature switches](https://learn.microsoft.com/en-us/dotnet/maui/deployment/trimming?view=net-maui-10.0)
- [Pinned HybridWebView handler source](https://github.com/dotnet/maui/tree/10.0.20/src/Core/src/Handlers/HybridWebView)

The host source and SVG placeholders are independently authored for Hephaera. MAUI and platform dependencies retain their upstream licenses; no Microsoft source or sample application is bundled here.
