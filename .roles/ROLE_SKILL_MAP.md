# Role Skill Map

This file maps common OpenCaw roles to their default skills and preferred commands.

Role casting should use this map to bias skill and command selection after a role is activated.

Mapping key resolution:
- prefer domain-qualified keys such as `computer-science/backend-architect` when present
- fallback to unqualified keys such as `backend-architect` for backward compatibility

## Shared capabilities

These skills and commands apply to all roles:

### Skills
- `plan-task`
- `update-memory`
- `debug-issue`
- `review-code`
- `refactor-code`
- `verify-changes`

### Commands
- `commands/run-tests.sh`
- `commands/lint.sh`
- `commands/format.sh`

## Role mappings

### backend-architect
Skills:
- `design-system-architecture`
- `review-architecture`
- `define-service-boundaries`
- `generate-clean-architecture`
- `evaluate-scalability`
- `dependency-audit`

Commands:
- `commands/generate-architecture.sh`
- `commands/solution-structure.sh`
- `commands/dependency-graph.sh`
- `commands/validate-architecture.sh`

### backend-developer
Skills:
- `implement-endpoint`
- `generate-mediatr-handler`
- `create-domain-entity`
- `write-unit-tests`
- `refactor-service`
- `optimize-query`

Commands:
- `commands/dotnet-build.sh`
- `commands/dotnet-test.sh`
- `commands/add-endpoint.sh`
- `commands/run-local-api.sh`

### frontend-developer
Skills:
- `generate-component`
- `create-feature-module`
- `state-management-setup`
- `optimize-rendering`
- `ui-refactor`
- `accessibility-review`

Commands:
- `commands/npm-install.sh`
- `commands/npm-build.sh`
- `commands/npm-test.sh`
- `commands/dev-server.sh`

### security-engineer
Skills:
- `threat-model-analysis`
- `security-audit`
- `identify-vulnerabilities`
- `secure-api-review`
- `dependency-vulnerability-scan`
- `auth-flow-review`

Commands:
- `commands/security-scan.sh`
- `commands/dependency-check.sh`
- `commands/secret-scan.sh`
- `commands/audit-logs.sh`

### qa-engineer
Skills:
- `generate-test-cases`
- `write-integration-tests`
- `playwright-e2e-tests`
- `test-gap-analysis`
- `regression-suite-update`

Commands:
- `commands/run-tests.sh`
- `commands/run-e2e.sh`
- `commands/generate-test-report.sh`

### code-migrator
Skills:
- `framework-migration-plan`
- `upgrade-dotnet-runtime`
- `dependency-audit-dotnet`
- `test-gap-analysis`
- `regression-suite-update`

Commands:
- `commands/dotnet-list-outdated-packages.sh`
- `commands/dotnet-upgrade-assistant.sh`
- `commands/dotnet-restore.sh`
- `commands/dotnet-build.sh`
- `commands/dotnet-test.sh`

### devops-engineer
Skills:
- `create-ci-pipeline`
- `optimize-pipeline`
- `infrastructure-review`
- `deployment-strategy`
- `artifact-flow-design`

Commands:
- `commands/deploy.sh`
- `commands/build-artifact.sh`
- `commands/pipeline-validate.sh`
- `commands/release.sh`

### sre
Skills:
- `incident-analysis`
- `define-slo-sla`
- `performance-analysis`
- `failure-mode-analysis`
- `resilience-design`

Commands:
- `commands/check-health.sh`
- `commands/metrics-dump.sh`
- `commands/logs-tail.sh`
- `commands/load-test.sh`

### platform-engineer
Skills:
- `internal-tooling-design`
- `developer-experience-review`
- `platform-standardization`
- `infra-abstraction-design`

Commands:
- `commands/bootstrap-project.sh`
- `commands/generate-template.sh`
- `commands/validate-platform.sh`

### ai-engineer
Skills:
- `prompt-engineering`
- `model-selection`
- `embedding-design`
- `rag-pipeline-design`
- `inference-optimization`

Commands:
- `commands/run-inference.sh`
- `commands/train-model.sh`
- `commands/convert-model.sh`
- `commands/evaluate-model.sh`

### data-engineer
Skills:
- `pipeline-design`
- `etl-optimization`
- `data-modeling`
- `schema-validation`
- `data-quality-analysis`

Commands:
- `commands/run-etl.sh`
- `commands/validate-schema.sh`
- `commands/data-migration.sh`

### fullstack-engineer
Skills:
- `feature-end-to-end`
- `api-ui-integration`
- `full-flow-testing`
- `cross-layer-debugging`

Commands:
- `commands/full-build.sh`
- `commands/dev-all.sh`
- `commands/test-all.sh`
