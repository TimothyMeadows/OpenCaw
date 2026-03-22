# Skills Catalog

Common reusable skills included in OpenCaw by category.

## Shared

- `plan-task` - Create or refine an implementation plan and keep task sequencing clear.
- `manage-task-issues` - Create/sync one GitHub issue per task and keep only open issue URLs in task tracking.
- `update-memory` - Capture durable lessons in project-local memory files.
- `clean-context` - Compress active context by archiving completed detail and refreshing a high-signal summary.
- `debug-issue` - Diagnose an issue using logs, errors, tests, and observable evidence.
- `review-code` - Review changes for correctness, maintainability, and alignment with architecture.
- `refactor-code` - Improve structure while preserving behavior.
- `verify-changes` - Prove that changes work using tests, logs, or browser verification.
- `link-pr-to-task-issue` - Ensure PRs include explicit closing linkage to the task issue.

## Architecture

- `design-system-architecture` - Design or evolve overall system architecture with explicit boundaries and tradeoffs.
- `review-architecture` - Review architecture against current requirements and constraints.
- `define-service-boundaries` - Define service, module, or bounded-context boundaries.
- `generate-clean-architecture` - Generate a clean architecture plan aligned with the active ARCHITECTURE.md.
- `evaluate-scalability` - Assess scalability, performance bottlenecks, and growth constraints.
- `dependency-audit` - Review dependencies for layering, coupling, and maintainability risks.

## Backend

- `implement-endpoint` - Implement a backend endpoint with proper contracts, orchestration, and tests.
- `generate-mediatr-handler` - Create or update a MediatR command/query handler workflow.
- `create-domain-entity` - Create or revise a domain entity with explicit invariants and behavior.
- `write-unit-tests` - Add or improve focused unit tests.
- `refactor-service` - Refactor a backend service or application workflow.
- `optimize-query` - Improve data access or query efficiency safely.

## Migration

- `framework-migration-plan` - Define a phased migration strategy from legacy frameworks/runtimes to modern supported versions.
- `upgrade-dotnet-runtime` - Execute .NET runtime/framework upgrades with verification-focused follow-through.

## Frontend

- `generate-component` - Create or revise a frontend component with clear boundaries and responsibilities.
- `create-feature-module` - Create or revise a feature-oriented frontend module.
- `state-management-setup` - Establish explicit frontend state ownership and flow.
- `optimize-rendering` - Improve rendering performance and reduce unnecessary UI work.
- `ui-refactor` - Refactor UI code for clarity, reuse, and maintainability.
- `accessibility-review` - Review UI for accessibility issues and improvements.

## Security

- `threat-model-analysis` - Analyze threats, abuse paths, and trust boundaries.
- `security-audit` - Audit code and configuration for security concerns.
- `identify-vulnerabilities` - Identify likely vulnerabilities and attack surfaces.
- `secure-api-review` - Review API surface for authn/authz, input handling, and data exposure issues.
- `dependency-vulnerability-scan` - Review dependencies for known vulnerabilities and upgrade risks.
- `auth-flow-review` - Review authentication and authorization flows.

## Qa

- `generate-test-cases` - Generate useful test cases for changed or risky behavior.
- `write-integration-tests` - Add or improve integration tests.
- `playwright-e2e-tests` - Design or write Playwright end-to-end checks.
- `comment-issue-test-results` - Post QA test outcomes and screenshot evidence to the task issue thread.
- `test-gap-analysis` - Identify missing tests and coverage gaps.
- `regression-suite-update` - Update regression coverage for recent fixes or changes.

## Devops

- `create-ci-pipeline` - Create or structure CI pipeline definitions.
- `optimize-pipeline` - Improve pipeline speed, clarity, or promotion flow.
- `infrastructure-review` - Review infrastructure or deployment definitions for maintainability and safety.
- `deployment-strategy` - Define or refine deployment and promotion strategy.
- `artifact-flow-design` - Define artifact build, storage, and promotion flow.

## Sre

- `incident-analysis` - Analyze an incident using evidence and operational signals.
- `define-slo-sla` - Define or refine SLO/SLA/SLI expectations.
- `performance-analysis` - Assess performance behavior and likely bottlenecks.
- `failure-mode-analysis` - Analyze likely failure modes and mitigation paths.
- `resilience-design` - Design resilience improvements and operational safeguards.

## Platform

- `internal-tooling-design` - Design internal developer tooling and workflows.
- `developer-experience-review` - Review friction points in developer workflow and setup.
- `platform-standardization` - Standardize templates, tooling, or conventions across repositories.
- `infra-abstraction-design` - Design abstractions around infrastructure or platform capabilities.

## Ai

- `prompt-engineering` - Design or refine prompts and agent instruction structure.
- `model-selection` - Evaluate and choose a model/runtime for a task.
- `embedding-design` - Design embedding strategy and vectorization approach.
- `rag-pipeline-design` - Design retrieval-augmented generation workflows.
- `inference-optimization` - Optimize inference behavior, cost, or latency.

## Data

- `pipeline-design` - Design a data or ETL pipeline with explicit contracts and stages.
- `etl-optimization` - Optimize ETL flow, throughput, or operational clarity.
- `data-modeling` - Define or refine data model structure and ownership.
- `schema-validation` - Validate schema compatibility and contract alignment.
- `data-quality-analysis` - Assess data quality risks and detection strategy.

## Fullstack

- `feature-end-to-end` - Implement or plan a feature across backend and frontend boundaries.
- `api-ui-integration` - Wire API and UI layers together cleanly.
- `full-flow-testing` - Define or run verification for the full product flow.
- `cross-layer-debugging` - Debug behavior that crosses multiple layers or services.
