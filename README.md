
# OpenCaw

![](OpenCaw.png)

https://github.com/user-attachments/assets/eb32b378-7269-4aa7-90d4-cbc0cba535f9

OpenCaw helps you work with an AI coding agent the way you would work with a thoughtful teammate: describe what you want in ordinary language, refine the plan together, and let the agent handle the repository-specific machinery.

You do **not** need to memorize role names, invoke skills, or know command syntax before you can use it. Those controls are available when you want extra precision, but the normal interface is simply a conversation.

```text
Help me plan a safe migration from our legacy checkout flow. Do not change code yet. Inspect the repository, identify the risky boundaries, and propose reviewable phases with tests and rollback points.
```

That is a complete OpenCaw request.

Behind the conversation, OpenCaw provides a shared system for planning, architecture, implementation, task tracking, repository memory, verification, and delivery across tools such as **Cursor, Codex, and Claude**. It can be mounted as `.codex`, `.cursor`, or `.claude` while keeping project-specific context inside the host repository.

```mermaid
flowchart TB
    accTitle: OpenCaw Brainstorm, planning, and delivery workflows
    accDescr: A request may explicitly enter persistent Brainstorm discovery before planning, then uses task mode by default, explicit goal mode for ordered task pull requests, or explicit Gauntlet mode for reviewed work-unit pull requests and final promotion.

    Request["Natural-language request"] --> Discovery{"Explicit Brainstorm mode?"}
    Discovery -->|"No"| Plan["Plan the understood work"]
    Discovery -->|"Yes"| Brainstorm["Activate persistent Brainstorm state"]
    Brainstorm --> Understand["Clarify one idea to baseline understanding"]
    Understand --> Research["Project manager plus two independent researchers"]
    Research --> Organize["Place the researched element in the branch graph"]
    Organize --> Continue{"Explicitly exit Brainstorm?"}
    Continue -->|"No; continue ideas"| Understand
    Continue -->|"Yes"| Summary["Generate the hash-bound summary index"]
    Summary --> Plan
    Plan --> Mode{"Delivery mode"}

    Mode -->|"Task: default"| Task["Complete one assignment"]
    Task --> TaskVerify["Verify the result"]
    TaskVerify --> TaskGate["Human PR readiness approval"]
    TaskGate --> TaskQA["Open one PR and run post-PR QA"]
    TaskQA --> HumanMerge["Human review and merge"]

    Mode -->|"Goal: explicit"| GoalTask["Complete next ordered task"]
    GoalTask --> GoalVerify["Verify the task"]
    GoalVerify --> GoalPR["Open its PR automatically"]
    GoalPR --> GoalQA["Run post-PR QA"]
    GoalQA --> GoalMore{"More tasks?"}
    GoalMore -->|"Yes"| GoalTask
    GoalMore -->|"No"| GoalReport["Prepare goal completion report"]
    GoalReport --> HumanMerge

    Mode -->|"Gauntlet: explicit"| Bar["Approve bar, delivery base, and progress-PR contract"]
    Bar --> GBranch["Create durable gauntlet/name integration branch"]
    GBranch --> Units["Derive independently judgeable work units"]
    Units --> Build["Builder improves one unit"]
    Build --> UnitPR["Publish or update its progress PR automatically to the integration branch"]
    UnitPR --> Critic["Fresh critic reviews the artifact; post round evidence"]
    Critic -->|"Fail"| RecordUnitFail["Post and record PR QA failure"]
    RecordUnitFail --> Build
    Critic -->|"Pass"| UnitQA["Run PR QA and post results"]
    UnitQA -->|"Fail"| RecordUnitFail
    UnitQA -->|"Pass"| UnitMerge["Human merges the unit PR"]
    UnitMerge --> MoreUnits{"All active units integrated?"}
    MoreUnits -->|"No; start independent or newly unblocked unit"| Build
    MoreUnits -->|"Yes"| Integration["Fresh critic reviews the integrated artifact"]
    Integration -->|"Fail"| Reopen["Record failure and reopen affected units"]
    Reopen --> Remediation["Builder corrects and verifies affected work"]
    Remediation --> RemediationPR["Run progress readiness and publish remediation PR"]
    RemediationPR --> Critic
    Integration -->|"Pass"| GauntletGate["Human promotion-PR readiness approval"]
    GauntletGate --> Promotion["Open promotion PR to the approved delivery base"]
    Promotion --> PromotionQA["Run promotion PR QA"]
    PromotionQA -->|"Pass"| HumanMerge
    PromotionQA -->|"Fail"| PromotionFail["Record failure, archive completion, and reopen named units"]
    PromotionFail --> Remediation
```

---

# Table of Contents

- [Start with a Normal Request](#start-with-a-normal-request)
  - [No Magic Words](#no-magic-words)
  - [Choose a Work Mode](#choose-a-work-mode)
  - [Brainstorm Before Planning](#brainstorm-before-planning)
  - [Planning Is a Conversation](#planning-is-a-conversation)
  - [A Realistic Planning Flow](#a-realistic-planning-flow)
  - [What OpenCaw Does Behind the Scenes](#what-opencaw-does-behind-the-scenes)
  - [Natural-Language Examples](#natural-language-examples)
  - [When Explicit Controls Help](#when-explicit-controls-help)
- [Install](#install)
  - [Fork OpenCaw First](#fork-opencaw-first)
  - [Choose a Mount Name](#choose-a-mount-name)
  - [Windows Bash Prerequisite](#windows-bash-prerequisite)
  - [Option 1 — Git Submodule](#option-1--git-submodule)
  - [Option 2 — Clone](#option-2--clone)
  - [Start the First Session](#start-the-first-session)
- [Technical Reference](#technical-reference)
  - [Runtime Model](#runtime-model)
  - [Session Startup and Context Resolution](#session-startup-and-context-resolution)
  - [Repository Layering](#repository-layering)
  - [Architecture, Style, and Media Contracts](#architecture-style-and-media-contracts)
  - [Roles](#roles)
  - [Role, Skill, and Command Bindings](#role-skill-and-command-bindings)
  - [Skills](#skills)
  - [Commands](#commands)
  - [Sub-Agent Orchestration](#sub-agent-orchestration)
  - [Brainstorm, Task, Goal, and Gauntlet](#brainstorm-task-goal-and-gauntlet)
  - [Task, Issue, and PR Delivery](#task-issue-and-pr-delivery)
  - [Memory v2](#memory-v2)
  - [Generative Media](#generative-media)
  - [Validation](#validation)
  - [Repository Layout](#repository-layout)
- [Contributing](#contributing)
- [License](#license)

---

# Start with a Normal Request

OpenCaw is not a command language wrapped around an AI. It is a repository-aware operating system for the conversation you were already going to have.

Start with the outcome:

```text
The settings screen has become hard to maintain. Help me understand why, propose a cleaner structure, and then make the smallest safe refactor with tests.
```

You can add constraints naturally:

```text
Keep the public API stable. Do not add dependencies. Show me the plan before editing, and stop for approval before opening a PR.
```

You can correct direction naturally too:

```text
That plan is too broad. Keep the database untouched and split the UI cleanup from the API work.
```

OpenCaw uses the baseline instructions, project contracts, repository structure, task state, and relevant memory to turn that conversation into governed work. You can stay at this level for the whole task.

## No Magic Words

Role and skill names are **optional controls**, not required incantations.

| You can simply say | OpenCaw can interpret it as |
| --- | --- |
| “Before coding, help me work out the safest approach.” | Inspect context, identify decisions, and produce a plan. |
| “Find the root cause and prove the fix.” | Diagnose, implement a focused correction, and run verification. |
| “Review this like a security-minded senior engineer.” | Apply a security review lens without requiring a role name. |
| “This is large; split only the parts that can safely run in parallel.” | Plan bounded sub-agent lanes when parallelism is useful and available. |
| “Take this from idea through a reviewed PR, but ask before publishing.” | Track the task, implement, validate, then stop at the PR readiness gate. |
| “Remember this repository rule for next time.” | Validate and store durable project knowledge under `.ai/`. |

These prompts are examples, not fixed syntax. Equivalent natural wording works.

You may still say `use role security-engineer`, invoke a named skill, or request a command when you know exactly which control you want. OpenCaw does not require that level of specificity to plan or complete ordinary work.

## Choose a Work Mode

OpenCaw has three work modes. A normal specific assignment uses task mode; goal and Gauntlet modes begin only when you explicitly request them.

Before those work modes, you may explicitly enter the optional Brainstorm discovery stage. The hierarchy is `Brainstorm → Plan → Task | Goal | Gauntlet`; Brainstorm never creates delivery work itself.

| Mode | Best for | Completion | PR behavior |
| --- | --- | --- | --- |
| Task | One specific assignment | The requested result passes its relevant verification | One PR after human readiness approval |
| Goal | An ordered collection of tasks | Every task is done and its post-PR QA has completed | A PR may open automatically for each task; merging remains human-controlled |
| Gauntlet | One ambitious, inspectable deliverable that benefits from adversarial iteration | Every active unit is critic-passed and PR-QA-passed at the same frozen scope and exact head SHA, that reviewed head is human-merged into its integration branch, then a fresh integration review passes | An approved contract permits automatic progress PRs; every merge and the final promotion PR remain human-controlled |

For ordinary work, describe the assignment directly:

```text
Fix the duplicate invoice bug, add a regression test, and stop when the branch is ready for my PR approval.
```

Use goal mode when several tasks should advance automatically through separate PRs:

```text
Use goal flow for these four migration tasks. Validate and open each task PR, run its post-PR QA, then continue. Never merge automatically.
```

Use Gauntlet mode when the result should survive repeated independent comparison against a concrete benchmark:

```text
Use gauntlet mode for this onboarding redesign. First propose an inspectable quality bar, delivery base, and integration-branch contract for my approval. Publish each unit's progress PR automatically after approval, use fresh critics, and leave every merge and the final promotion PR under human control.
```

Gauntlet mode is appropriate only when a critic can inspect the real output—such as running code, rendered pixels, test or performance results, a finished document, or another concrete artifact. It never permits the builder to grade its own work. Its progress PRs provide review surfaces throughout the loop; the final promotion PR is the integration boundary back to the approved delivery base, not the first review surface.

## Brainstorm Before Planning

Use Brainstorm mode when an idea needs structured clarification and substantial research before it is ready to become a plan:

```text
Enter Brainstorm mode. I want to explore a cooperative city-building game where players recover after disasters. Research the audience, comparable systems, technical risks, and a concrete definition of complete.
```

Brainstorm is deliberately explicit and sticky. Once entered, repository-root `BRAINSTORM.md` remains active across conversations until you explicitly turn it off. While active, OpenCaw does not create tasks, issues, goals, Gauntlets, implementation changes, commits, or PRs.

The Brainstorm team always has three participants: the main project-manager and two persistent read-only researcher subagents. One researcher focuses on the problem, audience, and precedent; the other focuses on feasibility, constraints, risks, start conditions, and measurable completeness. If both researcher slots are unavailable, idea processing stops rather than falling back to a smaller team.

Each materially distinct idea receives a stable `IDEA-NNN` identifier and belongs to the deepest matching stable `BR-NNN` branch. Only the project-manager writes the synthesized element, including:

- original user idea and established understanding
- sourced research with facts, inference, disagreements, and uncertainty separated
- dependencies, risks, and open questions
- concrete start conditions and definition of complete
- lifecycle status and plan readiness

Ask to see the Brainstorm and OpenCaw returns a Mermaid mindmap. Ask to see it “in Markdown” and it returns the complete `BRAINSTORM.md` instead.

Explicit exit preserves every complete or incomplete element and generates repository-root `BRAINSTORM_SUMMARY.md`, grouped by branch and bound to the final source hash. OpenCaw then waits; it plans only after you explicitly select an element.

Lifecycle commands:

```bash
./commands/brainstorm-mode.sh start
./commands/brainstorm-mode.sh status
./commands/show-brainstorm.sh
./commands/show-brainstorm.sh --markdown
./commands/brainstorm-mode.sh stop
./commands/validate-brainstorm.sh --phase inactive
```

## Planning Is a Conversation

Planning is where natural-language use is often most powerful.

You can begin with uncertainty:

```text
I know the reporting module needs to be modernized, but I am not sure where to start. Inspect it and help me turn the problem into a safe sequence of decisions and changes. Do not implement anything yet.
```

OpenCaw can then:

1. Resolve the repository boundary and load the relevant project context.
2. Inspect the current architecture, active tasks, tests, and likely change surface.
3. Separate facts from assumptions and identify decisions only you can make.
4. Draft an ordered plan with dependencies, risks, verification, and rollback points.
5. Let you revise the plan in plain language.
6. Record the agreed task structure before implementation.
7. Keep the plan current when discoveries change the direction.

Useful planning phrases include:

```text
Plan this with me before touching code.
```

```text
Give me three options and recommend one, including migration and rollback costs.
```

```text
Turn this idea into small PR-sized tasks and call out what can run in parallel.
```

```text
Assume zero downtime and no schema breaking changes. What does that change in the plan?
```

```text
We learned the API is shared by mobile. Stop and re-plan around backward compatibility.
```

You are not locked into the first plan. OpenCaw treats corrections, new evidence, and changed constraints as reasons to update the plan rather than push through stale assumptions.

## A Realistic Planning Flow

Here is a complete interaction without role or skill syntax:

```text
You:
Our authentication code is spread across the API and web app. I want a simpler design, but I cannot break mobile clients. First inspect the repository and give me a phased plan. Do not edit yet.

OpenCaw:
Inspects the architecture, authentication boundaries, active issues, tests, and relevant repository memory. Returns a plan with assumptions, compatibility risks, phases, and verification.

You:
Keep token formats unchanged in phase one. Separate observability from the refactor, and make the first task small enough for one reviewer.

OpenCaw:
Updates the plan, narrows phase one, and makes the dependency order explicit.

You:
Implement phase one. Add focused tests, run the broader validation, and tell me when it is ready for a PR.

OpenCaw:
Creates or updates task tracking, implements the agreed slice, verifies it, records reusable findings, and stops at the PR readiness gate.
```

The named machinery is still there—roles, skills, commands, task files, memory, and validation—but it supports the conversation instead of replacing it.

## What OpenCaw Does Behind the Scenes

For a substantial request, the normal flow is:

1. **Resolve the project safely** — find the actual host repository and mounted OpenCaw directory without guessing across workspace boundaries.
2. **Load high-signal context** — read protected repository memory, project rules, architecture/style contracts, active tasks, and relevant tagged knowledge.
3. **Restore or choose discovery** — resume an active Brainstorm before planning, or enter it only after an explicit request.
4. **Understand the request** — distinguish the desired outcome, constraints, assumptions, authorization boundaries, and definition of done; Brainstorm may use two researcher lanes to deepen that understanding.
5. **Select and plan the work contract** — after Brainstorm is explicitly closed when active, plan into task mode by default or an explicitly requested goal or Gauntlet lifecycle.
6. **Choose capabilities** — apply baseline behavior and automatically use relevant skills; explicit roles remain optional specialist lenses.
7. **Track real work** — create or import a task, link its GitHub issue, and keep the active checklist concise.
8. **Implement carefully** — make focused changes, preserve unrelated work, and use safe parallel lanes only when they genuinely help.
9. **Prove the result** — run targeted tests, broader validation, logs, browser checks, or artifacts appropriate to the risk.
10. **Preserve durable learning** — record verified, reusable repository facts and keep the semantic map current.
11. **Deliver by mode** — task work pauses before publication; goal flow may publish validated task PRs; an approved Gauntlet contract may publish unit progress PRs to its integration branch; every path keeps merges human-controlled, and Gauntlet promotion still requires a final human gate.

OpenCaw can do this even if your prompt never mentions a role, skill, command, task file, memory tag, or validation script.

## Natural-Language Examples

### Understand a repository

```text
I am new to this codebase. Explain how a request moves from the API entry point to storage, show me the important files, and call out the parts that are risky to change.
```

### Plan a feature

```text
Help me plan team invitations. We need expiring links, audit history, and no new infrastructure. Ask me only for decisions that materially change the design, then produce reviewable implementation tasks.
```

### Build a feature

```text
Add CSV export to the reporting page. Match the existing architecture, keep the UI accessible, add tests, and verify the download in a browser. Do not publish anything until I approve the PR.
```

### Diagnose a bug

```text
Users occasionally see duplicate invoices after retrying checkout. Find concrete evidence for the root cause, fix it without changing the public API, and add a regression test.
```

### Review without editing

```text
Review this pull request for correctness, security, and maintainability. Do not change files. Rank findings by severity and point to the exact evidence.
```

### Work from an issue

```text
Work on #123. Import the issue into task tracking, implement the smallest complete fix, test it, and prepare the PR readiness summary.
```

### Plan safe parallel work

```text
This migration is large. Split independent investigation, implementation, and QA work into safe lanes, avoid overlapping write scopes, then integrate and verify everything from the main lane.
```

### Create visual or media assets

```text
Help me define the visual direction for this onboarding flow, produce a reusable style contract, and stage a small set of image concepts for review without promoting them into runtime assets yet.
```

### Improve the process itself

```text
We keep rediscovering the same Windows path issue. Verify the pattern, fix the workflow, add a regression check, and remember the durable rule for future tasks.
```

## When Explicit Controls Help

Natural language is the default. Explicit controls are useful when you want to constrain *how* OpenCaw approaches the work.

| Control | Use it when | Example |
| --- | --- | --- |
| Role | You want a named specialist perspective or composition order. | `Use roles backend-architect + security-engineer.` |
| Skill | You want one exact reusable workflow. | `Use the dependency audit skill before changing packages.` |
| Command | You want a deterministic repository script. | `Run the full OpenCaw validation command.` |
| Agent count | You are authorizing parallel agent work and want a capacity ceiling. | `Use up to 3 agents, but only for independent lanes.` |
| Issue reference | Existing GitHub issue content is the source task. | `Work on #123.` |
| Brainstorm mode | An idea needs persistent, research-heavy discovery before planning. | `Enter Brainstorm mode and research this game idea.` |
| Task mode | You want to emphasize that one assignment should end at the normal human PR gate. | `Use task mode for this bug fix.` |
| Goal flow | You explicitly authorize automated task-to-PR progression across multiple tasks. | `Use goal flow for these four tasks; never merge automatically.` |
| Gauntlet flow | You want one deliverable repeatedly judged by independent critics against an approved bar. | `Use gauntlet mode for this redesign.` |

Explicit role examples:

```text
Use role security-engineer + sre and review the service for exploit paths and resilience gaps.
```

```text
Act as project-manager + fullstack-engineer. Build a safe parallel plan, then implement only after I approve it.
```

Explicit goal-flow example:

```text
Goal: modernize the reporting module across these five tasks. Raise each task PR after validation, run post-PR QA, then continue. Never merge PRs automatically.
```

Explicit Brainstorm example:

```text
Start Brainstorm mode for a privacy-first family scheduling app. Organize each idea into the existing graph, use both researchers, and do not create a plan until I explicitly exit and select an element.
```

Explicit Gauntlet example:

```text
Use gauntlet flow for the reporting experience. Propose a concrete benchmark and an approved delivery base, create a durable gauntlet integration branch, and let disjoint units publish progress PRs there automatically. Use a fresh critic for every round, require PR QA and human merge before a unit counts as integrated, and keep final promotion human-gated.
```

Brainstorm is explicit because it creates persistent pre-planning state and suspends delivery-mode creation until explicit exit. Goal flow is explicit because it changes the normal PR publication authorization boundary. Gauntlet flow is explicit because its approved contract authorizes progress PR publication and changes the execution and evidence model. That authorization never includes a merge: unit, remediation, and promotion merges remain human decisions, and the final promotion PR retains a human readiness gate. Ordinary natural-language work remains task mode and pauses for approval before publication.

---

# Install

OpenCaw is designed to be mounted directly inside an existing repository as one of:

```text
.codex/
.cursor/
.claude/
```

The mounted directory is the reusable baseline. Project-specific memory, tasks, rules, and generated contracts stay in the host repository.

## Fork OpenCaw First

Fork the repository before installing it into production or team projects. A fork gives your team control over updates, custom roles and skills, security policy, and the exact version each repository consumes.

Upstream repository:

https://github.com/TimothyMeadows/OpenCaw

Example fork:

```text
https://github.com/<your-org>/OpenCaw
```

Use your fork URL in the installation commands below.

## Choose a Mount Name

Choose the directory recognized by your AI tool:

| Tool or convention | Typical mount |
| --- | --- |
| Codex | `.codex` |
| Cursor | `.cursor` |
| Claude | `.claude` |

Examples below use `.codex`. Replace it consistently if you choose another mount.

## Windows Bash Prerequisite

OpenCaw commands use Bash. Linux and macOS normally already provide the expected runtime.

On Windows, Git Bash is recommended for native Windows filesystem performance. After OpenCaw is mounted, inspect available providers from PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\.codex\commands\install-windows-bash.ps1"
```

Install Git Bash explicitly when needed:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\.codex\commands\install-windows-bash.ps1" -Provider GitBash -Install
```

Or explicitly install WSL when Linux tooling compatibility is preferred:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\.codex\commands\install-windows-bash.ps1" -Provider WSL -Install
```

OpenCaw never installs Bash implicitly. Use `-WhatIf` to preview installation or scaffold execution.

Run the canonical scaffold through the selected provider:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\.codex\commands\install-windows-bash.ps1" -Provider GitBash -RunScaffold -ProjectRoot .
```

## Option 1 — Git Submodule

Recommended for teams that want centralized OpenCaw updates while pinning each host repository to a reviewed revision:

```bash
git submodule add https://github.com/<your-org>/OpenCaw .codex
git submodule update --init --recursive
```

Update later when your team is ready:

```bash
git submodule update --remote
```

Equivalent mount examples:

```bash
git submodule add https://github.com/<your-org>/OpenCaw .cursor
git submodule add https://github.com/<your-org>/OpenCaw .claude
```

## Option 2 — Clone

Use a direct clone when the host repository needs an independent, customized copy:

```bash
git clone https://github.com/<your-org>/OpenCaw .codex
```

Equivalent mount examples:

```bash
git clone https://github.com/<your-org>/OpenCaw .cursor
git clone https://github.com/<your-org>/OpenCaw .claude
```

## Start the First Session

Most compatible agents automatically discover the mounted `AGENTS.md` baseline or the host bootstrap that points to it. If discovery has not happened yet, use a natural request:

```text
Read the OpenCaw AGENTS.md instructions, initialize the repository-local .ai scaffold, and explain what project context is available before we start.
```

After initialization, begin with the work itself:

```text
I want to improve the onboarding flow. First help me understand the current implementation and create a safe plan. Do not edit yet.
```

---

# Technical Reference

The rest of this README describes the machinery behind the conversational experience. You do not need to invoke each layer manually; this section exists for teams that want to inspect, extend, or govern the system.

## Runtime Model

| Layer | Responsibility | User relationship |
| --- | --- | --- |
| Natural-language request | Outcome, constraints, corrections, authorization, and definition of done | Primary interface |
| `AGENTS.md` baseline | Startup, planning, safety, task, memory, verification, and delivery policy | Loaded by the agent |
| Project contracts | Repository architecture, visual language, media policy, and local rules | Created or consulted when relevant |
| Roles | Named specialist perspective and priorities | Optional precision control |
| Skills | Reusable reasoning and workflow instructions | Selected automatically when relevant or explicitly requested |
| Commands | Deterministic scripts for repeatable execution | Run by the agent or directly by developers |
| Task, goal, and Gauntlet state | Assignment scope, multi-task delivery, adversarial rounds, integration branches, PR/QA events, and GitHub traceability | Maintained for the selected work mode |
| Memory and repository map | Durable facts and semantic repository structure | Queried selectively before broad searches |
| Verification evidence | Tests, logs, browser artifacts, and PR QA comments | Required before completion |

Roles, skills, and commands deepen control, but baseline OpenCaw behavior works without explicitly naming any of them.

## Session Startup and Context Resolution

At session start, OpenCaw follows a memory-first sequence:

1. Resolve the actual project root and mounted baseline with `commands/resolve-opencaw-paths.sh`.
2. Create the repository-local `.ai` scaffold when required.
3. Load all of `.ai/SYSTEM_MEMORY.md`.
4. Review project rules, `ARCHITECTURE.md`, `STYLE.md`, active task tracking, and open issues when present.
5. Infer relevant memory tags and query ranked context before broad raw searches.
6. Check the semantic repository-map fingerprint and refresh stale structure when necessary.
7. Plan and execute the current request using the narrowest safe scope.

The resolver accepts an explicit `OPENCAW_PROJECT_ROOT`, a Git root associated with the host, or the parent of a recognized `.codex`, `.cursor`, or `.claude` mount. It fails closed when the project boundary is ambiguous.

## Repository Layering

OpenCaw separates reusable baseline behavior from host-project state.

### Shared mounted baseline

```text
<project-root>/.codex/    # or .cursor/ or .claude/
├── AGENTS.md
├── .architecture/
├── .roles/
├── .styles/
├── skills/
├── commands/
├── assets/
└── tests/
```

### Repository-local project state

```text
<project-root>/
├── AGENTS.md
├── ARCHITECTURE.md
├── STYLE.md
├── MEDIA.md                 # optional
└── .ai/
    ├── SYSTEM_MEMORY.md
    ├── MEMORY.md
    ├── REPO_MAP.md
    ├── RULES.md
    ├── DEBUG.md
    ├── CONTEXT_SUMMARY.md
    ├── tasks/
    ├── goals/
    ├── gauntlets/              # contracts, immutable rounds, and ordered PR/QA ledgers
    ├── archive/
    │   ├── tasks/
    │   ├── goals/
    │   └── gauntlets/
    └── reports/
```

Project-specific learned state belongs under the host repository's `.ai/` directory, never inside the reusable mounted baseline unless the user explicitly asks to modify the baseline itself.

## Architecture, Style, and Media Contracts

OpenCaw uses concise host-level contracts so agents do not have to rediscover foundational decisions during every task.

| Contract | Host file | Template source | Purpose |
| --- | --- | --- | --- |
| Architecture | `ARCHITECTURE.md` | `.architecture/` | Technology, boundaries, data, deployment, and engineering conventions |
| Visual style | `STYLE.md` | `.styles/*.md` | Visual language, UI/art constraints, asset direction, and review criteria |
| Generative media | `MEDIA.md` | `.styles/.gpu/` | Backend selection, capability, provenance, staging, budgets, and promotion policy |

When a required architecture or style contract is missing, OpenCaw asks which templates apply and supports composing more than one. Default generation uses concise read directives rather than copying entire templates into the host file. Inline generation is opt-in.

### Architecture frameworks

Common templates include:

- `.NET`, .NET Aspire, MAUI, Node.js, Python, Next.js, SPA, React, Angular, and Vue
- Playwright, SignalR/WebSockets, embedded firmware, and Solidity
- MSSQL, MySQL, PostgreSQL, SQLite, Cosmos DB, Azure Storage Tables, and Databricks
- Microservices, event-driven systems, Terraform, Kubernetes, Helm, GitHub Actions, and Azure DevOps
- Azure-specific infrastructure and application guidance

Templates live in `.architecture/`; language and tool alignment guidance lives in `.architecture/LANGUAGE_SUPPORT.md`.

Generate a host contract with:

```bash
./commands/generate-architecture.sh "DOTNET" "POSTGRESDB"
```

### Style contracts

Style templates live in `.styles/` and cover web experiences, UI systems, 2D/2.5D art, card games, VFX, papercraft, dark fantasy, tactical interfaces, and other asset-production directions.

Generate and validate a host style contract with:

```bash
./commands/generate-style.sh "WEB_LIGHT_PAPER"
./commands/validate-style-contract.sh
```

The complete style catalog is indexed in `.styles/INDEX.md`.

## Roles

Roles are optional named perspectives. Use one when you want a specific specialist lens, not because OpenCaw requires a role to work.

Role definitions live at:

```text
.roles/<domain>/<role-name>/ROLE.md
```

Current catalogs include computer-science and arts roles. Browse names, domains, and aliases in `.roles/INDEX.md`.

Role references may be:

- an exact name: `backend-architect`
- an alias: `security`
- a domain-qualified ID: `computer-science/backend-architect`

Examples:

```text
Use role backend-architect and review the service boundaries.
```

```text
Act as security + sre. Find exploit paths and operational failure modes.
```

If an unqualified name or alias is ambiguous across domains, OpenCaw asks for the domain-qualified role. Exact role-name matches take precedence over aliases.

### Multi-role composition

Roles compose in the order requested:

```text
Use roles frontend-developer + qa-engineer.
```

The first role is the primary perspective by default. Later roles add specialist constraints and review lenses. When guidance conflicts, the stricter or safer interpretation wins unless the user sets a different priority.

Deterministic resolution:

```bash
./commands/resolve-role.sh "security"
```

## Role, Skill, and Command Bindings

Role casting can influence more than tone. OpenCaw maintains default bindings between roles, reusable skills, and preferred commands:

```text
.roles/ROLE_SKILL_MAP.json
.roles/ROLE_SKILL_MAP.md
```

The JSON file is canonical. The Markdown map is generated deterministically and validated for drift.

Examples of role bias:

- `backend-architect` emphasizes service boundaries, architecture review, and dependency decisions.
- `frontend-developer` emphasizes component structure, accessibility, rendering, and browser evidence.
- `security-engineer` emphasizes threat modeling, vulnerability review, and least privilege.
- `sre` emphasizes resilience, observability, performance, and incident evidence.
- `art-director` emphasizes visual language, asset consistency, production constraints, and specialist art routing.
- `gameplay-engineer` emphasizes deterministic runtime systems, production tools, optimization, and playtesting.

Generate and validate the binding map with:

```bash
./commands/generate-role-skill-map.sh
./commands/validate-role-skill-map.sh
```

## Skills

Skills are focused, reusable workflows stored at:

```text
skills/<skill-name>/SKILL.md
```

Each skill includes matching interface metadata at `skills/<skill-name>/agents/openai.yaml`. Skills define when a workflow applies, what steps to follow, what output to produce, and what safety boundaries to preserve.

The agent selects a skill automatically when the request clearly matches its purpose. Explicit invocation remains available:

```text
Use the clean-context skill after this work is fully verified.
```

or, where the host interface supports named skill syntax:

```text
$clean-context
```

### Common skills

| Area | Examples | Purpose |
| --- | --- | --- |
| Discovery | `brainstorm-flow` | Persist, research, branch, visualize, and summarize ideas before planning |
| Planning and governance | `create-task-file`, `manage-task-issues`, `pr-readiness-gate`, `post-pr-qa` | Track work, preserve authorization boundaries, and publish evidence |
| Context | `maintain-memory`, `maintain-repository-map`, `clean-context` | Retrieve and preserve durable high-signal project knowledge |
| Parallel work | `orchestrate-subagents` | Create safe role-resolved lanes and integrate their evidence |
| Goal delivery | `goal-flow` | Manage explicit multi-task PR and post-PR-QA automation |
| Adversarial delivery | `gauntlet-flow` | Run builder and fresh-critic rounds through reviewable unit PRs, human-controlled integration, and final promotion |
| Build and test | `solution-build`, `test-dotnet` | Restore, build, test, and report repository results |
| Browser QA | `playwright-e2e-tests`, `playwright-browser-discovery`, `playwright-test-refinement`, `playwright-reporting` | Discover behavior, author tests, diagnose failures, and package evidence |
| Data | `install-database-cli-tools`, `database-cli-query` | Prepare and run engine-specific database workflows |
| Generative media | `plan-generative-media-pipeline`, `use-comfyui-local-generation`, `produce-generative-audio`, `validate-generated-media` | Plan, generate, stage, review, and validate reproducible media |
| Art and experience | `tcg-art-direction` and specialist web/game/art skills | Produce original, implementation-ready direction and evidence |

See `skills/INDEX.md` for the complete catalog.

## Commands

Commands are deterministic scripts used underneath conversational workflows or directly by developers:

```text
commands/*.sh
commands/*.ps1
```

You can ask naturally:

```text
Run the full OpenCaw validation and summarize any failures.
```

Or run the command directly:

```bash
./commands/validate-opencaw.sh
```

### Common command groups

| Group | Commands |
| --- | --- |
| Project resolution and scaffold | `resolve-opencaw-paths.sh`, `create-host-ai-scaffold.sh`, `install-windows-bash.ps1` |
| Brainstorm discovery | `brainstorm-mode.sh`, `validate-brainstorm.sh`, `show-brainstorm.sh` |
| Architecture and style | `generate-architecture.sh`, `generate-style.sh`, `validate-style-contract.sh` |
| Task and issue tracking | `create-task-file.sh`, `create-task-issue.sh`, `import-task-from-issue.sh`, `sync-task-issues.sh` |
| Sub-agent planning | `create-subagent-plan.sh`, `validate-subagent-plan.sh`, `record-subagent-result.sh` |
| Goal flow | `create-goal-file.sh`, `create-goal-completion-report.sh` |
| Gauntlet flow | `create-gauntlet-file.sh`, `validate-gauntlet.sh`, `record-gauntlet-round.sh`, `record-gauntlet-pr-event.sh`, `record-gauntlet-promotion-qa.sh`, `create-gauntlet-completion-report.sh` |
| PR delivery | `pr-readiness-check.sh`, `link-pr-to-task-issue.sh`, `comment-pr-qa-results.sh`, `comment-issue-test-results.sh` |
| Memory | `append-system-memory.sh`, `append-project-memory.sh`, `query-project-context.sh`, `purge-project-memory.sh`, `migrate-memory-v2.sh`, `clean-context.sh` |
| Repository map | `repo-map-status.sh` |
| .NET | `dotnet-restore.sh`, `dotnet-build.sh`, `dotnet-test.sh` |
| Browser QA | `playwright-install.sh`, `playwright-test.sh`, `playwright-capture-page.sh`, `playwright-report-summary.sh`, `playwright-artifact-index.sh` |
| Security and dependencies | `security-scan.sh`, `audit-agent-source.sh` |
| Databases | `install-database-cli-tools.sh`, `database-cli-query.sh` |
| Generative media | `generate-media-contract.sh`, `validate-media-contract.sh`, `install-comfyui-local.sh`, `install-comfyui-models.sh`, `inspect-local-media-host.sh`, `run-comfyui-workflow.sh`, `validate-media-generation-manifest.sh` |
| Validation | `validate-readme.sh`, `validate-roles.sh`, `validate-skills.sh`, `validate-commands.sh`, `validate-role-skill-map.sh`, `validate-media-templates.sh`, `validate-memory.sh`, `validate-opencaw.sh` |

Commands should remain deterministic, reviewable, platform-safe, and non-self-installing unless an installation action is explicitly authorized.

## Sub-Agent Orchestration

OpenCaw supports parallel work when the user requests multiple agents or when the applicable project policy explicitly permits safe parallel lanes.

Natural request:

```text
This feature has independent API, UI, and QA work. Split it into safe parallel lanes, keep file ownership separate, then integrate and verify from the main lane.
```

Count-constrained request:

```text
Use up to 4 agents. Do not invent work just to fill every slot, and reserve final integration for the main agent.
```

For substantial task-backed work, the durable lane plan lives at:

```text
.ai/tasks/<task-name>/SUBAGENTS.md
```

It records:

- requested and effective capacity
- lane IDs and resolved OpenCaw roles
- explorer, worker, or default agent type
- scope and non-overlapping write sets
- dependencies and integration order
- expected outputs and verification
- completed lane evidence and conflict risks

The main agent remains responsible for orchestration, critical-path blockers, integration, final verification, and user communication.

Brainstorm is the deliberate exception to task-backed lane files: its fixed three-person team is owned by `brainstorm-flow`, both researchers are read-only, their reports remain ephemeral, and only the main project-manager writes `BRAINSTORM.md`.

Helper commands:

```bash
./commands/create-subagent-plan.sh "<task_name>" "<agent_count>" --dry-run
./commands/validate-subagent-plan.sh "<task_name>"
./commands/record-subagent-result.sh "<task_name>" "<lane_id>" "<status>" "<summary_file>"
```

Parallelism is reduced when lanes would overlap, roles are unresolved, verification is unclear, or coordination would cost more than the work.

## Brainstorm, Task, Goal, and Gauntlet

Brainstorm precedes planning; Task, Goal, and Gauntlet remain sibling delivery modes after planning. The selected stage or mode controls durable state, stopping conditions, and publication boundaries.

| Stage or mode | Activation | Durable state | Loop | Publication |
| --- | --- | --- | --- | --- |
| Brainstorm | Explicit `start` or `enter Brainstorm mode`, or active repository state restored at startup | `BRAINSTORM.md`; hash-bound `BRAINSTORM_SUMMARY.md` on exit | Clarify, branch, research with two independent researchers, and synthesize ideas | None; delivery creation is blocked while active |
| Task | Default for a specific assignment; may also be named explicitly | `.ai/tasks/<task-name>/TASK.md` | Plan, implement, and verify one assignment | Human approval before its PR |
| Goal | Explicit `goal` or `goal flow`, or `Goal Flow: enabled` / `Flow: goal` in a planning artifact | `.ai/goals/<goal-name>/GOAL.md` plus its task artifacts | Complete each ordered task and its post-PR QA | Each task PR may open automatically; merging remains human-controlled |
| Gauntlet | Explicit `gauntlet`, `gauntlet mode`, or `gauntlet flow`, or `Gauntlet Mode: enabled` / `Flow: gauntlet` in an artifact | `.ai/gauntlets/<gauntlet-name>/GAUNTLET.md`, immutable rounds, and an ordered PR/QA ledger | Build and criticize units on progress PRs, human-merge them into `gauntlet/<name>`, then test and promote the integrated artifact | Approved contract permits automatic progress and remediation PRs; every merge and final promotion publication remain human-controlled |

Task, Goal, and Gauntlet are sibling delivery modes. Brainstorm may feed planning for any one of them, but never nests with or creates them. A generic `## Goal` section in `TASK.md` describes task intent and does not activate goal flow. Gauntlet work units are not separate goal tasks. Their progress-PR authorization comes only from the explicitly approved Gauntlet contract, not from goal mode. If a request selects conflicting stages or delivery modes, OpenCaw asks which governs before changing project state.

### Brainstorm lifecycle

Brainstorm starts only through explicit user wording. Startup restores active state before planning or task inspection. Every new idea is clarified, classified under a stable branch, independently researched by two read-only researcher instances, synthesized by the project-manager, and validated. Explicit exit regenerates the complete summary index and waits for a later element-to-plan request.

Creation commands for tasks, task issues/imports, Goals, and Gauntlets fail closed while Brainstorm is active or malformed. When Brainstorm is absent or validly inactive, their behavior is unchanged.

### Task lifecycle

Task mode is the normal path for one assignment. OpenCaw creates or imports its task and issue, implements within the agreed scope, proves the result, and stops at the human PR readiness gate. After approval, it opens one linked PR and runs post-PR QA.

### Goal lifecycle

Goal mode is an explicitly authorized multi-task delivery flow. Each task still receives local planning, implementation, and validation. Its PR may then open automatically, but post-PR QA must finish before the next task begins. Dependent tasks can use a recorded branch chain.

Failures in validation, PR creation, post-PR QA, role resolution, conflict handling, or an uncovered product or security decision stop goal automation. Goal mode never merges, approves, or enables auto-merge.

Create and report goal state with:

```bash
./commands/create-goal-file.sh "<goal_name>" "<Goal Title>"
./commands/create-goal-completion-report.sh "<goal_name>"
```

The completion report orders PRs for approval and records branch dependencies, QA evidence, and conflict risk.

### Gauntlet lifecycle

A Gauntlet has one parent task and GitHub issue, one ambitious deliverable, and a quality bar that a critic can inspect. A useful bar may be a reference artifact, acceptance or recovery test, latency target, security review, or evidence-backed writing rubric.

Before building begins, the user approves a durable delivery contract containing:

- the inspectable quality bar and constraints
- the original delivery-base branch and exact commit that will receive the finished work
- a `gauntlet/<name>` integration branch created exactly at that commit
- permission to publish progress and remediation PRs automatically to that integration branch
- the rule that every PR merge, approval, and final promotion remains human-controlled

The first accepted opened progress-PR event freezes the approved parent task, objective, constraints/permissions, base identity, static delivery policy, quality bar, and normalized work-unit manifest into separate execution-contract, quality, and manifest fingerprints. An approved quality-bar revision preserves old rounds, records the revision in Unit History, reopens affected units, clears integration evidence, and resets promotion eligibility; only current evidence can satisfy the revised bar. Every retained unit has a durable ID, title, and inspectable scope. The normalized manifest contains sorted retained ID/title/scope definitions and sorted supersession ID/scope/replacement edges, but excludes transient checkbox/status state. The initial manifest requires an approved fingerprint. Additions, definition changes, or edge changes require an approved manifest revision; changed title or scope also requires a matching scope-title revision. Existing definitions cannot vanish or be renamed. Every per-unit checkpoint, PR event, and critic round must reference a unit present in, and the title/scope definition committed by, the manifest generation active at its timestamp. Unchanged exact scopes may retain evidence from an authorized earlier manifest, while added, changed, superseding, superseded, and causally affected units require fresh evidence.

Supersession requires exactly one canonical `- Unit supersession: <item-id> | scope: <scope-fingerprint> | replacements: <comma-sorted-active-item-ids> | reason: <substantive reason> | approved by: <identity> | approved at: <canonical-UTC>` Unit History marker. It must bind the old scope, name one or more active non-self replacements, follow all retained evidence chronologically, and prohibit later evidence for the superseded unit. The graph must be acyclic, every path must reach an active leaf, and every active descendant inherits each outstanding failure obligation from its ancestors; failed work cannot simply disappear. Every edge used to inherit a failure must already be approved when the replacement cycle's publication checkpoint is issued, before the live PR is created, so a later manifest revision cannot retroactively authorize earlier work.

`GAUNTLET.md` is the live contract and index. It records flow and status, the parent task, objective, approved quality bar, constraints and permissions, retained work-unit definitions and active scopes, execution/quality/unit-manifest fingerprints, frozen base commit, round/progress-PR/completion/promotion ledgers, merge topology, integration review, delivery state, and review notes. Append-only publication checkpoints live beside it and are consumed by opened entries in the hashed progress-PR ledger.

Do not fabricate progressive PR events for a Gauntlet started under the earlier single-final-PR contract. Preserve that run and report under `.ai/archive/gauntlets/`, then create a new progressive Gauntlet or explicitly supersede its old units and rebuild them through real work-unit PRs. Historical evidence without an observed PR head, QA result, and human merge cannot satisfy the new completion gate.

#### Work units and progress PRs

The lead derives the smallest work units that can be improved and judged independently. Each unit line freezes a stable ID, title, and inspectable scope/acceptance boundary. Each active unit gets one progress PR targeting `gauntlet/<name>` from `gauntlet-work/<name>/<item-id>`; later remediation or replacement cycles use `-remediation-N`. Builder/critic iterations normally update that open unit PR, so its comments show every failure and pass without creating throwaway PRs. A completed, closed, or causally superseded cycle gets a new PR. The separate `gauntlet-work/` namespace is required because Git cannot store `gauntlet/<name>` and a descendant branch beneath the same ref. Disjoint units may use separate branches and PRs in parallel. Coupled or dependent work waits until its prerequisite PR is human-merged, then starts from the resulting integration-branch state.

The approved contract authorizes progress-PR publication; it does not authorize merging. Before publication, readiness fetches the recorded origin, proves every effective push URL belongs to the issue repository, compares local and remote integration/work refs, proves the work head descends from the exact integration-chain tip, and writes an immutable `publication-checkpoints/<item-id>/checkpoint-NNN.md`. Gauntlet evidence permits only authenticated SSH or HTTPS `github.com` remotes—never plaintext HTTP—and explicitly pins live API queries to `github.com` instead of trusting an ambient `GH_HOST`. Its quality fingerprint plus exact `Quality bar approved at` value, manifest fingerprint plus exact `Unit manifest approved at` value, and every supersession edge used for inherited remediation must already be approved and active at that checkpoint's issuance time. The PR body must begin with case-sensitive `Refs #<issue-number>` and include exactly one emitted `<!-- opencaw-gauntlet-publication:v1 checkpoint=<path> checkpoint-sha256=<sha> -->` marker; every GitHub closing-keyword alias is reserved for the human-gated promotion PR. The opened-event recorder queries the live same-repository PR body, base/head branches and OIDs, state, draft flag, and creation time; it verifies that the checkpoint still matches the contract, fingerprints, refs, and remediation root, then consumes it exactly once. Every later round and event re-observes the mutable body, and each later head on that open PR must fast-forward from its prior recorded head. An unused checkpoint may document an aborted publication attempt, but it cannot authorize a later changed PR; issuing a newer checkpoint supersedes every older unused checkpoint for that unit.

A unit counts as integrated only when all three conditions are recorded for the current unit scope, unit-manifest, quality, and execution-contract fingerprints:

1. Its latest fresh critic verdict passes the approved bar at an identified full PR-head SHA.
2. Its progress PR QA passes after GitHub confirms that head SHA has not drifted.
3. GitHub reports that the exact reviewed head was merged by an actor with `is_bot=false`; its observed `baseRefOid` extends the gapless frozen-base merge chain to the recorded `mergeCommit`, and the exact integration head equals the chain tip.

Publication authorization is branch- and unit-scoped. A progress or remediation PR must target the recorded integration branch; it does not authorize changing the delivery base, force-pushing shared history, deleting branches, spending money, approving reviews, or merging.

Each unit PR carries the complete review trail. Builder updates stay on that PR, and every critic round and PR QA result is posted as a comment or linked evidence. A failed critic or QA result leaves the unit unintegrated and returns it to the builder for a changed actual builder strategy; it never becomes a hidden local-only pass. The next round cannot begin until the previous round has a recorded QA failure. In particular, QA or CI failure after a critic pass reopens the unit and requires a new builder update, changed builder strategy, new head SHA, and fresh critic round on the same open PR before QA can pass and a human can merge it.

For every critic round:

1. A builder records the actual strategy for this attempt, changes the real artifact, runs its objective verifier, pushes it to the progress PR, and obtains the current full `headRefOid` from GitHub.
2. A separate critic starts with fresh context containing only the objective, current unit ID and frozen scope, approved bar, relevant constraints, exact head SHA, and actual artifact—not the builder's history, justification, or prior PR comments.
3. The critic uses blind comparison where feasible; otherwise it directly compares the artifact with the reference and checks objective tests and guardrails.
4. The report identifies the exact head SHA and real project-relative artifacts inspected. A passing verdict advances the unit toward PR QA. A failing verdict records the largest remaining gap and critic recommendation; after its QA failure is recorded, the builder must use a different actual strategy for the next attempt on the same unit PR.

Builder and critic identity sets must remain globally disjoint across the Gauntlet, with case-normalized comparison, and every round requires a new critic invocation using a native fresh-context subagent or a fresh isolated session. If OpenCaw cannot obtain an isolated critic, it blocks the Gauntlet instead of accepting self-review. Critics inspect the running product, rendered output, test evidence, finished document, or other real artifact—not a builder-written summary.

Every critic report uses the exact contract documented by the `gauntlet-flow` skill: ordered `Artifact Inspected`, `Bar Comparison`, `Guardrail Results`, `Verdict`, `Largest Remaining Gap`, and `Next Strategy` sections; at least one `- Artifact: <project-relative-file>` entry that is a regular file in the reviewed commit tree; one `- Head SHA: <full-sha>` matching the live PR or integration head; and exactly one `- Verdict: pass|fail|blocked`. Evidence is append-only under:

```text
.ai/gauntlets/<gauntlet-name>/rounds/<item-id>/round-NNN.md
```

PR events are durable under `.ai/gauntlets/<gauntlet-name>/pr-events/<item-id>/event-NNN.md`. Recording `opened`, `qa-pass`, `qa-fail`, `merged`, or `closed` performs a fresh live-GitHub query and persists same-repository identity, PR-body checkpoint, state, draft flag, created/closed/merged times, head/base SHAs, all current fingerprints, target, merge actor and bot flag, and merge commit. Record human merges promptly in integration order so every `baseRefOid` connects the prior chain tip to the new `mergeCommit`; direct integration commits are forbidden. Any retained GitHub timeline event that enabled auto-merge, auto-rebase, auto-squash, or entry into a merge queue invalidates a progress or promotion PR, even if the automation was later disabled. Completion and readiness re-query every terminal PR used for topology or remediation causality rather than trusting mutable local text. For PR events recorded in the same UTC second, append order in the hashed Progress PR Ledger supplies causal order; equal-time records in different ledgers must be joined by an explicit evidence edge rather than lexical path or evidence-type ordering.

Each QA verdict requires a new exact same-PR comment containing `<!-- opencaw-gauntlet-qa:v1 verdict=<pass|fail> head-sha=<sha> source=<canonical-evidence-path> source-sha256=<sha> affected-units=<none|comma-sorted-ids> -->`. The recorder verifies its source hash, reviewed head, verdict, affected set, trusted human collaborator, creation/update timestamps, PR ownership, and uniqueness. Each unit round also binds the opened event and resolved remediation root by path and hash, making the external comment an anchor that cannot be locally reassigned to a different failure. Canonical ledger lines bind one-to-one to file hashes, and mutation commands use an atomic per-Gauntlet lock, compare-and-swap, and no-clobber installation.

Each autonomous Gauntlet execution window lasts at most 45 minutes or two failed full-validation epochs, whichever occurs first. One epoch means evaluating one frozen candidate against the approved verification suite; targeted diagnosis does not reset or enlarge the window. When the budget is exhausted, OpenCaw records the elapsed time and failed-epoch count, persists resumable state, generates a stopped report, sets the Gauntlet to `stopped`, and asks for explicit user reauthorization before starting another build, audit, or validation epoch. Reauthorization starts a new window. Safety, permission, platform policy, and unrecoverable blockers still stop immediately, and this does not authorize unapproved paid services or external actions.

#### Integration and promotion

After every active unit is integrated, OpenCaw proves the fetch and every push identity still match the issue repository and the exact local and remote `gauntlet/<name>` heads are the unique gapless merge-chain tip descended from the frozen base. A rewind, force-push, fork, divergence, chain gap, or unrecorded direct commit fails. A new integration critic then reviews that SHA and aggregate scope. Unit critic/QA failures, integration fail/block evidence, and promotion failures each remain exact externally anchored causal roots until a later merged PR consumes them. Supersession transfers every outstanding ancestor root to every active descendant leaf. The replacement cycle's checkpoint, opened event, round, QA marker, and merge remain hash-linked to that root; old passing merges cannot be reused by manually flipping status.

An integration pass can generate `GAUNTLET_REPORT.md` and an immutable `completion-events/event-NNN.md` entry in the Completion Ledger. The event binds a canonical projection hash of the entire report except the self-referential Immutable Completion Evidence section. Every older completion must be consumed exactly once by a later promotion failure; at most the newest can remain active. An active completion forces passed, PR-eligible, report-present, and unchanged source state even if mutable fields are edited. Readiness rechecks remote identity, all fingerprints, base ancestry, merge topology, live terminal PRs, report projection, source SHA, and that the frozen delivery base is still GitHub's default branch. The promotion PR targets that verified default branch, begins with exact case-sensitive `Closes #<parent-issue>`, and links the ordered unit, remediation, critic, completion, and QA ledgers.

Promotion PR QA is mandatory and each verdict uses a new live same-PR semantic comment. The event binds the promotion PR's observed target `baseRefOid` as a descendant of the frozen base. One later failure may supersede a prior pass for the same completion, PR, and head; a second pass cannot follow that failure on the consumed completion. Failure archives the report, consumes the completion, binds the reviewed source, and names affected units. It is the only path that can reopen completion; direct state edits, rounds, progress events, report demotion, or stale merges are rejected. After causally linked remediation, integration must pass and create a new head and completion event before promotion QA repeats. Historical event heads remain verifiable through immutable comments and fast-forward ancestry, but the current live promotion PR must remain open, non-draft, and unmerged, and its source head plus the remote integration ref must exactly equal the reconstructed local merge-chain tip. Every merge remains human-controlled.

Gauntlet state uses `planning`, `ready`, `running`, `passed`, `stopped`, or `blocked`; work units use `pending`, `building`, `critic-failed`, `passed`, `blocked`, or `superseded`; round verdicts use `pass`, `fail`, or `blocked`. Passed, user-stopped, and blocked runs each produce a `GAUNTLET_REPORT.md`. Stopped and blocked runs preserve their branch and evidence ledger for an explicit resume, but their reports remain incomplete and cannot become promotion-eligible.

Create, validate, record, and report a Gauntlet with:

```bash
./commands/create-gauntlet-file.sh "<gauntlet-name>" "<Gauntlet Title>" --task "<task-name>" --dry-run
./commands/validate-gauntlet.sh "<gauntlet-name-or-path>" --phase ready
bash ./commands/pr-readiness-check.sh --gauntlet-progress "<gauntlet>" "<item-id>" "<validation-summary-file>"
./commands/record-gauntlet-round.sh "<gauntlet>" "<item-id>" "<pass|fail|blocked>" "<builder-id>" "<critic-id>" "<native-subagent|fresh-session>" "<critic-report.md>" --head-sha "<sha>" --builder-strategy "<strategy>" --dry-run
./commands/record-gauntlet-pr-event.sh "<gauntlet>" "<item-id>" "<opened|qa-pass|qa-fail|merged|closed>" "<pr-url>" "<head-branch>" "<evidence-url|none>" --head-sha "<sha>" [--merge-commit "<sha>"] [--dry-run]
./commands/record-gauntlet-promotion-qa.sh "<gauntlet>" "<pass|fail>" "<promotion-pr-url>" "<evidence-url>" --head-sha "<sha>" [--affected-unit "<item-id>"]... [--dry-run]
./commands/comment-pr-qa-results.sh "<pr-url>" "<summary-file>" --gauntlet-verdict "<pass|fail>" --head-sha "<sha>" --gauntlet-source "<project-relative-round-or-completion-event>" [--gauntlet-affected-units "<none|comma-sorted-ids>"]
./commands/create-gauntlet-completion-report.sh "<gauntlet>" --status "<complete|stopped|blocked>" --dry-run
./commands/validate-gauntlet.sh "<gauntlet-name-or-path>" --phase complete
```

The validation summary for `--gauntlet-progress` is optional. After the delivery contract is approved and readiness writes the unit's publication checkpoint, the agent may publish that exact progress PR without another prompt. Copy the emitted checkpoint marker into its body, then record the actual PR and each later QA or merge event; readiness itself never opens or merges a PR.

Use `opened` only after the progress PR is available; the first accepted event freezes the execution contract. Before a critic, fetch/update the local branch and use its exact `headRefOid`. Every QA verdict consumes a new verified `COMMENT_URL`. Fetch integration before `merged`, then record the human merge promptly in target order so its observed `baseRefOid` extends the current chain tip exactly. A PR may close before any critic round or after its latest round has recorded QA, but never with unconsumed critic evidence. Event recording verifies observed state; it never grants merge permission.

Remove `--dry-run` only after reviewing the resolved paths and intended state change. For successful completion, run the completion-report command after ready validation and the passing integration review. It creates the report and immutable completion event, then runs complete validation transactionally; a later explicit `--phase complete` invocation is a recheck, never a prerequisite for report generation. Once every unit is integrated and the fresh integration review passes, a complete `GAUNTLET_REPORT.md` can enter final promotion readiness:

```bash
bash ./commands/pr-readiness-check.sh --gauntlet "<gauntlet-ref>" "<validation-summary-file>"
```

The final validation summary is optional, but `--gauntlet` still requires human approval before publishing the promotion PR to the original delivery base, and that base must still be the repository's current GitHub default branch. Every merge remains human-controlled.

### Method sources

OpenCaw's Gauntlet mode adapts Matt Shumer's [Gauntlet Loop method](https://somethingbig.ai/gauntlet-loop), with the public [Claude of Duty repository and process evidence](https://github.com/mshumer/Claude-of-Duty) as a concrete case study. The user-supplied [Prompt Index guide](https://www.thepromptindex.com/ai-loop-engineering-gauntlet-loop-guide.html) provided supplementary framing. OpenCaw adds its own durable state, approval, issue, validation, and PR/QA policies; it does not embed or reproduce the external prompt.

## Task, Issue, and PR Delivery

Real work is tracked under:

```text
.ai/tasks/TODO.md
.ai/tasks/<task-name>/TASK.md
.ai/tasks/OPEN_ISSUES.md
```

Rules:

- `TODO.md` is the concise ordered checklist.
- Each substantial task has a detailed `TASK.md`.
- Each real task links to a GitHub issue while that issue is open.
- `OPEN_ISSUES.md` stores only open issue URLs, one per line.
- Existing issues can be imported from `#123`, `123`, or a full GitHub issue URL.
- Closed issue URLs are removed from active tracking.

Issue-first request:

```text
Work on #123. Import it, implement the fix, and keep verification evidence linked to the issue and PR.
```

Import directly with:

```bash
./commands/import-task-from-issue.sh "#123"
```

### Normal PR readiness gate

Completing implementation does not automatically authorize publication. Before a normal push or PR, OpenCaw:

1. summarizes the completed scope
2. reports validation evidence and remaining risk
3. creates a durable readiness report
4. asks the user whether the branch is ready to publish

After explicit approval, it commits intentionally, pushes the branch, opens a linked PR, and starts post-PR QA immediately.

PRs for task-backed work include issue linkage such as `Closes #123`. QA results are posted primarily to the PR, with issue links or mirrored evidence when useful. Screenshots are included inline when they are part of browser or visual proof.

## Memory v2

OpenCaw keeps all memory and context inside the resolved host repository:

```text
.ai/SYSTEM_MEMORY.md
.ai/MEMORY.md
.ai/REPO_MAP.md
.ai/RULES.md
.ai/DEBUG.md
.ai/CONTEXT_SUMMARY.md
```

### Memory layers

| File | Purpose |
| --- | --- |
| `SYSTEM_MEMORY.md` | Small, flat, always-loaded protected constraints and verified safe machine capabilities |
| `MEMORY.md` | Tagged project knowledge loaded selectively by relevance |
| `REPO_MAP.md` | Tagged semantic repository structure with a Git-visible path fingerprint |
| `RULES.md` | Project-specific preventive rules and conventions |
| `DEBUG.md` | Reusable debugging evidence and verified resolutions |
| `CONTEXT_SUMMARY.md` | Refreshed high-signal inventory of active state and tags |

Project-memory entries use tags such as:

```text
- [kind:workflow] [area:auth] [tech:dotnet] Run focused authentication tests before the full suite.
```

Each entry has exactly one `kind:` tag and at least one relevance tag such as `area:`, `tech:`, `env:`, `topic:`, or `scope:core`.

Useful commands:

```bash
./commands/query-project-context.sh --list-tags
./commands/query-project-context.sh --tags "area:auth,tech:dotnet"
./commands/append-project-memory.sh --tags "kind:workflow,area:auth" --entry "Run the focused authentication tests first."
./commands/repo-map-status.sh
./commands/clean-context.sh --dry-run
```

OpenCaw proactively records only verified, stable, reusable facts. It does not store secrets, identities, personal paths, guesses, raw logs, or transient task chatter. Replacement and purge workflows archive prior knowledge before removing it.

## Generative Media

OpenCaw supports governed image, music, sound-effect, ambience, and voice workflows while keeping `STYLE.md` authoritative for visual language.

All bundled generative-media assets live under:

```text
.styles/.gpu/
├── INDEX.md
├── CLOUD_SESSION.md
├── COMFYUI_LOCAL.md
├── media-generation-manifest.schema.json
├── model-packs.json
└── toolchain.json
```

The legacy `.media/` directory is prohibited.

Backend choices:

- `CLOUD_SESSION` uses compatible image or audio capabilities exposed by the active assistant session.
- `COMFYUI_LOCAL` uses a pinned, loopback-only ComfyUI toolchain with reviewed model/workflow manifests.

Generate a host contract:

```bash
./commands/generate-media-contract.sh CLOUD_SESSION
./commands/generate-media-contract.sh CLOUD_SESSION COMFYUI_LOCAL
```

Media guardrails include:

- explicit backend selection and no silent fallback
- per-modality capability inspection
- revision-pinned tool and model sources
- license, credential, disk, VRAM, and checksum gates
- non-runtime staging before human review
- reproducibility and provenance manifests
- hashed outputs and workflow receipts
- explicit acceptance, rejection, and promotion state

Local commands:

```bash
./commands/inspect-local-media-host.sh --json
./commands/install-comfyui-local.sh --help
./commands/install-comfyui-models.sh --help
./commands/run-comfyui-workflow.sh --help
./commands/validate-media-generation-manifest.sh --help
```

## Validation

OpenCaw includes integrated validators for roles, skills, commands, styles, role bindings, language/tool alignment, memory, Gauntlet lifecycles, Windows bootstrap behavior, and generative-media assets.

Run the complete suite:

```bash
./commands/validate-opencaw.sh
```

Common focused validators:

```bash
./commands/validate-roles.sh
./commands/validate-skills.sh
./commands/validate-commands.sh
./commands/validate-skill-safety.sh
./commands/validate-role-skill-map.sh
./commands/validate-styles.sh
./commands/validate-media-templates.sh
./commands/validate-readme.sh
./commands/validate-memory.sh
./tests/test-gauntlet-flow.sh
```

The integrated suite verifies, among other things:

- role and skill schema compliance
- matching skill interface metadata
- unsafe paths, credentials, links, hidden mutations, and publishing behavior
- complete domain-qualified role mappings
- agreement between canonical JSON and generated role-map Markdown
- command syntax and executable requirements
- style catalog and contract structure
- pinned media toolchains, model packs, workflows, checksums, and manifests
- Memory v2 isolation, tagged writes, replacement, migration, retrieval, purge, cleanup, and map freshness
- Brainstorm path isolation, sticky lifecycle state, branch/element validation, summary hashing, graph rendering, and delivery-creation guards
- Gauntlet scaffold isolation, real commit/ref and live-GitHub binding, fresh-critic evidence, one-to-one hash ledgers, transactional progress events, authorized remediation, human-merge integration, and final promotion gates
- Windows provider classification and explicit-install behavior

Verification for host-project work remains proportional to the task: targeted tests first, broader suites when risk warrants them, and browser/log/artifact evidence where behavior cannot be proven by unit tests alone.

## Repository Layout

```text
OpenCaw/
├── AGENTS.md                         # shared behavior contract
├── README.md
├── BRAINSTORM.md                     # optional persistent pre-planning ideas and active state
├── BRAINSTORM_SUMMARY.md             # optional generated hash-bound idea index
├── ARCHITECTURE.md                   # architecture contract for this repository
├── STYLE.md                          # visual-style contract for this repository
├── .architecture/                    # reusable architecture templates
├── .roles/                           # domain roles, aliases, and capability maps
├── .styles/                          # style templates
│   └── .gpu/                         # all generative-media assets
├── skills/                           # reusable reasoning workflows
├── commands/                         # deterministic scripts
├── assets/                           # reusable test/report assets
├── tests/                            # OpenCaw validation suites and fixtures
└── .ai/                              # repository-local memory, tasks, goals, and Gauntlet round/PR evidence
```

Bundled Playwright assets include configuration, package-script, report, and CLI-reference templates under `assets/playwright/` and `assets/playwright-cli/`. Host repositories continue to own their actual application tests, credentials, runtime artifacts, and generated reports.

---

# Contributing

Contributions are welcome.

Typical flow:

1. Fork the repository.
2. Create a focused branch.
3. Implement the improvement.
4. Run the relevant focused checks and `./commands/validate-opencaw.sh`.
5. Review the diff and readiness evidence.
6. Push and open a linked pull request after the required human confirmation.
7. Run post-PR QA and attach the evidence to the PR.

Example:

```bash
git clone https://github.com/<your-org>/OpenCaw
cd OpenCaw
git checkout -b feature/add-architecture-framework
```

After making changes:

```bash
./commands/validate-opencaw.sh
git add <intended-files>
git commit -m "feat(architecture): add framework"
```

When contributing:

- keep changes small enough to review
- preserve the layering boundary between the shared baseline and host-project `.ai` state
- keep architecture, role, skill, style, and command schemas valid
- add regression coverage for workflow fixes
- avoid hidden dependency installation or external mutations
- include issue linkage and post-PR QA evidence

---

# License

OpenCaw is released under the MIT License. See `LICENSE` for the full terms.
