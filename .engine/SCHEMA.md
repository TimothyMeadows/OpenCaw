# Engine Contract Schema

`registry.json` is canonical for six IDs, normalized aliases, prefixes, supported languages, `runtimeKind` (`web` or `native`), `particleBackend` (`THREE_QUARKS` for THREEJS, null otherwise), feature bindings, legacy skill aliases and engine-bound commands. `validate-engines.sh` checks all classifications, prefixes and bindings. Metadata arrays contain one canonical engine or AGNOSTIC.

A generated ENGINE.md contains exactly one `Selected OpenCaw engine:` list with one canonical ID inside a unique managed block. It reads the matching .engine definition or embeds its complete current text. Regeneration replaces only that block. Unknown IDs, duplicates, conflicting read directives, stale/incomplete inline definitions and conflicting production evidence fail. Three browser architecture files remain compatibility redirects and do not create a second engine selector.

Resolution scans production directories to bounded depth/count, excluding baseline configuration, dependencies, tests, task state and isolated prototypes. Root or nested Unity ProjectVersion, Godot project.godot, Unreal .uproject and engine package dependencies establish existing engine evidence. Ambiguous or conflicting evidence requires migration rather than fallback.

Override JSON schemaVersion 1 records projectEngine, effectiveEngine, selectionSource prompt, contract and hashes for project definition, effective definition, registry and task, plus task and outputScope. Its adjacent .sha256 detects accidental evidence edits. Consumers recheck current contracts, task, scope, path components and prototype engine evidence. Allowed runtime outputs are isolated prototypes/NAME or task-local prototypes/NAME. CODE commands accept --engine-evidence; source/adapter paths must remain in that scope and manifest/review outputs must remain in the recorded task. No receipt is an authentication service or OS sandbox.

Resolvers emit deterministic JSON with project/effective selection, compatibility and exclusion reasons; a missing authoritative contract resolves THREEJS only if no conflicting evidence exists. `validate-engine-contract.sh` requires a real contract. An alternate path is allowed for read-only validation, never for production or skill activation. Engine selection neither installs dependencies nor selects art pipelines.


## Derived native packaging capability

`runtimeKind: web` derives `runtimeKind` and a `packaging` object in resolution, generation, skill and role output. Its `profile` is `MAUI`, `selectionSource` is `engine`, `platforms` is exactly `WINDOWS`, `MACOS`, `ANDROID`, `IOS` in that order, and `nativeReadiness` is `unverified`. `runtimeKind: native` instead returns a null profile, empty platform list and `nativeReadiness: not-applicable`; those engines retain their own exporters. Missing/unknown runtime metadata fails closed.

Packaging follows the effective engine, including a valid isolated override. It is recomputed from current registry metadata when consuming a receipt; serialized packaging fields are not a separate selector or permission. Registry hashes preserve override freshness. Existing read-directive ENGINE.md contracts need no rewrite to acquire this capability; stale inline definitions require explicit regeneration under the existing contract rules. No resolution/generation creates a packaging contract/project, probes workloads, installs, restores or publishes. The initial MAUI target set excludes Linux and TV; Windows Wine/Proton compatibility is not implied.

## Derived particle capability

THREEJS requires registry `particleBackend: THREE_QUARKS`; the five other registered engines require null. Missing or conflicting metadata fails before generated contract writes. Resolution, generation, skill and role output expose `particles` as null for other engines, or as this object for the effective THREEJS selection:

```json
{
  "backend": "THREE_QUARKS",
  "package": "three.quarks",
  "skill": "threejs-build-particles",
  "selectionSource": "engine",
  "renderer": "WebGLRenderer",
  "readiness": "unverified",
  "testedVersion": "0.17.1",
  "testedCoreVersion": "0.17.1",
  "minimumThreeVersion": "0.182.0"
}
```

The version fields identify the initial tested API/dependency pair and upstream peer minimum, not a host installation or upgrade instruction. Capability metadata is recomputed from the effective engine on valid override recording and consumption; serialized `particles` fields cannot select another package/backend, claim readiness or bypass registry/task/definition freshness. MAUI packaging and engine selection remain unchanged. No resolution/generation probes node_modules, imports the library, creates helper source, installs dependencies or renders particles. Read-directive contracts acquire current guidance automatically; stale inline definitions retain their explicit regeneration requirement.
