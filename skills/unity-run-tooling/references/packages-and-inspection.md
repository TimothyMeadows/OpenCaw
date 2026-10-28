# Package lifecycle and project inspection

## Establish the project identity

Inspect `ProjectSettings/ProjectVersion.txt`, package manifest/lock, assembly definitions and target build settings as data before launching tools. Record the installed Editor path/version, target modules and project-owned build/test entry points. Template-based project creation requires an absent approved destination and explicit template/version; it does not authorize replacing an existing project or installing a missing Editor. Keep generated evidence under resolved `.opencaw/.cache` and build outputs in an approved non-source location.

## UPM requests

Use `UnityEditor.PackageManager.Client` only through a controlled Editor owner. Its requests complete asynchronously; retain each `Request` and inspect `IsCompleted`, `Status`, `Result` and `Error` rather than assuming that returning from `List`, `Add` or `Remove` means success. Poll through an Editor update/coroutine within a deadline; do not block the main thread while waiting for the request. Preserve exact failure messages after secret/path sanitization. [Client API](https://docs.unity3d.com/6000.0/Documentation/ScriptReference/PackageManager.Client.html).

For read-only verification, prefer installed/offline inventory and compare resolved name/version/source against the project lock. Offline inventory does not prove remote registry availability. Adding/removing/upgrading packages changes the project and may trigger resolution, imports and compilation; perform only an authorized explicit selection, serialize conflicting operations, inspect the resulting manifest/lock diff and await stable compilation before testing. Do not invoke package restoration as an invisible prerequisite fallback.

## Search and audits

Use Unity Search providers and version-supported `SearchService` requests to discover project assets/types/settings. Scope by provider/filter and inspect asynchronous completion, errors and empty results. Search indexes may lag or include package assets; resolve GUIDs/paths back to their owning project/package and do not edit a read-only package to satisfy a result. [Search request API](https://docs.unity3d.com/6000.0/Documentation/ScriptReference/Search.SearchService.Request.html).

Project Auditor is optional. Confirm its installed package/API and report analysis scope, source/assembly inclusion, build target and actual findings. Static recommendations require contextual review and cannot certify frame-time, memory or platform behavior. Do not upgrade or install the auditor merely to obtain a report. Keep actionable findings linked to project-owned code/assets and distinguish suppressed, blocked and unreviewed items. [Project Auditor 1.0 documentation](https://docs.unity3d.com/Packages/com.unity.project-auditor@1.0/manual/index.html); use the installed version's documentation.

## Evidence

For tests, require nonempty discovery and terminal results for every selected case, plus process success and a fresh report bound to the current invocation. A report from another process/run, unfinished request or passing XML beside a failed Editor exit is a failure. For builds, record the actual BuildReport result, target, output identity and resulting player's startup/shutdown. Batchmode smoke tests do not establish visual, audio, networking or device acceptance.
