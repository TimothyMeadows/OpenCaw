# Subagent Plan: import-selected-capabilities

## Capacity
- Requested: 3
- Effective lanes: 3
- Reason: The game, web, and governance surfaces have disjoint write sets; shared catalogs and integration remain with the main agent.

## Rules
- Resolve each lane role with `./commands/resolve-role.sh` before delegation.
- Use `explorer` for read-only lanes and `worker` for implementation lanes when Codex subagents are available.
- Worker lanes must declare disjoint write sets.
- Keep the main agent responsible for orchestration, critical-path blockers, integration, final verification, and user communication.

## Lanes

### lane-1
- Role: computer-science/gameplay-engineer
- Agent type: worker
- Status: completed
- Scope: Implement the rigged-runtime actor capability, technical 3D role, manifest validator, and gameplay/action reference expansions.
- Write set: skills/prepare-rigged-runtime-actors, .roles/arts/technical-3d-artist, commands/validate-rigged-actor-manifest.sh, skills/build-gameplay-runtime, skills/design-action-gameplay
- Dependencies: none
- Expected output: Independently authored skill, role, references, and validator without shared catalog edits.
- Verification: Run skill validation for the new skill, Bash syntax and focused manifest fixtures, and report changed paths.

### lane-2
- Role: arts/web-experience-designer
- Agent type: worker
- Status: completed
- Scope: Implement the engine-neutral scroll-authored web experience skill and its one-level references.
- Write set: skills/build-scroll-authored-web-experiences
- Dependencies: none
- Expected output: Independently authored skill and interface metadata with renderer selection, scroll-state, accessibility, fallback, and performance contracts.
- Verification: Run skill validation for the new skill and verify every relative reference resolves.

### lane-3
- Role: computer-science/security-engineer
- Agent type: worker
- Status: completed
- Scope: Record adaptation boundaries, deepen release-ledger and evidence-matrix guidance, and add focused adaptation safety tests.
- Write set: skills/EXTERNAL_SOURCES.md, skills/build-game-production-tools, skills/verify-and-explain, tests/test-selected-capability-import.sh
- Dependencies: none
- Expected output: Capability disposition ledger, independently authored references, parent routing updates, and a deterministic focused test.
- Verification: Run the focused test plus skill safety and link validation for changed skills.

## Integration
- Merge order: lane-1, lane-2, lane-3, then shared catalog and documentation integration by the main agent.
- Conflict risks: Shared skill and role indexes, canonical role mapping, README, validation entrypoint, memory, repository map, and task files are integration-owner only.
- Final verification: Run focused tests, all structural validators, full OpenCaw validation with the recorded Gauntlet baseline comparison, and `git diff --check`.

## Results

### Result: lane-2 - completed - 2026-08-08T22:47:00Z
- Summary source: `.ai/tasks/import-selected-capabilities/lane-2-result.txt`

```text
Implemented the engine-neutral build-scroll-authored-web-experiences skill with renderer selection and scroll experience contract references.

Verification:
- skill-creator quick validation passed.
- OpenCaw skill safety validation passed for the skill.
- Both relative reference links resolved.
- Required renderer, story, state, accessibility, fallback, lifecycle, and performance concepts were present.
- Vendor and project identity scan passed.
- Whitespace validation passed.
```

### Result: lane-3 - completed - 2026-08-08T22:55:19Z
- Summary source: `.ai/tasks/import-selected-capabilities/lane-3-result.txt`

```text
Implemented the capability-boundary ledger, production release-ledger reference, acceptance/evidence matrix reference, parent-skill routing, and focused capability-import test.

Verification:
- Bash syntax passed for the focused test.
- Changed parent-skill safety and link validation passed.
- Boundary and reference-routing test sections passed.
- The initial integrated run failed closed only because the lane-1 rigged-actor validator had not yet landed; the integration owner will rerun the full test after lane-1 completion.
- Lane-scoped whitespace validation passed with only platform line-ending notices.
```

### Result: lane-1 - completed - 2026-08-08T23:03:17Z
- Summary source: `.ai/tasks/import-selected-capabilities/lane-1-result.txt`

```text
Implemented the rigged runtime actor skill, technical 3D artist role, strict executable manifest validator, and gameplay/action reference expansions.

Verification:
- Valid shipped character and monster manifests passed.
- Wrong schema, duplicate clip/socket/equipment IDs, missing action role, unknown socket, path escape, skeleton mismatch, missing file, incomplete verified evidence, and shipped-without-root cases failed closed.
- Bash syntax, executable mode, skill-creator validation, OpenCaw skill safety, role, skill, command, prohibited-source, credential, and whitespace checks passed.
- ShellCheck was unavailable in Git Bash and is not claimed.
- Temporary fixtures were removed.
```
