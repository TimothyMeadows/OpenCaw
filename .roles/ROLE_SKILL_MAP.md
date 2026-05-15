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
- `enforce-art-language-safety`

Commands:
- `commands/print-css-art-token-template.sh`
- `commands/validate-svg-assets.sh`

### arts/generative-art-designer
Skills:
- `iterate-art-to-sanity`
- `enforce-art-language-safety`

Commands:
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
- `playwright-e2e-tests`
- `playwright-browser-discovery`
- `playwright-test-refinement`
- `playwright-reporting`
- `post-pr-qa`
- `comment-issue-test-results`
- `test-dotnet`

Commands:
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
- `manage-task-issues`
- `pr-readiness-gate`
- `post-pr-qa`
- `clean-context`

Commands:
- `commands/create-task-file.sh`
- `commands/create-task-issue.sh`
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
- `solution-build`
- `test-dotnet`

Commands:
- `commands/generate-architecture.sh`
- `commands/dotnet-build.sh`
- `commands/dotnet-test.sh`

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
