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

Project-local knowledge belongs in the host repository:
- durable memory: `../.ai/MEMORY.md`
- rules: `../.ai/RULES.md`
- debug history: `../.ai/DEBUG.md`
- fragments: `../.ai/FRAGMENTS/`
- learnings: `../.ai/LEARNINGS/`
- task notes: `../.ai/tasks/`

Never write project-specific learned state into this mounted baseline unless the user explicitly asks to modify the shared baseline.

## Session startup review
At session start, ensure the host scaffold exists before loading host-repository memory.

First-run host scaffold behavior:
- If any of these files are missing, treat it as first-run and run `./commands/create-host-ai-scaffold.sh` automatically without waiting for user input:
  - `../AGENTS.md`
  - `../.ai/MEMORY.md`
  - `../.ai/RULES.md`
  - `../.ai/DEBUG.md`
  - `../.ai/tasks/TODO.md`
  - `../.ai/tasks/OPEN_ISSUES.md`
- This scaffold step is idempotent and safe to run multiple times.

After scaffold checks, review these host-repository files when they exist:
- `../.ai/MEMORY.md`
- `../.ai/RULES.md`
- `../.ai/DEBUG.md`
- `../ARCHITECTURE.md`
- `../.ai/tasks/TODO.md`
- `../.ai/tasks/OPEN_ISSUES.md`

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
- Write detailed specs up front to reduce ambiguity
- If something goes sideways, stop and re-plan immediately instead of pushing through a stale plan

## Subagent strategy
- Use subagents liberally to keep the main context window clean
- Offload research, exploration, parallel analysis, and focused investigations to subagents
- For complex problems, throw more compute at the problem via subagents
- Use one task per subagent for focused execution

## Self-improvement loop
- After any user correction, update `../.ai/MEMORY.md` with the learned pattern
- Write or refine preventive rules in `../.ai/RULES.md`
- Ruthlessly iterate on lessons and rules until the same mistake rate drops
- Prefer concise, normalized entries over verbose logs

## Context hygiene workflow
- Use the `clean-context` skill after substantial task completion, before handoff, or when context artifacts become noisy.
- Follow this flow:
  1. Finish implementation and verification.
  2. Run `record-correction-pattern` or `record-debug-resolution` when applicable.
  3. Run a safe preview: `./commands/clean-context.sh --dry-run`.
  4. Run cleanup: `./commands/clean-context.sh`.
- Expected outputs:
  - completed task files compacted
  - memory entries merged
  - duplicate rules removed
  - debug notes compressed
  - recommended context summary refreshed
- Safety rules:
  - never delete durable knowledge without archiving it first
  - prefer summarization over destruction

## Verification before done
- Never mark a task complete without proving it works through tests, logs, or browser/playwright verification when relevant
- Diff behavior between main and your changes when relevant
- Ask: "Would a staff engineer approve this?"
- Run tests, inspect logs, and demonstrate correctness before closing work
- Do not present guesswork as verification
- For QA workflows (especially Playwright), post a verification comment on the linked task issue with:
  - pass/fail summary
  - relevant command outputs
  - screenshot/artifact references

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
9. Capture lessons: update `../.ai/MEMORY.md` after corrections or durable discoveries
10. Before final handoff for substantial work, run `clean-context` to compress completed context and refresh high-signal summaries

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
- Do not open a pull request unless explicitly asked
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

## Memory promotion policy
Use a strict funnel:

1. Temporary notes go to `../.ai/tasks/<unique_task_name>/TASK.md`
2. Only durable, reusable facts may be promoted
3. Promote durable facts into:
   - `../.ai/FRAGMENTS/repo-map.md`
   - `../.ai/FRAGMENTS/conventions.md`
   - `../.ai/FRAGMENTS/gotchas.md`
   - `../.ai/LEARNINGS/workflows.md`
   - `../.ai/LEARNINGS/bugs.md`
4. Update `../.ai/MEMORY.md` only for high-value summary facts
5. Do not append raw scratch notes, verbose logs, or one-off task chatter to durable memory

## Promotion criteria
A fact qualifies for promotion only if it is likely useful in future tasks and is:
- architectural
- procedural
- a recurring bug pattern
- a recurring workflow dependency
- a naming or layering convention
- an environment/setup gotcha

If not durable, keep it temporary or discard it.

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
- `./commands/validate-opencaw.sh`

Use these when:
- adding or editing role files
- adding or editing skills
- adding or editing commands
- reviewing changes to the OpenCaw baseline

Prefer running full validation before finalizing structural changes to OpenCaw.

## Host repository assumption
When this starter is mounted in a project, the host project root is the parent directory of this folder.
