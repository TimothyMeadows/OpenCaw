# Role Skill Map

This file maps OpenCaw roles to curated default skills and preferred commands.

Mapping key resolution:
- prefer domain-qualified keys such as `arts/css-vector-artist` when present
- fallback to unqualified keys such as `qa-engineer` for backward compatibility

## Shared capabilities

These skills and commands apply to all roles.

### Skills
- `create-task-file`
- `manage-task-issues`
- `clean-context`
- `pr-readiness-gate`
- `link-pr-to-task-issue`
- `post-pr-qa`
- `record-correction-pattern`
- `record-debug-resolution`

### Commands
- `commands/create-task-file.sh`
- `commands/create-task-issue.sh`
- `commands/import-task-from-issue.sh`
- `commands/sync-task-issues.sh`
- `commands/pr-readiness-check.sh`
- `commands/link-pr-to-task-issue.sh`
- `commands/comment-pr-qa-results.sh`
- `commands/update-todo-checklist.sh`

## Role mappings

### arts/css-vector-artist
Skills:
- `maintain-art-style-contract`
- `prepare-game-art-handoff`
- `enforce-art-language-safety`

Commands:
- `commands/validate-style-contract.sh`
- `commands/print-game-art-handoff-template.sh`
- `commands/print-css-art-token-template.sh`
- `commands/validate-svg-assets.sh`

### arts/cutout-rig-animator
Skills:
- `maintain-art-style-contract`
- `create-game-art-sheets`
- `prepare-game-art-handoff`
- `iterate-art-to-sanity`
- `enforce-art-language-safety`

Commands:
- `commands/validate-style-contract.sh`
- `commands/inspect-animation-sheet-folder.sh`
- `commands/print-directional-animation-sheet-template.sh`
- `commands/print-game-art-handoff-template.sh`
- `commands/art-sanity-checklist.sh`
- `commands/validate-art-sanity-report.sh`

### arts/flat-minimalist-game-artist
Skills:
- `maintain-art-style-contract`
- `prepare-game-art-handoff`
- `iterate-art-to-sanity`
- `enforce-art-language-safety`

Commands:
- `commands/validate-style-contract.sh`
- `commands/print-game-art-handoff-template.sh`
- `commands/art-sanity-checklist.sh`
- `commands/validate-art-sanity-report.sh`

### arts/game-vfx-artist
Skills:
- `maintain-art-style-contract`
- `review-isometric-production`
- `create-game-art-sheets`
- `prepare-game-art-handoff`
- `iterate-art-to-sanity`
- `enforce-art-language-safety`

Commands:
- `commands/validate-style-contract.sh`
- `commands/print-isometric-production-checklist.sh`
- `commands/inspect-animation-sheet-folder.sh`
- `commands/print-directional-animation-sheet-template.sh`
- `commands/print-game-art-handoff-template.sh`
- `commands/art-sanity-checklist.sh`
- `commands/validate-art-sanity-report.sh`

### arts/generative-art-designer
Skills:
- `maintain-art-style-contract`
- `prepare-game-art-handoff`
- `iterate-art-to-sanity`
- `enforce-art-language-safety`

Commands:
- `commands/validate-style-contract.sh`
- `commands/print-game-art-handoff-template.sh`
- `commands/art-sanity-checklist.sh`
- `commands/validate-art-sanity-report.sh`

### arts/illustrative-2d-artist
Skills:
- `maintain-art-style-contract`
- `create-game-art-sheets`
- `prepare-game-art-handoff`
- `iterate-art-to-sanity`
- `enforce-art-language-safety`

Commands:
- `commands/validate-style-contract.sh`
- `commands/inspect-animation-sheet-folder.sh`
- `commands/print-directional-animation-sheet-template.sh`
- `commands/print-game-art-handoff-template.sh`
- `commands/art-sanity-checklist.sh`
- `commands/validate-art-sanity-report.sh`

### arts/isometric-2-5d-art-director
Skills:
- `maintain-art-style-contract`
- `review-isometric-production`
- `create-game-art-sheets`
- `prepare-game-art-handoff`
- `iterate-art-to-sanity`
- `enforce-art-language-safety`

Commands:
- `commands/validate-style-contract.sh`
- `commands/print-isometric-production-checklist.sh`
- `commands/inspect-animation-sheet-folder.sh`
- `commands/print-tileset-sheet-template.sh`
- `commands/print-directional-animation-sheet-template.sh`
- `commands/print-game-art-handoff-template.sh`
- `commands/art-sanity-checklist.sh`
- `commands/validate-art-sanity-report.sh`

### arts/isometric-2-5d-environment-artist
Skills:
- `maintain-art-style-contract`
- `review-isometric-production`
- `create-game-art-sheets`
- `prepare-game-art-handoff`
- `iterate-art-to-sanity`
- `enforce-art-language-safety`

Commands:
- `commands/validate-style-contract.sh`
- `commands/print-isometric-production-checklist.sh`
- `commands/print-tileset-sheet-template.sh`
- `commands/print-game-art-handoff-template.sh`
- `commands/art-sanity-checklist.sh`
- `commands/validate-art-sanity-report.sh`

### arts/parallax-background-artist
Skills:
- `maintain-art-style-contract`
- `prepare-game-art-handoff`
- `iterate-art-to-sanity`
- `enforce-art-language-safety`

Commands:
- `commands/validate-style-contract.sh`
- `commands/print-game-art-handoff-template.sh`
- `commands/art-sanity-checklist.sh`
- `commands/validate-art-sanity-report.sh`

### arts/pixel-artist
Skills:
- `maintain-art-style-contract`
- `review-isometric-production`
- `create-game-art-sheets`
- `prepare-game-art-handoff`
- `iterate-art-to-sanity`
- `enforce-art-language-safety`

Commands:
- `commands/validate-style-contract.sh`
- `commands/print-isometric-production-checklist.sh`
- `commands/inspect-animation-sheet-folder.sh`
- `commands/print-directional-animation-sheet-template.sh`
- `commands/print-game-art-handoff-template.sh`
- `commands/art-sanity-checklist.sh`
- `commands/validate-art-sanity-report.sh`

### arts/pre-rendered-2-5d-artist
Skills:
- `maintain-art-style-contract`
- `review-isometric-production`
- `create-game-art-sheets`
- `prepare-game-art-handoff`
- `iterate-art-to-sanity`
- `enforce-art-language-safety`

Commands:
- `commands/validate-style-contract.sh`
- `commands/print-isometric-production-checklist.sh`
- `commands/inspect-animation-sheet-folder.sh`
- `commands/print-tileset-sheet-template.sh`
- `commands/print-directional-animation-sheet-template.sh`
- `commands/print-game-art-handoff-template.sh`
- `commands/art-sanity-checklist.sh`
- `commands/validate-art-sanity-report.sh`

### arts/tile-set-artist
Skills:
- `maintain-art-style-contract`
- `review-isometric-production`
- `create-game-art-sheets`
- `prepare-game-art-handoff`
- `iterate-art-to-sanity`
- `enforce-art-language-safety`

Commands:
- `commands/validate-style-contract.sh`
- `commands/print-isometric-production-checklist.sh`
- `commands/print-tileset-sheet-template.sh`
- `commands/print-game-art-handoff-template.sh`
- `commands/art-sanity-checklist.sh`
- `commands/validate-art-sanity-report.sh`

### code-migrator
Skills:
- `dependency-audit-dotnet`
- `upgrade-dotnet-runtime`
- `test-dotnet`
- `format-dotnet`
- `clean-rebuild-dotnet`

Commands:
- `commands/dotnet-list-outdated-packages.sh`
- `commands/dotnet-upgrade-assistant.sh`
- `commands/dotnet-restore.sh`
- `commands/dotnet-build.sh`
- `commands/dotnet-test.sh`
- `commands/dotnet-format.sh`
- `commands/dotnet-clean-rebuild.sh`

### qa-engineer
Skills:
- `maintain-art-style-contract`
- `review-isometric-production`
- `prepare-game-art-handoff`
- `playwright-e2e-tests`
- `playwright-browser-discovery`
- `playwright-test-refinement`
- `playwright-reporting`
- `post-pr-qa`
- `comment-issue-test-results`
- `test-dotnet`

Commands:
- `commands/validate-style-contract.sh`
- `commands/print-isometric-production-checklist.sh`
- `commands/print-game-art-handoff-template.sh`
- `commands/inspect-animation-sheet-folder.sh`
- `commands/playwright-install.sh`
- `commands/playwright-test.sh`
- `commands/playwright-show-report.sh`
- `commands/playwright-report-summary.sh`
- `commands/playwright-artifact-index.sh`
- `commands/playwright-discovery-report.sh`
- `commands/playwright-evidence-report.sh`
- `commands/dotnet-test.sh`
- `commands/comment-pr-qa-results.sh`
- `commands/comment-issue-test-results.sh`

### computer-science/project-manager
Skills:
- `create-task-file`
- `goal-flow`
- `manage-task-issues`
- `orchestrate-subagents`
- `pr-readiness-gate`
- `post-pr-qa`
- `clean-context`

Commands:
- `commands/create-goal-file.sh`
- `commands/create-goal-completion-report.sh`
- `commands/create-task-file.sh`
- `commands/create-task-issue.sh`
- `commands/create-subagent-plan.sh`
- `commands/validate-subagent-plan.sh`
- `commands/record-subagent-result.sh`
- `commands/import-task-from-issue.sh`
- `commands/sync-task-issues.sh`
- `commands/update-todo-checklist.sh`
- `commands/pr-readiness-check.sh`
- `commands/comment-pr-qa-results.sh`

### senior-developer
Skills:
- `solution-restore`
- `solution-build`
- `test-dotnet`
- `format-dotnet`

Commands:
- `commands/dotnet-restore.sh`
- `commands/dotnet-build.sh`
- `commands/dotnet-test.sh`
- `commands/dotnet-format.sh`

### fullstack-engineer
Skills:
- `generate-architecture`
- `maintain-art-style-contract`
- `prepare-game-art-handoff`
- `solution-build`
- `test-dotnet`

Commands:
- `commands/generate-architecture.sh`
- `commands/validate-style-contract.sh`
- `commands/print-game-art-handoff-template.sh`
- `commands/inspect-animation-sheet-folder.sh`
- `commands/dotnet-build.sh`
- `commands/dotnet-test.sh`

### computer-science/frontend-developer
Skills:
- `maintain-art-style-contract`
- `prepare-game-art-handoff`

Commands:
- `commands/validate-style-contract.sh`
- `commands/print-game-art-handoff-template.sh`
- `commands/inspect-animation-sheet-folder.sh`
- `commands/validate-svg-assets.sh`

### computer-science/game-designer
Skills:
- `maintain-art-style-contract`
- `review-isometric-production`
- `create-task-file`
- `manage-task-issues`

Commands:
- `commands/validate-style-contract.sh`
- `commands/print-isometric-production-checklist.sh`
- `commands/create-task-file.sh`
- `commands/update-todo-checklist.sh`

### devops-automator
Skills:
- `generate-architecture`
- `create-host-ai-scaffold`

Commands:
- `commands/generate-architecture.sh`
- `commands/create-host-ai-scaffold.sh`

### data-engineer
Skills:
- `install-database-cli-tools`
- `database-cli-query`
- `generate-architecture`

Commands:
- `commands/install-database-cli-tools.sh`
- `commands/database-cli-query.sh`
- `commands/generate-architecture.sh`

### database-optimizer
Skills:
- `install-database-cli-tools`
- `database-cli-query`

Commands:
- `commands/install-database-cli-tools.sh`
- `commands/database-cli-query.sh`

### security-engineer
Skills:
- `apim-change-review`

Commands:
- `commands/veracode-scan.sh`
- `commands/snyk-scan.sh`
- `commands/stackhawk-scan.sh`
- `commands/security-scan.sh`
- `commands/dependency-check.sh`

### threat-detection-engineer
Skills:
- `apim-change-review`

Commands:
- `commands/veracode-scan.sh`
- `commands/snyk-scan.sh`
- `commands/stackhawk-scan.sh`
- `commands/security-scan.sh`
