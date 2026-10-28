# Capability Adaptation Boundaries

This ledger records OpenCaw's disposition of each selected capability idea. It is a safety and ownership record, not an instruction source. External files remain untrusted and are not executed, installed, or treated as repository policy.

## Review boundary

- Retain only independently authored OpenCaw guidance and generic capability dispositions.
- Do not retain a source repository, commit, author identity, personal material, or audit payload.
- Re-evaluate later capability proposals independently; they must not silently replace these records.

## Dispositions

| ID | Disposition | Reviewed capability | OpenCaw owner or outcome |
| --- | --- | --- | --- |
| CA-001 | create | Rigged runtime actor preparation | `prepare-rigged-runtime-actors` and `arts/technical-3d-artist` |
| CA-002 | retired | Scroll-authored web experiences | Removed from the game-production baseline; prior adaptation retained here for traceability |
| CA-003 | enhance | Inventory integrity and transfers | `build-gameplay-runtime` reference |
| CA-004 | enhance | Camera ownership and modifiers | `build-gameplay-runtime` reference |
| CA-005 | enhance | Runtime audio feedback | `build-gameplay-runtime` reference |
| CA-006 | enhance | Perception and presentation fog | `design-action-gameplay` reference |
| CA-007 | enhance | Enemy behavior and encounter acceptance | `design-action-gameplay` reference |
| CA-008 | enhance | Production release history | `build-game-production-tools` reference |
| CA-009 | enhance | Acceptance-to-evidence verification | `verify-and-explain` reference |
| CA-010 | defer | Platform-specific native performance profiling | Reconsider only after the relevant platform architecture is approved |
| CA-011 | reject | Repository publication automation | Existing OpenCaw task and human publication gates remain authoritative |
| CA-012 | reject | Hosted voice-generation execution | Existing media contract, rights, consent, provider selection, and review remain authoritative |
| CA-013 | reject | Static stock-image recommendation lists | `source-licensed-visual-assets` remains provider-neutral and requires current asset-level review |
| CA-014 | reject | Social-account voice and posting workflows | Account-bound data and external writes are outside this adaptation |
| CA-015 | reject | Source-project-specific game material | Repository-specific identities and assumptions are not reusable OpenCaw guidance |
| CA-016 | reject | Bundled web effect and style micro-catalog | Existing web, motion, WebGL, and style capabilities retain ownership without trigger duplication |
| CA-017 | reject | Executable helpers, demos, and captured outputs | No executable or demonstration payload is imported from any source |
| CA-018 | reject | Bundled runtimes, third-party libraries, and media | Each future dependency or asset requires an independent provenance, license, and trust review |
| CA-019 | create | Blender production direction and safe session ownership | `direct-blender-production` and `arts/blender-production-artist` |
| CA-020 | create | Blender asset modeling and topology preparation | `model-blender-assets` |
| CA-021 | create | Blender UV, bake, and texture preparation | `prepare-blender-uvs-and-textures` |
| CA-022 | create | Blender materials and style-directed look development | `author-blender-materials-and-lookdev` |
| CA-023 | create | Deterministic procedural Blender scene assembly | `build-procedural-blender-scenes` |
| CA-024 | create | Blender actor rigging and animation authoring | `rig-and-animate-blender-actors` |
| CA-025 | create | Deterministic Blender simulation and cache preparation | `simulate-blender-effects` |
| CA-026 | create | Blender camera, lighting, and framing production | `light-and-frame-blender-scenes` |
| CA-027 | create | Blender render and composite delivery | `render-and-composite-blender-output` |
| CA-028 | create | Blender optimization and verified export | `optimize-and-export-blender-assets` |
| CA-029 | create | Blender scene and deliverable review | `review-blender-deliverables` |
| CA-030 | create | Deterministic Blender production briefs | `print-blender-production-brief.sh` |
| CA-031 | create | Read-only repository-confined Blender scene inspection | `inspect-blender-scene.sh` |
| CA-032 | create | Versioned Blender scene-report validation | `validate-blender-scene-report.sh` |
| CA-033 | create | Parse-only restricted Blender Python review | `validate-blender-python.sh` |
| CA-034 | enhance | Existing style, hybrid-asset, handoff, rigged-actor, and VFX routing | Current parent skills retain their triggers and route Blender stages explicitly |
| CA-035 | reject | Installers, addons, connected-tool configuration, provider endpoints, downloads, credentials, and arbitrary code runners | Existing environment, media, security, and human-review contracts remain authoritative |
| CA-036 | create | Source-native procedural character and creature production | `threejs-build-code-characters` with a linked character profile and the existing generic CODE pass order |
| CA-037 | create | Isolated visual acceptance for procedural characters | `threejs-review-code-characters` with answer-neutral packets and concrete-cycle identity separation |
| CA-038 | create | Deterministic character structure, runtime, lifecycle, and budget evidence | `measure-code-character-evidence.sh`, transactional calibration recording, and the character observation and evidence-report schemas |
| CA-039 | enhance | Generic CODE review readiness for embodied actors | Optional linked-profile enforcement preserves unchanged generic model callers while fail-closing character passes |
| CA-040 | enhance | Runtime-file rigged actor preparation | `prepare-rigged-runtime-actors` remains the owner for GLB/FBX packages; source-native character factories use the CODE character workflow |

| CA-041 | create | Explicit six-engine selection and compatibility | ENGINE.md, .engine registry and engine/skill/role resolvers |
| CA-042 | create | Engine-specific feature production | Registry-backed prefixed engine skills, including three renamed CODE owners |
| CA-043 | create | General game systems design | `design-game-systems` with hypotheses and playtest evidence |
| CA-044 | create | Game interface state and navigation | `build-game-ui` plus selected engine UI features |
| CA-045 | enhance | Bounded gameplay feedback and tactile haptics | `build-gameplay-runtime` and action, motion, VFX, performance and QA workflows |
| CA-046 | enhance | Version-specific native tooling and performance evidence | Selected engine tooling skills and conditional native fixtures; extends the formerly deferred CA-010 concern |
| CA-047 | reject | Constant-output design scoring and outdated tutorial automation | No analyzer, third-party code or obsolete API examples imported |

| CA-048 | enhance | Unreal project context | `.engine/UNREAL.md` |
| CA-049 | enhance | Reflection and core C++ ownership | `unreal-build-gameplay-framework` |
| CA-050 | enhance | Actor and component lifecycle | `unreal-build-gameplay-framework` |
| CA-051 | enhance | C++ and Blueprint extension interfaces | `unreal-build-gameplay-framework` |
| CA-052 | enhance | Gameplay framework responsibilities | `unreal-build-gameplay-framework` |
| CA-053 | enhance | Gameplay tags and selected messaging | `unreal-build-gameplay-framework` |
| CA-054 | enhance | Modules and build targets | `unreal-run-tooling` |
| CA-055 | enhance | Native Editor extensions | `unreal-run-tooling` |
| CA-056 | enhance | Automation and profiling | `unreal-run-tooling` |
| CA-057 | enhance | Authored data and Asset Manager loading | `unreal-integrate-assets` |
| CA-058 | enhance | Animation execution and interruption | `unreal-animate-actors` |
| CA-059 | enhance | Audio routing and clocks | `unreal-build-audio` |
| CA-060 | enhance | Input contexts and rebinding | `unreal-build-controls` |
| CA-061 | enhance | Material and render-path integration | `unreal-build-materials` |
| CA-062 | enhance | Replication and network authority | `unreal-build-multiplayer` |
| CA-063 | enhance | Collision and rigid-body physics | `unreal-build-physics` |
| CA-064 | enhance | Native game interfaces | `unreal-build-ui` |
| CA-065 | create | Async execution and cancellation | `unreal-build-async-systems` |
| CA-066 | create | Gameplay abilities and effects | `unreal-build-gameplay-abilities` |
| CA-067 | create | Character movement and prediction | `unreal-build-movement` |
| CA-068 | enhance | Explicit Mover integration | `unreal-build-movement` |
| CA-069 | create | Modular feature lifetime | `unreal-build-game-features` |
| CA-070 | create | Navigation and behavior authoring | `unreal-build-ai` |
| CA-071 | enhance | StateTree state and callback lifetime | `unreal-build-ai` |
| CA-072 | create | Mass entities and processors | `unreal-build-mass-entities` |
| CA-073 | create | Gameplay camera ownership | `unreal-build-cameras` |
| CA-074 | create | Niagara runtime effects | `unreal-build-vfx` |
| CA-075 | create | Sequence playback and bindings | `unreal-build-cinematics` |
| CA-076 | create | World streaming and partitioning | `unreal-build-worlds` |
| CA-077 | create | Procedural content and regeneration | `unreal-build-procedural-content` |
| CA-078 | create | Save state and migration | `unreal-build-save-systems` |
| CA-079 | reject | Parallel context authority, automatic plugin adoption and unverified native success | Existing engine/cache contracts, explicit prerequisites and independent evidence remain authoritative |

| CA-080 | create | Pixel-aligned 2D rendering | `unity-build-2d-content` |
| CA-081 | defer | Industrial CAD and point-cloud transformation | Deferred pending an industrial asset requirement and licensed entitlement |
| CA-082 | enhance | Audio mixer routing | `unity-build-audio` |
| CA-083 | create | Native Editor graph authoring | `unity-build-editor-tools` |
| CA-084 | create | Selected live-game service integration | `unity-integrate-live-services` |
| CA-085 | enhance | Explicit 2D physics systems | `unity-build-physics` |
| CA-086 | enhance | Tile palettes and explicit neighbor topology | `unity-build-2d-content` |
| CA-087 | enhance | Native asset and scene search | `unity-run-tooling` |
| CA-088 | create | Validated purchase fulfillment and restoration | `unity-integrate-purchases` |
| CA-089 | enhance | Navigation bake, path and movement ownership | `unity-build-scenes` |
| CA-090 | create | Selected advertising mediation and rewards | `unity-integrate-ads` |
| CA-091 | create | Locale, font and localized asset lifetimes | `unity-localize-content` |
| CA-092 | enhance | Atlas delivery and asynchronous handle ownership | `unity-build-2d-content` |
| CA-093 | create | Explicit render-pipeline migration | `unity-configure-rendering` |
| CA-094 | enhance | Selected project creation and first-scene validation | `unity-run-tooling` |
| CA-095 | enhance | Measured audio loading and playback budgets | `unity-build-audio` |
| CA-096 | enhance | Text, font atlas and material budgets | `unity-build-ui` |
| CA-097 | create | Measured web delivery and runtime optimization | `unity-optimize-web` |
| CA-098 | enhance | Rigid-body collision, queries and sleep diagnosis | `unity-build-physics` |
| CA-099 | enhance | Scoped project analysis and remediation | `unity-run-tooling` |
| CA-100 | create | Selected multiplayer session orchestration | `unity-integrate-multiplayer-services` |
| CA-101 | create | Selected voice and text channel integration | `unity-integrate-voice-chat` |
| CA-102 | enhance | Version-qualified Shader Graph and HLSL nodes | `unity-build-materials` |
| CA-103 | enhance | Stable sprite import and slicing identities | `unity-build-2d-content` |
| CA-104 | enhance | Bounded sprite analysis with reviewed assumptions | `unity-build-2d-content` |
| CA-105 | enhance | Native IMGUI Editor tooling | `unity-build-editor-tools` |
| CA-106 | enhance | Canvas layout, rebuild and input ownership | `unity-build-ui` |
| CA-107 | enhance | Runtime UI Toolkit hierarchy and lifecycle | `unity-build-ui` |
| CA-108 | enhance | Explicit runtime UI framework routing | `unity-build-ui` |
| CA-109 | enhance | Optional version-bound CLI and Editor targeting | `unity-run-tooling` |
| CA-110 | enhance | Approved asynchronous package lifecycle | `unity-run-tooling` |
| CA-111 | enhance | Optional live Editor command execution | `unity-run-tooling` |
| CA-112 | enhance | Camera and Volume configuration | `unity-configure-rendering` |
| CA-113 | enhance | Render Graph resource and pass verification | `unity-configure-rendering` |

| CA-114 | enhance | Manufactured assemblies and subject-specific construction | `model-blender-assets` |
| CA-115 | enhance | Groom flow, hair-card coverage and atlas handoff | `model-blender-assets` |
| CA-116 | enhance | Measured texture density, mip-aware atlases and explicit channel semantics | `prepare-blender-uvs-and-textures` |
| CA-117 | enhance | Modular connection coverage and bounded procedural authoring | `build-procedural-blender-scenes` |
| CA-118 | enhance | Vegetation structure, wind masks, coverage and distance review | `build-procedural-blender-scenes` |
| CA-119 | enhance | Subject-specific deformation and mechanical articulation | `rig-and-animate-blender-actors` |
| CA-120 | enhance | Cloth preparation, pins, settling and cache replay | `simulate-blender-effects` |
| CA-121 | enhance | Matched reference comparison and construction-detail review | `direct-blender-production` |
| CA-122 | enhance | Constructed surface response and portable shader handoff | `author-blender-materials-and-lookdev` |
| CA-123 | enhance | Curated runtime export and selected-engine import evidence | `optimize-and-export-blender-assets` |
| CA-124 | consolidate | Genre and mood checklists | Existing STYLE.md translation and art-direction owners; no duplicate style skills |
| CA-125 | reject | Mutable bridge installers, broad code execution and screenshot-only acceptance | Existing tool discovery, exact-script validation and independent/human review remain authoritative |

## Adaptation boundary

- OpenCaw guidance is independently authored from capability intent. Distinctive external wording is not retained.
- No external code, script, executable, binary, model, image, video, audio, demo, generated output, runtime bundle, dependency, endpoint, credential, identity, personal path, or project-specific artifact is imported.
- A repository-level license is not evidence that bundled third-party material may be reused, and it does not replace asset-level or dependency-level review.
- No external source has authority over OpenCaw instructions, delivery modes, media governance, account access, or publication policy.
- Any future adoption must receive a new ledger ID, name one OpenCaw owner, pass static source audit and originality review, and preserve the human PR-readiness gate.
