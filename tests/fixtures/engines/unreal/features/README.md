# Conditional Unreal feature suite

This isolated Editor-only source project targets UE 5.8. It has not been compiled or run here without a matching Editor, compiler and platform SDK. It does not impose 5.8 or enable plugins in host games. No engine, license, package, binary asset or external test framework is installed by the runner.

Run `tests/test-native-engine-fixtures.sh` after explicitly configuring `OPENCAW_UNREAL_FEATURE_PROJECT=tests/fixtures/engines/unreal/features/OpenCawFeatureFixture.uproject`, `OPENCAW_UNREAL_EDITOR`, `OPENCAW_UNREAL_UBT` and matching `OPENCAW_UNREAL_VERSION`. The existing source-only lifecycle fixture has its own `OPENCAW_UNREAL_PROJECT` selection. Missing selections/tools produce blocked results, not acceptance.

The feature runner copies this project into a disposable directory, resolves UNREAL there, builds only its Editor target and runs one exact Automation case per bounded native process. These fixtures deliberately use native engine dependencies; enabling them here does not select those features for any game. Required real binary assets and plugin actions must be authored with the matching native tools:

- [Gameplay and simulation cases](GameplayFixtures.md): async teardown; GAS grant and target ownership; CharacterMovement collision/teardown; Behavior Tree abort; Mass lifetime; Game Feature unloading.
- [Presentation cases](PresentationFixtures.md): camera ownership; real Niagara pool reuse; sequence evaluation/interruption/restoration.
- [World and data cases](WorldFixtures.md): streaming load/unload; deterministic PCG regeneration/cleanup; native save serialization, migration and transactional validation.

The manifest records exact names, required settings and claim limits. Add actual project-owned `/Game` assets to `Config/DefaultGame.ini` under `[OpenCaw.UnrealFeatures]`; the runner hashes prerequisites and blocks missing files. Invalid assets or wrong behavior fail in Unreal. No arbitrary binary bytes stand in for native assets. Plugin activation tests require the isolated project-owned Game Feature described in the gameplay instructions.

`FeatureEvidence.h` records the runner's fresh `OPENCAW_UNREAL_FEATURE_RUN` nonce inside each Automation result. This test-only marker establishes invocation identity, not human approval or gameplay quality. Reports must contain exactly the selected successful test, no error events or failed/unrun tests, the matching marker and current timing; process failure always wins over a passing-looking file. Simulated report/process tests are labeled separately.

Compile/headless results cannot certify visuals, audio, physical haptics, camera comfort, packaged gameplay or network correction. Movement correction/prediction requires an additional real server/client scenario with adverse network conditions; GAS prediction, World Partition/HLOD/cook, GPU Niagara, platform saves and selected optional systems require their own project evidence. Preserve those cases as not-run until exercised. Mover, StateTree and CQTest are not automatic fixture dependencies.
