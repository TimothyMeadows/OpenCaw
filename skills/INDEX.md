# Skills Catalog

Curated reusable skills included in OpenCaw.

## Task And Governance

- `create-host-ai-scaffold` - Ensure host-repository `.ai` scaffolding and OpenCaw bootstrap wiring are in place.
- `create-task-file` - Create a detailed task folder and TASK.md, then create/link a matching GitHub issue and track it.
- `goal-flow` - Manage explicitly requested automated goals across task completion, automatic PR creation, post-PR QA, branch chaining, and final human approval reporting.
- `manage-task-issues` - Maintain one GitHub issue per task and keep only open issue URLs in tracking.
- `update-todo-checklist` - Maintain concise numbered TODO checklist state for active tasks.
- `archive-task-note` - Archive task notes into long-term context storage.
- `pr-readiness-gate` - Stop before push/PR creation, summarize readiness, and ask for human PR approval.
- `link-pr-to-task-issue` - Ensure PR bodies include issue-closing linkage.
- `post-pr-qa` - Run post-PR QA and post PR comments with pass/fail evidence and inline screenshot links.
- `comment-issue-test-results` - Post QA/Playwright outcomes and artifacts to linked issue threads.
- `audit-untrusted-agent-source` - Statically inspect agent-facing source for unsafe instructions, executables, credentials, path escapes, and hidden side effects.
- `adapt-external-agent-skills` - Reimplement approved capability intent as an independently authored OpenCaw skill.
- `verify-and-explain` - Produce evidence-backed conclusions with explicit scope, limitations, and reproduction steps.
- `audit-reference-originality` - Compare local subject and reference material for mechanical similarity evidence without making legal conclusions.

## Memory And Context

- `clean-context` - Compact context artifacts and refresh high-signal summaries.
- `maintain-memory` - Proactively retrieve, validate, record, replace, migrate, and purge scoped Memory v2 entries.
- `maintain-repository-map` - Keep the tagged semantic repository map current using a Git-visible project-path fingerprint.
- `record-correction-pattern` - Capture user corrections as memory + preventive rules.
- `record-debug-resolution` - Capture reusable bug diagnosis/resolution notes.
- `repo-map-dotnet` - Add .NET-specific structure to the canonical semantic repository map.

## .NET Delivery

- `solution-restore` - Restore solution dependencies.
- `solution-build` - Build solution with standard repository conventions.
- `test-dotnet` - Run .NET tests with appropriate scope.
- `format-dotnet` - Run .NET formatting workflow.
- `clean-rebuild-dotnet` - Perform clean rebuild workflow for .NET solutions.
- `upgrade-dotnet-runtime` - Upgrade .NET runtime/framework with verification.
- `dependency-audit-dotnet` - Audit .NET dependencies for risk and upgrade path.
- `issue-to-plan-dotnet` - Convert an issue into an actionable .NET implementation plan.
- `branch-name-suggester` - Generate structured branch naming suggestions.
- `git-commit-dotnet` - Produce conventional commit message and commit changes when explicitly requested.

## Architecture And Integration

- `generate-architecture` - Generate `ARCHITECTURE.md` from selected templates.
- `generate-style` - Generate `STYLE.md` from selected art style templates.
- `apim-change-review` - Review Azure API Management changes for compatibility and risk.
- `azure-settings-checklist` - Validate required Azure app settings and environment assumptions.
- `function-app-checklist` - Validate Function App operational and deployment expectations.
- `servicebus-checklist` - Validate Service Bus configuration and integration assumptions.
- `storage-checklist` - Validate storage configuration and data-safety assumptions.

## Data Platforms

- `install-database-cli-tools` - Install or preview install commands for CLI clients across supported database engines.
- `database-cli-query` - Run engine-specific database CLI connect/query workflows and capture deterministic command usage.

## QA And UI Verification

- `playwright-e2e-tests` - Design or run Playwright end-to-end verification.
- `playwright-browser-discovery` - Discover live UI selectors, fields, and conditional behavior before authoring tests.
- `playwright-test-refinement` - Diagnose, rerun, and stabilize Playwright tests.
- `playwright-reporting` - Generate non-interactive Playwright evidence reports from JSON results and artifacts.

## Visual Research And Production

- `capture-ui-reference-pack` - Capture authorized interface evidence with provenance, state, viewport, and observation notes.
- `derive-visual-spec-from-video` - Convert authorized video evidence into implementable visual and temporal constraints.
- `extract-interaction-patterns` - Describe reusable interaction state machines without reproducing distinctive expression.
- `develop-original-brand-directions` - Develop multiple original visual directions from product constraints.
- `prototype-from-reference-pack` - Build a bounded original prototype from documented observations and host requirements.
- `capture-full-page-evidence` - Produce repeatable full-page browser evidence with explicit viewport and motion settings.
- `produce-browser-demo` - Assemble reviewed local frames into a deterministic browser-demo artifact.
- `profile-application-performance` - Measure representative application performance against host-defined budgets.
- `source-licensed-visual-assets` - Evaluate asset candidates using provenance, license, fit, and production risk.
- `design-ui-from-constraints` - Derive interface hierarchy, states, tokens, and acceptance criteria from explicit constraints.

## Web Experience

- `design-web-experiences` - Design original responsive web systems with accessible enhancement paths.
- `design-conversion-pages` - Design clear conversion journeys without coercive patterns or hidden mutations.
- `build-accessible-motion-systems` - Define motion semantics, comfort controls, and equivalent reduced-motion states.
- `build-interactive-web-effects` - Add bounded effects that support comprehension and degrade safely.
- `build-webgl-experiences` - Build progressively enhanced 3D browser scenes with fallback and resource budgets.
- `optimize-web-motion` - Diagnose and reduce animation cost using measured evidence.

## Game Development

- `author-game-worlds` - Define coherent playable worlds, rules, regions, encounters, and content constraints.
- `design-action-gameplay` - Specify responsive actions, counterplay, timing, feedback, and tuning hypotheses.
- `build-gameplay-runtime` - Implement deterministic gameplay state and presentation boundaries.
- `build-game-production-tools` - Create reversible, validated content tools with preview and rollback paths.
- `plan-hybrid-game-assets` - Plan coherent asset pipelines across runtime-native, rendered, and generated media.
- `create-game-vfx` - Design readable effect families with timing, accessibility, and runtime budgets.
- `optimize-web-games` - Profile and improve browser-game frame time, memory, loading, and asset churn.
- `test-playable-games` - Run structured functional, experiential, accessibility, and performance playtests.
- `ship-web-games` - Assemble evidence and release gates for a web game without automatic publication.

## Art Production

- `maintain-art-style-contract` - Maintain, generate, or validate `STYLE.md` against selected `.styles` templates.
- `review-isometric-production` - Review isometric art for projection, anchors, depth sorting, occlusion, and gameplay readability.
- `prepare-game-art-handoff` - Prepare game art assets for engine/runtime handoff with metadata and validation checks.
- `create-game-art-sheets` - Plan tilesets, environment sheets, prop atlases, and directional animation sheets.
- `tcg-art-direction` - Plan original TCG/CCG card frames, board styling, tokens/minions, hand/deck/graveyard zones, VFX, and IP-safe fantasy card-game art direction.
- `iterate-art-to-sanity` - Iterate generated art until sanity checks pass.
- `enforce-art-language-safety` - Enforce language and visual safety constraints for generated art.
