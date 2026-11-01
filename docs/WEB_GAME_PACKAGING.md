# Native packaging for web games

## Selection and targets

Selecting THREEJS, BABYLONJS or PHASERJS automatically selects the MAUI packaging profile. This is derived from the engine registry's `runtimeKind: web`; MAUI does not become another game engine, architecture selection or visual/media pipeline. Existing read-directive `ENGINE.md` contracts need no regeneration; stale inline definitions require explicit regeneration after shared-definition changes as usual. Default Three.js selection and validated isolated engine overrides follow the same rule. Unity, Unreal and Godot retain their native exporters.

The profile embeds a completed static HTML/JavaScript/CSS build in a .NET 10 `HybridWebView`. It works with bundled web-engine output without translating gameplay into C#. It does not embed a Node server, run an npm build, or make browser APIs universally portable.

| Target | Native host | Build machine | Distribution formats |
| --- | --- | --- | --- |
| WINDOWS | WinUI / WebView2 | Windows | Published application folder or MSIX |
| MACOS | Mac Catalyst / WKWebView | Mac with compatible Xcode | `.app` or signed `.pkg` |
| ANDROID | Android WebView | Windows or Mac with compatible Android SDK/JDK | APK for installation, AAB for store distribution |
| IOS | iOS / WKWebView | Mac with compatible Xcode and provisioning | Signed device IPA |

Only these four official MAUI platforms are supported. Linux, TVs and Tizen are excluded. Linux users may try the Windows output through Wine or Proton; neither compatibility nor WebView2/Windows App SDK operation is guaranteed.

## Create a host

Run examples from an installed host project's root. In a maintainer source checkout, use `commands/` instead of `.hephaera/commands/`.

```bash
bash .hephaera/commands/resolve-engine.sh
bash .hephaera/commands/web-game-package.sh resolve
bash .hephaera/commands/web-game-package.sh doctor --target WINDOWS
bash .hephaera/commands/web-game-package.sh init \
  --app-id com.example.mygame --title "My Game" \
  --web-root dist --output platforms/maui
```

Automatic selection creates no host, installs no SDK/workload and accepts no licenses. `doctor` reads installed SDK/workload metadata and checks the build-machine OS. `buildEligible` permits an attempt; `nativeReadiness: unverified` remains until the compiler runs. It does not certify Xcode compatibility, Android SDK/JDK completeness, signing, devices or store access. Install the official tools separately when authorized.

`init` writes `web-game-package.json` and a new owned native source directory. It refuses existing output/configuration. Commit the host source and configuration with the game, excluding `bin/`, `obj/`, private signing files and `.hephaera/.cache/`. The shipped MAUI Controls dependency is pinned to `10.0.20`; servicing updates require a reviewed baseline change and fresh builds. Other platform SDKs/workloads must be compatible with that version.

The configuration contains `schemaVersion: 1`, `profile: MAUI`, `appId`, `title`, `displayVersion`, `buildNumber`, `hostDirectory`, `webRoot` and `entry`. Use lowercase reverse-DNS identity, numeric `major.minor.patch` display version and a monotonically increasing build number from 1 to 65535. Default entry is `index.html`. Edit title, version, build number or entry explicitly, then sync. Changing `appId` requires a fresh configuration/native host; do not relabel an existing ownership receipt. Generated `HephaeraGame.props` comes from configuration; put native customizations in their own source/property files rather than editing generated properties.

## Stage the game and plan a package

Build the game's static distribution using its existing locked toolchain. All required scripts, chunks, textures, WASM and audio must be included. Then:

```bash
bash .hephaera/commands/web-game-package.sh sync
bash .hephaera/commands/web-game-package.sh plan --target WINDOWS --format folder
bash .hephaera/commands/web-game-package.sh build --target WINDOWS --rid win-x64
bash .hephaera/commands/web-game-package.sh package --target WINDOWS --format folder --rid win-x64
```

`plan` performs no restore, compilation or installation. `build` and `package` explicitly invoke `dotnet build` and `dotnet publish` on `GameHost.csproj`, narrowed to the selected framework. Normal project restore may download NuGet dependencies; these commands never install workloads, drivers or SDKs. `--timeout-seconds` bounds the native process tree (default 1200; range 1–3600). Cancellation/failure never reuses an older successful package. Native tool stdout/stderr is not persisted, protecting signing inputs; run the reviewed plan manually for compiler diagnostics when needed.

`sync` checks portable project paths, source files and existing owned assets before replacement. It stages exact bytes, keeps removed files out of the current app, and preserves prior staged versions/receipts in durable `.hephaera/.cache/packaging/`. Links/junctions, traversal, case collisions, unsafe Windows names, overlapping source/output, foreign directories and changed staged content are rejected. Source/configuration/native code/engine/template changes make a snapshot stale and require explicit review and resync. These are cooperative local guards, not a hostile-filesystem sandbox.

The native host is editable source. After approved native changes, sync again to bind the current native files. Never copy a host between applications and relabel its ownership receipt. Init and sync prepare complete changes before publishing, retain a write-ahead ownership journal and roll back ordinary failures without deleting prior state. An interrupted pending transaction blocks further work. Run `web-game-package.sh recover` with the same configuration to restore the prior owned state, or reconcile an already committed transaction; changed or foreign bytes stop recovery. Keep simultaneous operations serialized by the command's project-local lock. If a process was interrupted while holding the lock, first verify no operation is still running, remove only its empty lock directory, then use recovery. Never remove a lock blindly.

Custom `--config` paths are project-relative. A validated `--engine-evidence` receipt restricts the config, web output and host to that isolated prototype scope; it cannot package another existing game.

## Package each platform

Run each command on the compatible machine from the table. Defaults are Windows x64, Mac Catalyst arm64, Android arm64 and iOS arm64. Supported alternate RIDs are `win-arm64`, `win-x86`, `maccatalyst-x64` and `android-x64`.

```bash
# Windows application folder; keep all published dependencies together.
bash .hephaera/commands/web-game-package.sh package --target WINDOWS --format folder
# Signed MSIX; publisher must match the selected signing identity.
bash .hephaera/commands/web-game-package.sh package --target WINDOWS --format msix \
  --signing-properties release/windows.private.props
# Android device-installable package or Play bundle.
bash .hephaera/commands/web-game-package.sh package --target ANDROID --format apk
bash .hephaera/commands/web-game-package.sh package --target ANDROID --format aab \
  --signing-properties release/android.private.props
# Mac Catalyst application or installer (on a Mac).
bash .hephaera/commands/web-game-package.sh package --target MACOS --format app
bash .hephaera/commands/web-game-package.sh package --target MACOS --format pkg \
  --signing-properties release/apple.private.props
# Provisioned iOS device archive (on a Mac).
bash .hephaera/commands/web-game-package.sh package --target IOS --format ipa \
  --signing-properties release/apple.private.props
```

Private MSBuild files are trusted executable build inputs. They must remain project-local, ignored and reviewed; reference secret environment variables instead of placing credential values in CLI arguments. Windows needs its package publisher/certificate settings; Android needs its keystore alias/path and signing settings; Apple needs the signing identity, provisioning profile and applicable entitlements. Release signing identities must be supplied explicitly. Android build tooling may use or create its development signing key when no release keystore is configured; a development-signed APK is QA output, not a store release. No command changes accounts, enrolls devices or accepts agreements. See the [native host contract](../.packaging/maui/PACKAGING.md) for platform-specific configuration.

Successful runs retain a unique output directory and hashed files under `.hephaera/.cache/packaging/…/runs/`. Read the returned `output` path; don't reuse a path from an earlier run. Receipts retain sanitized SDK/workload identities and the resolved NuGet assets identity when available, in addition to command/source identities. The receipt reports `nativeReadiness: compiled`, `signing: unverified`, `deviceQa: not-run`, `releaseReady: false` and `storeSubmitted: false`. A compiler success and matching extension do not certify a signature, complete game behavior, notarization or store eligibility.

## Release and actual target QA

Before distribution, replace placeholder icon/splash branding, review identity/version/publisher, privacy/permissions, licensed content, media disclosure and game-specific entitlements. Test the actual package on each target. Measure startup, frame pacing, memory/thermal behavior and input. Verify WebGL2/WebGPU requirements, WASM MIME/loading and worker assumptions, local chunks/assets, offline operation, persistence, audio unlock, suspend/resume, resize/safe areas, touch/gamepad/keyboard, pointer lock/fullscreen and graphics-context loss. Threaded WASM/cross-origin isolation and WebGPU are not guaranteed by packaging. Browser tests do not replace native WebView/device QA.

The host sends `hephaera:lifecycle` events with `{state: 'resume'}` or `{state: 'suspend'}`. The game must explicitly pause/resume its own engine, simulation and audio and handle `visibilitychange`. Native navigation stays on the packaged origin and popups are blocked; no JavaScript-to-native filesystem or arbitrary method bridge is installed. Remote resource requests remain subject to the game's CSP and platform networking policy.

For Windows, validate the signature/MSIX installation and Microsoft Store requirements when that channel is selected. For Android, verify signed APK installation and signed AAB in an authorized Play testing track. For Apple, validate signatures, provisioning, entitlements and on-device behavior; complete notarization for applicable Mac distribution and TestFlight/App Store Connect review for iOS. Submission, external upload, store publication and GitHub release publication require the user's selected channel and authorization. Preparing a local package grants none of those actions.

Use GitHub Actions for host CI. Run the packaging selection, execution and transaction regression suites on Windows/Linux; build each native target on its compatible runner with explicitly provisioned matching tools. Store signing secrets in protected environment secrets, keep private props out of artifacts, upload only reviewed package outputs and keep publication behind the selected release environment. Source CI does not pretend to produce Apple/mobile packages without their prerequisites.

## Official references

- [MAUI supported platforms](https://learn.microsoft.com/en-us/dotnet/maui/supported-platforms?view=net-maui-10.0)
- [HybridWebView and packaged local content](https://learn.microsoft.com/en-us/dotnet/maui/user-interface/controls/hybridwebview?view=net-maui-10.0)
- [Deployment, platform tools and distribution](https://learn.microsoft.com/en-us/dotnet/maui/deployment/?view=net-maui-10.0)
- [.NET Android signing process and development key defaults](https://github.com/dotnet/android/blob/main/Documentation/docs-mobile/building-apps/build-process.md)
- [MAUI trimming constraints](https://learn.microsoft.com/en-us/dotnet/maui/deployment/trimming?view=net-maui-10.0)
