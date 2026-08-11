# AGENTS.md

## Purpose
This mounted repository is the shared AI baseline for the division.
It should be mounted directly as one of:
- `./.codex`
- `./.cursor`
- `./.claude`

## Layering contract
This folder is the shared configuration layer.
It is not the project-memory layer.

All memory and context artifacts live under the resolved repository root:
- always-loaded system memory: `<project-root>/.ai/SYSTEM_MEMORY.md`
- tagged project memory: `<project-root>/.ai/MEMORY.md`
- semantic repository map: `<project-root>/.ai/REPO_MAP.md`
- project rules: `<project-root>/.ai/RULES.md`
- debug history: `<project-root>/.ai/DEBUG.md`
- task notes: `<project-root>/.ai/tasks/`

Optional pre-planning Brainstorm state lives at the resolved repository root:
- full durable ideas and active state: `<project-root>/BRAINSTORM.md`
- generated exit index: `<project-root>/BRAINSTORM_SUMMARY.md`

Resolve these paths with `./commands/resolve-opencaw-paths.sh`. Never infer a broad workspace parent when resolution fails.

Never write project-specific learned state into this mounted baseline unless the user explicitly asks to modify the shared baseline.

## Session startup review
At session start, follow this memory-first sequence:

On Windows without a usable Bash runtime, run the PowerShell bootstrap described in **Windows Bash bootstrap** before this sequence.

1. Resolve the project root and repository-local `.ai` paths with `./commands/resolve-opencaw-paths.sh`.
2. Run `./commands/create-host-ai-scaffold.sh` automatically when required files are missing. The command is idempotent and reports legacy-memory migration needs.
3. Load all of `SYSTEM_MEMORY.md`. It has precedence over project memory and rules, but never over actual system, developer, or current user instructions.
4. Run `./commands/brainstorm-mode.sh status` when the command is available. If `BRAINSTORM.md` is active, load all of it and restore Brainstorm mode before planning, task tracking, Goal, or Gauntlet selection; reconstitute its two researcher subagents before processing ideas.
5. Review project `RULES.md`, `ARCHITECTURE.md`, `STYLE.md`, active task tracking, active goal or Gauntlet state, and open issues when present. Read `DEBUG.md` only for debugging work.
6. Run `./commands/query-project-context.sh --list-tags`, infer relevant tags from the request and active task, then query those tags with the default ranked limit before raw file searches.
7. Run `./commands/repo-map-status.sh`. If the map is missing, empty, or stale, use `maintain-repository-map` before relying on it.
8. If legacy memory is reported, prepare and complete the AI-classified migration before loading untagged entries. Never load legacy memory as a fallback.

Read `../MEDIA.md` only when the current task configures, generates, validates, or promotes image or audio media. Do not load it for unrelated work.

You should send a message to the user that you are an OpenCaw session and ready for usage.

## Windows Bash bootstrap

- Linux and macOS use their existing Bash runtime; do not run Windows bootstrap or installation logic there.
- On Windows, prefer an existing Git Bash runtime for native filesystem performance and lower startup overhead.
- If Bash is missing, run `powershell -NoProfile -ExecutionPolicy Bypass -File "./<mount>/commands/install-windows-bash.ps1"` to inspect providers.
- Install software only when the user explicitly requests it or runs the installer with `-Install`; never install Bash during ordinary scaffold creation.
- Use `-Provider GitBash -Install` for the recommended native Windows provider or `-Provider WSL -Install` when Linux tooling compatibility is required.
- Use `-RunScaffold -ProjectRoot <path>` after discovery or installation to invoke the canonical Bash scaffold.
- The scaffold writes `.ai/WINDOWS_BASH.md` only when it detects a Windows host, Git Bash/MSYS/Cygwin, or WSL.

## Architecture workflow
The canonical architecture contract for the host repository is:

- `../ARCHITECTURE.md`

Architecture templates live in:

- `./.architecture/`

### When `../ARCHITECTURE.md` exists
- Read it and follow it as the authoritative architecture contract.

### When `../ARCHITECTURE.md` is missing
- Ask the user which architecture templates in `./.architecture/` apply to the repository.
- Support selecting multiple templates for multi-architecture repositories.
- After the user answers, generate `../ARCHITECTURE.md` with `./commands/generate-architecture.sh "<TEMPLATE1>" ["TEMPLATE2" ...]`.
- Default generation must use concise read directives (for example `Read \`./<mount>/.architecture/DOTNET.md\` instructions`) instead of inlining template text.
- Use `--inline` only when the user explicitly asks for fully embedded template content.
- Once generated, use `../ARCHITECTURE.md` as the authoritative architecture contract.

### When regenerating architecture later
- Ask the user again which templates apply.
- Regenerate `../ARCHITECTURE.md` with the same default read-directive mode unless inline output is explicitly requested.

## Art style and pipeline workflow
The canonical visual contract for the host repository is:

- `../STYLE.md`

Style templates live in:

- `./.styles/`

Art pipeline contracts live in:

- `./.styles/.pipelines/`

Registered pipelines are `CLOUD`, `LOCAL`, `CSS3`, `CODE`, and `BLENDER`. Every generated `STYLE.md` contains at least one art style, exactly one primary pipeline, allowed alternatives, task-local prompt-override scope, and an explicit no-silent-fallback rule.

### When `../STYLE.md` exists
- Read it and follow it as the authoritative art style and pipeline contract for visual, game-art, generated-image, UI-art, code-model, and asset-production work.
- Resolve the current pipeline with `./commands/resolve-art-pipeline.sh`. An explicit current-prompt pipeline selection takes precedence over the primary pipeline, applies only to that task, may select any registered pipeline, and does not rewrite `STYLE.md`.
- Record prompt-override evidence below the active `.ai/tasks/<task>/` folder with `selectionSource: prompt` and the current style-contract hash.

### When `../STYLE.md` is missing
- Ask the user which style templates in `./.styles/` apply to the repository, unless the user already named the desired style.
- Support selecting multiple templates for mixed-style repositories.
- Default the primary art pipeline to `CSS3` unless the user explicitly selects `CLOUD`, `LOCAL`, `CODE`, or `BLENDER`.
- After the user answers, generate `../STYLE.md` with `./commands/generate-style.sh [--pipeline PIPELINE] [--allow-pipeline PIPELINE ...] [--asset-library ID=ABSOLUTE_PATH ...] "<STYLE1>" ["STYLE2" ...]`.
- External asset libraries are optional. Never ask for or probe a library during startup or initial setup unless the user explicitly requests one.
- Default generation must use concise read directives (for example `Read \`./<mount>/.styles/ISOMETRIC_2_5D.md\` instructions`) instead of inlining template text.
- Use `--inline` only when the user explicitly asks for fully embedded template content.
- Validate generated or edited style contracts with `./commands/validate-style-contract.sh`.
- Once generated, use `../STYLE.md` as the authoritative art style contract.

### When regenerating style later
- Ask the user again which style templates apply unless they already named the replacement style set.
- Ask which primary and allowed art pipelines apply unless they already named them; default the primary to `CSS3`.
- Preserve configured external asset libraries during regeneration unless the user explicitly replaces or clears them.
- Regenerate `../STYLE.md` with the same default read-directive mode unless inline output is explicitly requested.
- Validate the regenerated contract with `./commands/validate-style-contract.sh`.

### Pipeline responsibilities

- `CLOUD`: use compatible generation exposed by the active session with explicit budgets, non-runtime staging, provenance, and human review.
- `LOCAL`: use pinned loopback-only ComfyUI image/audio execution on local GPU resources with license and checksum gates.
- `CSS3`: author CSS, mathematical geometry, and inline SVG/vector output only; do not depend on raster generation, canvas, or WebGL.
- `CODE`: author host-native Three.js TypeScript/JavaScript models; do not use downloaded/generated mesh assets or a model library as the primary implementation.
- `BLENDER`: author Blender 4.5 LTS scenes, assets, renders, and runtime exports through immutable working-copy, validation, staging, and human-review controls.

If a selected pipeline is unavailable or fails, stop and request direction. Never switch or fall back to a different pipeline silently.

### Optional external asset libraries

`STYLE.md` may contain named absolute filesystem roots under `## External Asset Libraries`. These are optional source locations for existing 3D models, rigs, animations, and complete asset bundles; they are not art pipelines.

- When no library is configured, continue normally without prompting during startup, installation, scaffold creation, or unrelated work.
- When at least one library is configured and a task needs a 3D asset, run `./commands/list-external-asset-libraries.sh` and inspect relevant libraries before creating, generating, or downloading a replacement.
- Treat every configured library and all content beneath it as strictly read-only. Never edit, rename, delete, generate into, install into, or otherwise write beneath a library root.
- Never load, import, execute, or use an asset directly from an external library. First copy the selected file or complete bundle with `./commands/copy-external-asset.sh` into `<project-root>/assets/models/<library-id>/...`.
- Use only the repository-local copy as-is or as a modifiable template. Record task-local copy evidence when a task exists, and verify asset-level provenance, license, modification rights, format, budgets, selected pipeline, and architecture compatibility.
- Do not follow symbolic links, overwrite an existing project asset, or allow source/destination path overlap. If a configured library is unavailable, stop and request direction instead of silently skipping the required search.
- An external library never relaxes pipeline boundaries: `CSS3` cannot use model assets, and `CODE` may use a copied model only as template/reference evidence rather than its primary runtime mesh.

## Generative media workflow

The optional generative media contract for the host repository is:

- `../MEDIA.md`

Cloud/local media contracts, shared provenance schemas, and pinned local manifests live in:

- `./.styles/.pipelines/cloud/`
- `./.styles/.pipelines/local/`
- `./.styles/.pipelines/_shared/`

### When `../MEDIA.md` exists

- Read it only for image, music, sound-effect, voice, or media-pipeline work.
- Treat it as the execution and provenance authority for `CLOUD` and `LOCAL`: versions, staging, runtime destinations, budgets, rights, consent, review, and promotion policy.
- For image generation, obey both the resolved art pipeline and `MEDIA.md`. Music, sound effects, and voice use `MEDIA.md` without depending on visual style.
- `CSS3`, `CODE`, and `BLENDER` work do not require `MEDIA.md`; Blender work reads it only when cloud/local generated inputs are also in scope.

### When `../MEDIA.md` is missing

- Do not generate it for unrelated tasks.
- When the user configures a media pipeline, discover capabilities separately for image, music, sound effects, and voice.
- For image generation, first resolve `CLOUD` or `LOCAL` through `STYLE.md` or the current prompt.
- Inspect compatible cloud/session and local capabilities per modality. If both paths are viable and the pipeline is not already selected, ask the user to choose before generation.
- Generate the contract with `./commands/generate-media-contract.sh CLOUD [LOCAL]`, then validate it with `./commands/validate-media-contract.sh`.

### Generation and promotion boundaries

- Never switch or fall back between `CLOUD` and `LOCAL` silently. Report a selected-pipeline failure and request direction.
- Keep generated outputs in a non-runtime staging location until human review is recorded.
- Record versioned generation manifests with explicit unavailable markers when a provider does not disclose a model, workflow, parameter, or seed.
- Require input rights and applicable identity or voice consent, hash staged outputs, validate runtime budgets, and record acceptance or rejection reasons.
- Keep promotion separate from generation. Never persist credentials, accept licenses for the user, or promote an unreviewed candidate.

## Role casting

OpenCaw supports **role casting** using role definitions stored in:

- `./.roles/<domain>/<role-name>/ROLE.md`
- current computer science catalog: `./.roles/computer-science/<role-name>/ROLE.md`
- role list index: `./.roles/INDEX.md`

### Activation rule
If the user explicitly defines or requests a role, resolve it across `./.roles/<domain>/` and apply the matching role definition for the session.
Role references may be:
- unqualified role name, for example `backend-architect`
- alias from `./.roles/INDEX.md`, for example `security`
- domain-qualified role id, for example `computer-science/backend-architect`

Resolution behavior:
- If an unqualified role name or alias maps to exactly one role across all domains, activate it directly.
- If an unqualified role name or alias maps to multiple roles across domains, pause and ask the user which domain-qualified role they mean before continuing.
- If both an exact role-name match and alias match exist, prefer exact role-name match.
- If no match exists, continue using normal OpenCaw baseline behavior.
- Prefer deterministic resolution with `./commands/resolve-role.sh` when available.

### Alias support
- Common aliases are listed in `./.roles/INDEX.md`
- If the user provides a known alias, resolve it to the matching role name
- Prefer exact role-name matches when both an alias and an exact role are present
- If alias resolution is ambiguous across domains, ask for a domain-qualified role id before proceeding

### Multi-role composition
Users may request more than one role, for example:

- `use role backend-architect + security-engineer`
- `use roles frontend-developer + qa-engineer`
- `act as sre + backend-architect`

When multiple roles are requested:

1. Resolve each requested name or alias to a role in `./.roles/<domain>/`
2. Load the matching `ROLE.md` files
3. Compose them in the order requested by the user
4. Treat the first role as the primary perspective when rules overlap, unless the user explicitly sets a different priority
5. Treat later roles as additive constraints, review lenses, or specialist guidance
6. If two roles conflict, follow the stricter or safer interpretation unless the user says otherwise

### Behavior
- If a matching role file exists, use that role definition in the session
- If multiple matching role files exist, compose them in request order
- If no matching role exists, continue using the normal OpenCaw baseline behavior
- Role casting is additive to the baseline unless the user explicitly says the role should dominate the session

### Guidance
- Prefer exact role-name matches from `./.roles/INDEX.md`
- If the user names a role ambiguously, ask which available role they want
- Do not invent role files that do not exist unless the user explicitly asks to create one

## Work hierarchy and modes

- OpenCaw's hierarchy is optional Brainstorm discovery, then planning, then exactly one delivery mode: `Brainstorm -> Plan -> Task | Goal | Gauntlet`.
- Brainstorm mode is an optional, explicitly activated pre-planning stage for researched ideas. It is not a delivery mode and creates no task, issue, Goal, Gauntlet, implementation, commit, or PR state.
- Activate Brainstorm only when the user explicitly says `Brainstorm mode`, `start Brainstorm mode`, or `enter Brainstorm mode`; ordinary use of the verb “brainstorm” does not activate persistent mode.
- Once active, Brainstorm persists in repository-root `BRAINSTORM.md` across conversations until the user explicitly turns it off. Never infer exit from inactivity or completeness.
- Explicit exit regenerates repository-root `BRAINSTORM_SUMMARY.md` and waits. Planning begins only when the user explicitly selects an element to turn into a plan.
- Task mode is the default for one specific assignment. It uses one task file and issue, completes after scoped verification, and retains the human PR readiness gate.
- Goal mode is an explicitly requested collection of ordered tasks. It may automatically raise each validated task PR, requires post-PR QA before advancing, and leaves merge approval to humans.
- Gauntlet mode is an explicitly requested adversarial loop for one ambitious deliverable. It uses one parent task and issue, a human-approved quality bar, persistent builder-versus-fresh-critic rounds, progressive work-unit PRs into one Gauntlet integration branch, and a final integration critic before human-gated promotion.
- Activate goal mode only when the user says `goal` or `goal flow`, or an artifact marks `Goal Flow: enabled` or `Flow: goal`.
- Activate Gauntlet mode only when the user says `gauntlet`, `gauntlet mode`, or `gauntlet flow`, or an artifact marks `Gauntlet Mode: enabled` or `Flow: gauntlet`.
- Do not activate goal mode from the generic `## Goal` section in `TASK.md`; that field describes task intent.
- If Brainstorm is active, reject Task, Goal, and Gauntlet creation until explicit exit and an explicit plan request. If Brainstorm and a delivery mode are selected together, pause and ask which stage governs rather than nesting them.
- If goal and Gauntlet are both explicitly selected for the same work, pause and ask which mode governs delivery before mutating project state.

## Plan mode default
- Enter plan mode for any non-trivial task
- Do not enter planning while Brainstorm is active. Complete explicit exit and summary generation first, then require the user to select an element for planning.
- Treat a task as non-trivial when it has 3+ steps, architectural decisions, cross-cutting impact, verification complexity, or ambiguity
- Use plan mode for verification work, not just implementation
- When the user specifies a developer count, agent count, worker count, or explicit parallel execution target, apply the `computer-science/project-manager` planning lens to align tasks into safe parallel lanes before implementation
- Count-based plans should name lane ownership, scope, dependencies, verification, integration order, and any reason the effective parallelism is smaller than the requested count
- Apply the explicit Brainstorm stage and task, goal, or Gauntlet work-mode contract before creating execution artifacts
- Write detailed specs up front to reduce ambiguity
- If something goes sideways, stop and re-plan immediately instead of pushing through a stale plan

## Subagent strategy
- Use the `computer-science/project-manager` planning lens before subagent execution when the user requests multiple agents/developers/workers or when natural parallelism is clear
- Create or update `../.ai/tasks/<task_name>/SUBAGENTS.md` for substantial parallel work using `./commands/create-subagent-plan.sh`, then validate it with `./commands/validate-subagent-plan.sh`
- Brainstorm is the only exception to task-backed `SUBAGENTS.md`: maintain exactly three participants consisting of the main `computer-science/project-manager` and two persistent read-only `computer-science/researcher` subagents; keep their reports ephemeral and let only the project-manager write Brainstorm artifacts.
- If two researcher slots are unavailable, preserve active Brainstorm state and block idea processing. Never use a smaller team or sequential fallback.
- Resolve every lane role with `./commands/resolve-role.sh` before assigning work; do not spawn a lane with unresolved role ambiguity, missing verification, overlapping write scope, or an immediate critical-path dependency
- For Codex, map read-only investigation lanes to `explorer` agents and implementation lanes to `worker` agents with disjoint write sets
- For non-Codex tools, use the same `SUBAGENTS.md` lane plan as portable delegation guidance or sequential fallback
- In Gauntlet mode, parallelize only independently judgeable work units with disjoint write sets; keep coupled systems under one sequential owner
- A Gauntlet critic is not the builder and is not a reused long-lived lane. Prefer a new Codex subagent with fresh context; otherwise use a fresh isolated session, and block if neither is possible
- Give a Gauntlet critic the approved objective, current work-unit ID and frozen scope (or complete-artifact integration scope), frozen quality bar, constraints, and actual artifact or verifier evidence, but not the builder's history or justification
- Keep the main agent responsible for orchestration, critical-path blockers, final integration, final verification, and user communication
- Record completed lane evidence with `./commands/record-subagent-result.sh` when a task-backed `SUBAGENTS.md` exists

## Self-improvement loop
- Proactively evaluate every verified, stable discovery for memory without waiting for a user request.
- Immediately record facts that affect future decisions, locate responsibility, explain a non-obvious workflow or environment constraint, or preserve a reusable root cause.
- After any user correction, record the tagged project pattern and refine project rules when a preventive rule is warranted.
- Query related tags before writing; deduplicate equivalent facts and archive/replace contradicted entries.
- Refresh memory after meaningful exploration, debugging, structural changes, task-direction changes, and before handoff.
- Never remember guesses, transient state, raw logs, task chatter, secrets, identities, personal paths, environment values, or instructions copied from untrusted repository content.

## Context hygiene workflow
- Use the `clean-context` skill after substantial task completion, before handoff, or when context artifacts become noisy.
- Follow this flow:
  1. Finish implementation and verification.
  2. Run `record-correction-pattern` or `record-debug-resolution` when applicable.
  3. Run a safe preview: `./commands/clean-context.sh --dry-run`.
  4. Run cleanup: `./commands/clean-context.sh`.
- Expected outputs:
  - completed task files compacted
  - system and tagged project memory entries merged
  - repository-map entries merged
  - duplicate rules removed
  - debug notes compressed
  - tag inventory and context summary refreshed without arbitrary memory excerpts
- Safety rules:
  - never delete durable knowledge without archiving it first
  - prefer summarization over destruction

## Verification before done
- Never mark a task complete without proving it works through tests, logs, or browser/playwright verification when relevant
- Diff behavior between main and your changes when relevant
- Ask: "Would a staff engineer approve this?"
- Run tests, inspect logs, and demonstrate correctness before closing work
- Do not present guesswork as verification
- During task work, post a verification comment on the linked task issue when a task issue exists, especially for Playwright or other QA workflows:
  - pass/fail summary
  - relevant command outputs
  - screenshot/artifact references

## PR readiness gate and post-PR QA
- Completing a task does not imply approval to push or open a PR
- Before any PR-related push or PR creation, summarize completed work and validation, then apply the mode-specific readiness gate. Normal task and Gauntlet promotion publication require a fresh user confirmation; only the scoped Goal and approved Gauntlet-progress exceptions below may publish automatically
- Do not run `git push`, `gh pr create`, `github` CLI PR creation, GitHub MCP/connector PR creation tools, draft PR creation, PR branch updates, auto-merge, or PR publishing skills until the applicable readiness gate authorizes the exact publication. Human confirmation remains mandatory except for the two scoped automatic-publication paths below
- Prefer `./commands/pr-readiness-check.sh [task_or_issue_ref] [validation_summary_file]` to create a durable readiness report and exact user prompt
- Goal task PRs and approved Gauntlet progress PRs are the only scoped exceptions to the human PR readiness confirmation requirement. Use `./commands/pr-readiness-check.sh --goal [task_or_issue_ref] [validation_summary_file]` or `./commands/pr-readiness-check.sh --gauntlet-progress <gauntlet_ref> <item_id> [validation_summary_file]` to record the applicable automatic-publication boundary
- Gauntlet progress-PR publication becomes automatic only after the user approves the Gauntlet quality bar and delivery contract. Every progress PR targets the recorded Gauntlet integration branch, and every merge remains human-controlled
- Use case-sensitive `Refs #<issue-number>` as the exact first body line for Gauntlet progress and remediation PRs; reserve every closing-keyword alias for the human-gated promotion PR, whose exact first line is `Closes #<issue-number>` and whose target must be the current GitHub default branch
- `pr-readiness-check.sh --gauntlet-progress` creates an immutable publication checkpoint under `publication-checkpoints/<item-id>/`, including the exact quality-bar fingerprint plus `Quality bar approved at` value and unit-manifest fingerprint plus `Unit manifest approved at` value active at issuance. Gauntlet GitHub evidence accepts only authenticated SSH or HTTPS `github.com` remotes, rejects plaintext HTTP, and pins live API queries to `github.com` rather than ambient `GH_HOST`. Put its exact `<!-- opencaw-gauntlet-publication:v1 checkpoint=<path> checkpoint-sha256=<sha> -->` marker after the required issue-reference first line; the opened-event recorder must query that body, verify the checkpoint still matches the live contract, refs, remote observations, and remediation cause, and consume it exactly once
- That scoped publication approval does not authorize force-pushing shared branches, deleting branches, changing the delivery base, approving reviews, merging, or enabling auto-merge
- Use `./commands/pr-readiness-check.sh --gauntlet <gauntlet_ref> [validation_summary_file]` only after all active progress PRs are QA-passed and human-merged and the integration review passes. Verify the integration branch still matches the emitted reviewed source SHA; explicit human confirmation remains required before the promotion PR to the delivery base
- Goal flow may automatically push/open a PR for the completed task, but it must still run post-PR QA before moving to the next goal task
- Goal flow never auto-merges PRs, enables auto-merge, or grants merge approval; it only auto-raises PRs and runs/reports post-PR QA
- Goal flow does not suppress validation, PR evidence, issue linkage, or post-PR QA
- For GitHub PR operations and metadata lookups, choose tools in this order:
  1. `gh` from the local shell
  2. an available `github` CLI executable or repository-provided GitHub CLI wrapper
  3. GitHub MCP/app connector tools only when both CLI options are unavailable or unsuitable
- After the applicable readiness gate authorizes publication and the PR number or URL is confirmed available, start QA immediately without waiting for another prompt
- Post each QA pass/fail verdict to the PR as a new GitHub comment; when screenshots are part of the evidence, include inline screenshot URLs in the comment. Gauntlet comments carry `<!-- opencaw-gauntlet-qa:v1 verdict=<pass|fail> head-sha=<sha> source=<canonical-evidence-path> source-sha256=<sha> affected-units=<none|comma-sorted-ids> -->`; recorders must query the exact same-PR comment and reject missing, edited, wrong-author, wrong-PR, semantically stale, or reused evidence
- Prefer `./commands/comment-pr-qa-results.sh "<pr_number_or_url>" "<results_summary_file>" [screenshot_or_artifact ...]` for non-Gauntlet PR QA comments. For a Gauntlet PR, use `./commands/comment-pr-qa-results.sh "<pr_number_or_url>" "<results_summary_file>" --gauntlet-verdict "<pass|fail>" --head-sha "<sha>" --gauntlet-source "<project-relative-evidence>" [--gauntlet-affected-units "<none|comma-sorted-ids>"] [screenshot_or_artifact ...]`; the bare form does not emit the semantic marker required by Gauntlet recorders
- Mirror or link QA evidence to the task issue when a task issue exists, but the PR comment is the primary post-PR signal
- If QA fails on an open Gauntlet progress PR, keep that unit PR as the evidence surface, record the failure comment, rebuild with a changed builder strategy, and use a new critic invocation against the new PR-head SHA before repeating QA
- If integration QA fails after a unit PR has merged, reopen affected units from the recorded integration failure. If promotion-PR QA fails, first record the exact promotion PR, reviewed source SHA, same-PR QA comment, and affected units with `record-gauntlet-promotion-qa.sh`; only that immutable failure event may reopen a passed Gauntlet. Create remediation PRs into the same integration branch, update the promotion PR through that branch, and repeat integration and promotion QA
- Once QA is complete, notify the user that the PR is ready for review and that you can move to the next task if any remain

## Demand elegance (balanced)
- For non-trivial changes, pause and ask whether there is a more elegant solution
- If a fix feels hacky, re-evaluate and implement the elegant solution using everything learned so far
- Skip over-engineering for simple, obvious fixes
- Challenge your own work before presenting it

## Autonomous bug fixing
- When given a bug report, move directly into diagnosis and resolution
- Point at logs, errors, failing tests, or concrete evidence, then resolve the issue
- Minimize user context switching
- Review `../.ai/DEBUG.md` for previous solutions before finding new ones
- Write reusable bug resolutions to `../.ai/DEBUG.md`

## Task management
0. Do not run task management while Brainstorm mode is active. Brainstorm elements can become plans only after explicit exit; a later delivery-mode request may then create task state.
1. Plan first: update `../.ai/tasks/TODO.md` as the active numbered checklist of pending and completed tasks in execution order
2. For each real task, create `../.ai/tasks/<unique_task_name>/TASK.md` with the actual instructions, assumptions, notes, and review details
3. Create or link a matching GitHub issue for each real task and record only the issue URL in `../.ai/tasks/OPEN_ISSUES.md`
4. Verify plan: check in before starting implementation when the task is non-trivial or changes direction materially
5. Track progress: mark `../.ai/tasks/TODO.md` items complete as you go
6. Keep `../.ai/tasks/TODO.md` concise: it should be the ordered checklist, not the full work log
7. Store detailed implementation notes, task-specific instructions, and review results in the matching `../.ai/tasks/<unique_task_name>/TASK.md`
8. Sync task issues when reading active tasks and remove URLs for closed issues from `.ai/tasks` tracking
9. Capture lessons proactively with `append-project-memory.sh --tags ... --entry ...` after corrections and durable discoveries
10. Before final handoff for substantial work, run `clean-context` to compress completed context and refresh high-signal summaries
11. A Gauntlet has one parent task file and issue. Its internal work units, progress and promotion-QA ledgers, PR-event evidence, and immutable critic rounds live under `.ai/gauntlets/<gauntlet_name>/`; do not create separate task issues for those units unless they become independently deliverable work

## Brainstorm flow

- Brainstorm is for app, game, product, feature, and other research-heavy idea discovery before planning.
- Use `./commands/brainstorm-mode.sh start|stop|status`, `./commands/validate-brainstorm.sh`, and `./commands/show-brainstorm.sh [--markdown]` against the safely resolved project root.
- Persist mode/session state, stable `BR-NNN` branch definitions, and stable `IDEA-NNN` elements only in repository-root `BRAINSTORM.md`. Never reuse or renumber retained IDs.
- For each materially distinct user idea, clarify to baseline understanding, place it in the deepest fitting branch or create a new branch, then run two complementary researcher lanes: problem/audience/precedent and feasibility/constraints/completeness.
- Require public/current factual claims to carry source URLs and distinguish evidence, inference, disagreement, and uncertainty. Only the project-manager synthesizes and writes the result.
- Every element records title, branch, status, original idea, base understanding, research findings/citations, dependencies, risks, open questions, start conditions, definition of complete, and plan readiness.
- Use only `captured`, `clarifying`, `researching`, `plan-ready`, and `parked`. Incomplete elements remain valid and must survive exit; only complete, cited elements may be `plan-ready`.
- When the user asks to see the Brainstorm, show the Mermaid mindmap produced by `show-brainstorm.sh`. If the user explicitly requests Markdown, return the complete `BRAINSTORM.md` verbatim.
- On explicit exit, atomically deactivate the live state and regenerate `BRAINSTORM_SUMMARY.md` with one linkable summary per element grouped by branch path and bound to the final source SHA-256.
- Do not automatically plan on exit. Wait for an explicit element selection, then use that element as planning input without directly creating Task, Goal, or Gauntlet state.
- Creation commands for tasks, task issues/imports, Goals, and Gauntlets must fail closed when Brainstorm is active, malformed, or inactive without a current exit summary. Absent state or valid inactive state with a current summary preserves existing behavior.

## Goal flow
- A goal is an explicitly requested automated multi-task delivery flow, not the generic `## Goal` field in a task file
- Never start or create Goal flow while Brainstorm mode is active.
- Goal files live under `../.ai/goals/<goal_name>/GOAL.md`; create them with `./commands/create-goal-file.sh "<goal_name>" ["Goal Title"]`
- In normal task flow, tasks proceed one by one unless the project-manager role defines safe parallel sub-agent lanes
- In goal flow, tasks still proceed through planning, implementation, validation, PR creation, and post-PR QA, but the PR readiness human confirmation prompt is skipped
- After each completed goal task, automatically raise the PR, confirm it is available, run post-PR QA, post QA evidence to the PR, then move to the next goal task
- If a future goal task depends on a previous task or risks merge conflicts later, base that task on the previous task branch or PR head and record the dependency in the goal branch chain
- When all goal tasks complete, generate a goal completion report with PR links in approval order, branch dependencies, QA evidence, and conflict-risk notes before asking for human approval
- Do not continue to the next goal task if local validation fails, PR creation fails, post-PR QA fails, role resolution is ambiguous, a merge conflict blocks the PR path, or a required human/product/security decision was not already covered by the goal plan
- Goal flow never grants automatic merge approval; merging remains governed by repository policy

## Gauntlet flow

- A Gauntlet is an explicitly requested adversarial quality loop, not a synonym for a task or goal queue
- Never start or create Gauntlet flow while Brainstorm mode is active.
- Gauntlet state lives under `../.ai/gauntlets/<gauntlet_name>/GAUNTLET.md`; create it with `./commands/create-gauntlet-file.sh "<gauntlet_name>" ["Title"] --task "<task_name>"`
- Before building, define an inspectable objective, artifact, constraints, concrete quality bar, delivery base branch plus exact base commit SHA, and `gauntlet/<gauntlet_name>` integration branch created exactly at that commit. Obtain human approval; the first accepted progress-PR event freezes the parent task, objective, constraints/permissions, base identity, static delivery policy, approved quality bar, and normalized unit manifest into separate execution-contract, quality, and unit-manifest fingerprints
- Changing an approved bar requires new human approval and invalidates affected prior pass evidence; preserve prior rounds, record the revision in Unit History, reopen active units, clear integration evidence, reset the current fingerprint to `pending`, and reset PR eligibility to `no`
- Let the lead agent decompose the deliverable into stable, independently judgeable units with a durable title and inspectable frozen scope. The normalized manifest contains sorted retained ID/title/scope definitions plus sorted supersession ID/scope/replacement edges, excluding transient checkbox/status state. Approve it with `- Unit manifest approval: <fingerprint> | units: <comma-sorted-ids> | approved by: <identity> | approved at: <canonical-UTC>`. Later additions, definition changes, or edge changes require `- Unit manifest revision: <revision-id> | from: <fingerprint> | to: <fingerprint> | prior-units: <comma-sorted-ids> | current-units: <comma-sorted-ids> | reason: <substantive reason> | approved by: <identity> | approved at: <canonical-UTC>`; a changed title or scope also requires a matching `- Unit scope-title revision: <item-id> | from: <scope-fingerprint> | to: <scope-fingerprint> | reason: <substantive reason> | approved by: <identity> | approved at: <canonical-UTC>`. Every per-unit checkpoint, PR event, and round must name a unit present in—and use the title/scope definition committed by—the manifest generation active at that evidence timestamp. Never delete or rename a retained definition
- Preserve split, merge, scope revision, supersession, failure, and strategy history. A superseded unit requires exactly one canonical Unit History marker: `- Unit supersession: <item-id> | scope: <scope-fingerprint> | replacements: <comma-sorted-active-item-ids> | reason: <substantive reason> | approved by: <identity> | approved at: <canonical-UTC>`. The supersession graph must be acyclic, every path must end at an active leaf, and every active descendant inherits each outstanding failure obligation of its superseded ancestors. Every edge on an inherited-failure path must be approved no later than the replacement cycle's publication checkpoint, which itself must precede the live PR creation time; a later manifest approval cannot retroactively authorize earlier replacement work or evidence
- Create the integration branch exactly at the recorded base commit and keep it as the only target for work-unit progress PRs. Use `gauntlet-work/<gauntlet_name>/<item_id>[-remediation-N]` for unit branches; Git cannot store a child ref beneath the existing `gauntlet/<gauntlet_name>` integration ref. Do not write directly to the integration branch: its history must remain one continuous recorded `baseRefOid` to `mergeCommit` chain
- After a builder changes and objectively verifies a work unit, run `pr-readiness-check.sh --gauntlet-progress`. It fetches the recorded origin, verifies every effective push URL belongs to the issue repository, checks local and remote integration/work refs without force or overwrite, and writes an immutable publication checkpoint. The checkpoint's manifest and quality generations, including every relied-on supersession edge, must already be approved and active at its recorded issuance time. Automatically publish only the exact emitted branch/commit into the emitted integration target and include the emitted checkpoint marker in the PR body
- Record the PR's `opened` event with the full head SHA. The recorder queries live GitHub repository identity, same-repository status, body marker, base/head branches and OIDs, state, draft flag, and creation time; it requires the work head to descend from the checkpoint's exact integration-chain tip, rejects drift, and consumes the current checkpoint exactly once. All later rounds for that unit stay on the same open PR until it is human-merged or closed, and each later head must be a fast-forward descendant of that PR's prior recorded head
- For every round, record the builder's actual changed strategy, then give a separate fresh-context critic the exact PR-head SHA, frozen unit scope, frozen bar, and guardrails. Builder and critic identity sets are globally disjoint for the entire Gauntlet, and every critic invocation ID is unique. The critic report must identify that SHA and project-relative artifacts present as regular files in that exact commit. Bind each round to its opened-event path/hash and resolved remediation-root path/hash. Post each verdict with the canonical QA marker; recorders re-query GitHub, the exact immutable comment, and local Git refs before accepting evidence
- Record critic reports under `rounds/<item_id>/round-NNN.md`, PR events under `pr-events/<item_id>/event-NNN.md`, and promotion QA under `promotion-events/event-NNN.md`; preserve their canonical one-to-one hash ledgers in `GAUNTLET.md`. When PR events share a second-resolution timestamp, their Progress PR Ledger append order is authoritative; equal-time evidence from different ledgers requires an explicit immutable causal edge and never receives an invented path or evidence-type order
- A failing unit returns to its builder on the same progress PR with the largest gap and must use a changed actual builder strategy; persist that strategy with the next round, omit builder history and prior PR comments from the critic packet, and use a new critic invocation. Do not start a new round until the prior round has a recorded QA failure
- A unit counts as integrated only when its latest critic round and QA event pass for the same current unit scope, unit-manifest, quality, and execution-contract fingerprints and unchanged PR-head SHA; live GitHub reports that exact same-repository reviewed head merged by an actor with `is_bot=false`; its created/closed/merged times, `baseRefOid`, actor, and `mergeCommit` are recorded; and the event extends the continuous integration chain. Record each human merge promptly and in integration order. Terminal validation re-queries every topology and causal-replacement PR instead of trusting local event text. Reject a progress or promotion PR if its retained GitHub timeline ever contains auto-merge, auto-rebase, auto-squash, or merge-queue enablement, even when later disabled. Gauntlet automation never approves or merges
- Independent, disjoint unit PRs may proceed in parallel. Coupled or dependent work must wait for the prerequisite PR to merge and then branch from the updated integration branch
- After every active unit is integrated, prove the exact local and remote integration heads equal the gapless recorded merge-chain tip, descend from the frozen base, and contain every active unit's latest merge. Then use a new integration critic on that exact SHA and aggregate scope. Its fail/block evidence records the exact then-active affected unit set. A rewind, divergence, unrecorded direct commit, fork, or origin mismatch blocks integration/completion. Each unit-local critic/QA failure, integration failure, or promotion failure remains an externally anchored causal root until a later PR cycle consumes it; an active supersession descendant inherits every outstanding ancestor root. The checkpoint, opened event, round, QA marker, and merge must remain hash-linked to the exact root
- Limit each autonomous Gauntlet execution window to 45 minutes or two failed full-validation epochs, whichever occurs first. A full-validation epoch is one frozen candidate evaluated against the approved verification suite; targeted diagnosis does not reset or increase the budget. At exhaustion, do not begin another build, audit, or validation epoch: record elapsed time and failed-epoch count in Review Notes, persist resumable state, generate a stopped report, set status to `stopped`, and request explicit user reauthorization. Reauthorization starts a new window. Safety, permission, platform-policy, and unrecoverable blockers still stop immediately; this does not authorize unapproved spending or external actions
- A Gauntlet passes only when every active unit's latest critic verdict and QA event pass, every active progress PR is human-merged, and the integration verdict passes; stopped and blocked reports remain incomplete and promotion-ineligible
- Generate `GAUNTLET_REPORT.md` with ordered progress PRs, reviewed head SHAs, QA comments, merge topology, frozen base, unit-manifest/scope/quality/execution fingerprints, integration evidence, and conflict notes. Complete status also creates an immutable completion event and ledger entry binding a canonical hash projection of the whole report except its self-referential immutable-evidence section. Every older completion must be consumed exactly once by a later promotion failure; at most the newest may remain active. An active unconsumed completion forces passed/report/source invariants. Then verify the frozen delivery base is still GitHub's default branch and use the normal human readiness gate for the promotion PR from the integration branch
- The promotion PR is the roll-up integration boundary, not the first review surface. Record each QA verdict with a new live same-PR semantic comment and `record-gauntlet-promotion-qa.sh`; one later failure may supersede a prior pass for the same completion, PR, and head, but another pass cannot follow that failure without a new head and completion. A failure archives the stale report, explicitly consumes the active completion event, and immutably names affected units plus the reviewed SHA. It is the only event allowed to reopen a completed Gauntlet. Direct state edits, rounds, progress events, stopped/blocked reports, or stale pre-failure merges cannot bypass it. Then add causally linked remediation PRs, rerun integration criticism, create a new completion event, let the promotion PR update, and repeat QA. Historical promotion-QA snapshots remain anchored by immutable comments and ancestor head SHAs, while the current live promotion PR must stay open, non-draft, and unmerged with its source head and the remote integration ref exactly equal to the reconstructed local merge-chain tip
- Gauntlet mutation commands serialize through a portable per-Gauntlet lock, compare-and-swap the contract, and install round and event files without clobbering. Treat an existing lock as an active or stale-state blocker; never remove it without confirming no recorder is running

## Issue-first task import
- If the user prompt includes an issue reference (for example `Work on #123`), import that issue into task tracking first with `./commands/import-task-from-issue.sh "#123"`.
- Accept issue references as `#123`, `123`, or a full GitHub issue URL.
- Reuse the existing task file when the issue is already linked.
- Keep imported issue URLs in `../.ai/tasks/OPEN_ISSUES.md` only while the issue state is open.

## Task file rules
- `../.ai/tasks/TODO.md` is the active ordered checklist only
- Items should be numbered and ordered by execution sequence
- Checked items are complete; unchecked items are pending
- Each TODO entry should reference its matching task folder when applicable
- `../.ai/tasks/<unique_task_name>/TASK.md` contains the actual work instructions for that task
- `../.ai/tasks/OPEN_ISSUES.md` stores only open GitHub issue URLs (one per line)
- Each task should include a linked issue URL while open (for example in `## Issue`)
- Prefer one task folder per substantial task
- Keep task names stable, concise, and filesystem-safe

## Core principles
- Simplicity first: make every change as simple as possible and minimize code impact
- No laziness: find root causes, avoid temporary fixes, and hold changes to senior-engineer quality
- Prefer small, reviewable changes
- Preserve existing solution and project structure unless change is required
- Avoid introducing new dependencies unless necessary
- Prefer explicit null handling and defensive guards at integration boundaries
- Prefer keeping configuration externalized
- Prefer deterministic, testable logic over hidden state or side effects

## Division .NET conventions
- Prefer repository scripts in `./commands/`
- Restore before build when needed
- Build before concluding implementation is complete
- Prefer targeted tests before broad test runs when the request is narrow

## Cloud and CI conventions
- Prefer `GitHub` for source control and collaboration defaults
- Prefer `GitHub Actions` for CI/CD workflow defaults
- Prefer cloud environment targets in this order unless the user explicitly overrides:
  1. `GCP`
  2. `Azure`
  3. `AWS`
- When providing cloud recommendations, migrations, or deployment plans, explain any deviation from this order

## Azure conventions
- Prefer environment-driven configuration
- Avoid hardcoding subscription, tenant, storage account, service bus, or resource names
- Prefer least-privilege assumptions
- When modifying Azure-related code, call out:
  - required app settings
  - identity / RBAC assumptions
  - deployment impact
  - rollback impact
- Prefer scripts or docs that make local vs cloud behavior explicit

## Branch and PR conventions
- Do not commit unless explicitly asked
- Do not push or open a pull request until the applicable PR readiness gate authorizes it; normal task and Gauntlet promotion PRs require explicit user confirmation
- The scoped automatic-publication exceptions are explicit goal-task PRs after `pr-readiness-check.sh --goal` and approved Gauntlet progress PRs after `pr-readiness-check.sh --gauntlet-progress`; both leave every merge to humans
- Gauntlet promotion from its integration branch to the delivery base retains the normal human readiness confirmation after complete Gauntlet validation
- Any PR created for task-backed work must be associated with its issue. Use `Closes #<issue-number>` for a delivery-completing task, Goal-task, or Gauntlet-promotion PR; use a non-closing `Refs #<issue-number>` reference for Gauntlet progress and remediation PRs
- When asked to commit, prefer conventional commits:
  - feat(scope): summary
  - fix(scope): summary
  - refactor(scope): summary
  - docs(scope): summary
  - test(scope): summary
  - chore(scope): summary
- Keep branch names concise and structured:
  - `feature/<area>-<short-name>`
  - `bugfix/<area>-<short-name>`
  - `chore/<area>-<short-name>`
  - `spike/<area>-<short-name>`
  - `gauntlet/<gauntlet-name>` for an approved Gauntlet integration branch
  - `gauntlet-work/<gauntlet-name>/<item-id>[-remediation-N]` for work-unit and remediation PR branches
- When asked to prepare a PR, produce:
  - Summary
  - What changed
  - Risks
  - Validation
  - Deployment / rollback notes if relevant

## Memory v2 policy

### Precedence and scope
- `.ai/SYSTEM_MEMORY.md` is flat, always loaded, and limited to protected safety constraints, verified non-sensitive machine capabilities, and repository-wide system-memory facts.
- `MEMORY.md` is the canonical project-learning store and is loaded selectively by exact tags.
- `REPO_MAP.md` is the canonical semantic project index and uses the same tag syntax.
- `RULES.md` remains the project-specific instruction layer; `DEBUG.md` remains detailed debugging evidence.
- Temporary notes remain in the matching task file.
- Never store OpenCaw memory or context artifacts in a user-home, machine-global, or workspace-parent directory; keep them under the resolved repository's `.ai` directory.

### Tagged entry schema
Use one-line bullets such as:

```text
- [kind:workflow] [area:auth] [tech:dotnet] Run the focused authentication tests before the full suite.
```

Rules:
- require exactly one `kind:` tag
- use `architecture`, `convention`, `workflow`, `gotcha`, `bug`, `decision`, `dependency`, `environment`, or `tooling` for project-memory kinds; repository maps may also use `component`, `entrypoint`, `config`, `test`, and `command`
- require at least one relevance tag from `area:`, `tech:`, `env:`, `topic:`, or `scope:core`
- use lowercase kebab-case values
- reserve `scope:core` for the few entries relevant to every task
- use `./commands/append-project-memory.sh`; untagged writes are invalid
- use `./commands/purge-project-memory.sh --tag ... --dry-run` before an exact-tag purge; actual purges archive first

### Proactive promotion criteria
Promote a fact immediately when it is verified, stable across sessions, likely to affect future work, and costly or error-prone to rediscover. Prefer concise facts with repository-relative source paths when useful. If later evidence conflicts, archive and replace the old fact rather than appending both.

System memory may be updated autonomously only for verified cross-project constraints or safe machine capabilities such as operating-system, shell, and toolchain behavior. Project facts never belong there.

## Skill authoring guidance
When adding a new skill:
1. Create `skills/<skill-name>/SKILL.md`
2. Reuse an existing script in `commands/` if possible
3. Add a new script only when necessary
4. Keep the skill focused on a single repeatable job
5. If the skill writes memory, it must write only to the host repo under `../.ai/`

## Role-based skill and command binding

After a role is activated, bias behavior using the mappings defined in:

- `./.roles/ROLE_SKILL_MAP.md`
- `./.roles/ROLE_SKILL_MAP.json`

### Rules
- Automatically prioritize skills associated with the active role
- Prefer commands mapped to the active role when relevant
- Apply shared skills and commands for all roles
- Bias reasoning toward that role's domain expertise
- Resolve mappings by trying `<domain>/<role>` first, then fallback to `<role>` for backward compatibility
- When multiple roles are active, merge the mapped skills and commands in the same order as the active role composition
- Use the first role as the primary bias when there is overlap, unless the user sets a different priority
- Use stricter or safer guidance when role-specific skill choices conflict

## OpenCaw schema validation

OpenCaw includes schema validation commands for roles, skills, and commands:

- `./commands/validate-roles.sh`
- `./commands/validate-skills.sh`
- `./commands/validate-commands.sh`
- `./commands/validate-styles.sh`
- `./commands/validate-media-templates.sh`
- `./commands/validate-opencaw.sh`

Use these when:
- adding or editing role files
- adding or editing skills
- adding or editing commands
- reviewing changes to the OpenCaw baseline

Prefer running full validation before finalizing structural changes to OpenCaw.

## Host repository assumption
Resolve the active project root in this order: explicit `OPENCAW_PROJECT_ROOT`, a Git root associated with the host, or the parent of a recognized `.codex`, `.cursor`, or `.claude` mount. A standalone OpenCaw checkout resolves to its own Git root. Fail closed when the boundary is ambiguous.
