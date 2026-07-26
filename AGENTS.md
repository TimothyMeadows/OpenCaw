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

Resolve these paths with `./commands/resolve-opencaw-paths.sh`. Never infer a broad workspace parent when resolution fails.

Never write project-specific learned state into this mounted baseline unless the user explicitly asks to modify the shared baseline.

## Session startup review
At session start, follow this memory-first sequence:

1. Resolve the project root and repository-local `.ai` paths with `./commands/resolve-opencaw-paths.sh`.
2. Run `./commands/create-host-ai-scaffold.sh` automatically when required files are missing. The command is idempotent and reports legacy-memory migration needs.
3. Load all of `SYSTEM_MEMORY.md`. It has precedence over project memory and rules, but never over actual system, developer, or current user instructions.
4. Review project `RULES.md`, `ARCHITECTURE.md`, `STYLE.md`, active task tracking, and open issues when present. Read `DEBUG.md` only for debugging work.
5. Run `./commands/query-project-context.sh --list-tags`, infer relevant tags from the request and active task, then query those tags with the default ranked limit before raw file searches.
6. Run `./commands/repo-map-status.sh`. If the map is missing, empty, or stale, use `maintain-repository-map` before relying on it.
7. If legacy memory is reported, prepare and complete the AI-classified migration before loading untagged entries. Never load legacy memory as a fallback.

You should send a message to the user that you are an OpenCaw session and ready for usage.

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

## Art style workflow
The canonical art style contract for the host repository is:

- `../STYLE.md`

Style templates live in:

- `./.styles/`

### When `../STYLE.md` exists
- Read it and follow it as the authoritative art style contract for visual, game-art, generated-image, UI-art, and asset-production work.

### When `../STYLE.md` is missing
- Ask the user which style templates in `./.styles/` apply to the repository, unless the user already named the desired style.
- Support selecting multiple templates for mixed-style repositories.
- After the user answers, generate `../STYLE.md` with `./commands/generate-style.sh "<STYLE1>" ["STYLE2" ...]`.
- Default generation must use concise read directives (for example `Read \`./<mount>/.styles/ISOMETRIC_2_5D.md\` instructions`) instead of inlining template text.
- Use `--inline` only when the user explicitly asks for fully embedded template content.
- Validate generated or edited style contracts with `./commands/validate-style-contract.sh`.
- Once generated, use `../STYLE.md` as the authoritative art style contract.

### When regenerating style later
- Ask the user again which style templates apply unless they already named the replacement style set.
- Regenerate `../STYLE.md` with the same default read-directive mode unless inline output is explicitly requested.
- Validate the regenerated contract with `./commands/validate-style-contract.sh`.

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

## Plan mode default
- Enter plan mode for any non-trivial task
- Treat a task as non-trivial when it has 3+ steps, architectural decisions, cross-cutting impact, verification complexity, or ambiguity
- Use plan mode for verification work, not just implementation
- When the user specifies a developer count, agent count, worker count, or explicit parallel execution target, apply the `computer-science/project-manager` planning lens to align tasks into safe parallel lanes before implementation
- Count-based plans should name lane ownership, scope, dependencies, verification, integration order, and any reason the effective parallelism is smaller than the requested count
- When the user explicitly requests a `goal`, says `goal flow`, or a task planning artifact marks `Goal Flow: enabled` or `Flow: goal`, use goal flow instead of normal task flow
- Do not activate goal flow from the generic `## Goal` section in `TASK.md`; that field describes task intent and is not the automated goal feature
- Write detailed specs up front to reduce ambiguity
- If something goes sideways, stop and re-plan immediately instead of pushing through a stale plan

## Subagent strategy
- Use the `computer-science/project-manager` planning lens before subagent execution when the user requests multiple agents/developers/workers or when natural parallelism is clear
- Create or update `../.ai/tasks/<task_name>/SUBAGENTS.md` for substantial parallel work using `./commands/create-subagent-plan.sh`, then validate it with `./commands/validate-subagent-plan.sh`
- Resolve every lane role with `./commands/resolve-role.sh` before assigning work; do not spawn a lane with unresolved role ambiguity, missing verification, overlapping write scope, or an immediate critical-path dependency
- For Codex, map read-only investigation lanes to `explorer` agents and implementation lanes to `worker` agents with disjoint write sets
- For non-Codex tools, use the same `SUBAGENTS.md` lane plan as portable delegation guidance or sequential fallback
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
- Before any PR-related push or PR creation, summarize completed work and validation, then ask the user whether they are ready for a PR
- Do not run `git push`, `gh pr create`, `github` CLI PR creation, GitHub MCP/connector PR creation tools, draft PR creation, PR branch updates, auto-merge, or PR publishing skills until the user explicitly confirms readiness after the implementation is complete
- Prefer `./commands/pr-readiness-check.sh [task_or_issue_ref] [validation_summary_file]` to create a durable readiness report and exact user prompt
- Goal flow is the only exception to the human PR readiness confirmation requirement; use `./commands/pr-readiness-check.sh --goal [task_or_issue_ref] [validation_summary_file]` to record the exception before automatic PR creation
- Goal flow may automatically push/open a PR for the completed task, but it must still run post-PR QA before moving to the next goal task
- Goal flow never auto-merges PRs, enables auto-merge, or grants merge approval; it only auto-raises PRs and runs/reports post-PR QA
- Goal flow does not suppress validation, PR evidence, issue linkage, or post-PR QA
- For GitHub PR operations and metadata lookups, choose tools in this order:
  1. `gh` from the local shell
  2. an available `github` CLI executable or repository-provided GitHub CLI wrapper
  3. GitHub MCP/app connector tools only when both CLI options are unavailable or unsuitable
- After the user approves and the PR number or URL is confirmed available, start QA immediately without waiting for another prompt
- Post QA pass/fail evidence to the PR using GitHub comments; when screenshots are part of the evidence, include inline screenshot URLs in the comment
- Prefer `./commands/comment-pr-qa-results.sh "<pr_number_or_url>" "<results_summary_file>" [screenshot_or_artifact ...]` for the PR QA comment
- Mirror or link QA evidence to the task issue when a task issue exists, but the PR comment is the primary post-PR signal
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

## Goal flow
- A goal is an explicitly requested automated multi-task delivery flow, not the generic `## Goal` field in a task file
- Goal files live under `../.ai/goals/<goal_name>/GOAL.md`; create them with `./commands/create-goal-file.sh "<goal_name>" ["Goal Title"]`
- In normal task flow, tasks proceed one by one unless the project-manager role defines safe parallel sub-agent lanes
- In goal flow, tasks still proceed through planning, implementation, validation, PR creation, and post-PR QA, but the PR readiness human confirmation prompt is skipped
- After each completed goal task, automatically raise the PR, confirm it is available, run post-PR QA, post QA evidence to the PR, then move to the next goal task
- If a future goal task depends on a previous task or risks merge conflicts later, base that task on the previous task branch or PR head and record the dependency in the goal branch chain
- When all goal tasks complete, generate a goal completion report with PR links in approval order, branch dependencies, QA evidence, and conflict-risk notes before asking for human approval
- Do not continue to the next goal task if local validation fails, PR creation fails, post-PR QA fails, role resolution is ambiguous, a merge conflict blocks the PR path, or a required human/product/security decision was not already covered by the goal plan
- Goal flow never grants automatic merge approval; merging remains governed by repository policy

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
- Do not push or open a pull request until the PR readiness gate has been presented and the user explicitly confirms they are ready
- The only exception is explicit goal flow, where PR creation is automatic between goal tasks after `./commands/pr-readiness-check.sh --goal` records validation and before post-PR QA runs; merging remains human-approved after the goal completion report
- Any PR created for task-backed work must be associated with its issue (for example `Closes #<issue-number>` in PR body)
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
- `./commands/validate-opencaw.sh`

Use these when:
- adding or editing role files
- adding or editing skills
- adding or editing commands
- reviewing changes to the OpenCaw baseline

Prefer running full validation before finalizing structural changes to OpenCaw.

## Host repository assumption
Resolve the active project root in this order: explicit `OPENCAW_PROJECT_ROOT`, a Git root associated with the host, or the parent of a recognized `.codex`, `.cursor`, or `.claude` mount. A standalone OpenCaw checkout resolves to its own Git root. Fail closed when the boundary is ambiguous.
