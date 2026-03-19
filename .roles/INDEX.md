# Roles Index

OpenCaw role catalog with categories and common aliases.

## Categories

### Architecture & Design
- `autonomous-optimization-architect`
- `backend-architect`
- `software-architect`

### Backend & APIs
- `rapid-prototyper`

### Frontend & UX
- `frontend-developer`
- `mobile-app-builder`

### Security & Reliability
- `security-engineer`
- `sre`

### Data & Platform
- `ai-data-remediation-engineer`
- `data-engineer`
- `database-optimizer`
- `devops-automator`

### General Engineering
- `ai-engineer`
- `code-reviewer`
- `embedded-firmware-engineer`
- `git-workflow-master`
- `incident-response-commander`
- `senior-developer`
- `solidity-smart-contract-engineer`
- `technical-writer`
- `threat-detection-engineer`

## Aliases

The following aliases may be used when requesting a role. Prefer exact role names when possible.

- `ai-data-remediation-engineer`: `ai`, `ai data remediation engineer`, `ai-data-remediation-engineer`, `aidataremediationengineer`, `analytics`, `data`, `llm`, `ml`
- `ai-engineer`: `ai`, `ai engineer`, `ai-engineer`, `aiengineer`, `llm`, `ml`
- `autonomous-optimization-architect`: `architect`, `autonomous optimization architect`, `autonomous-optimization-architect`, `autonomousoptimizationarchitect`
- `backend-architect`: `api`, `api-architect`, `architect`, `backend`, `backend architect`, `backend-architect`, `backendarchitect`
- `code-reviewer`: `code reviewer`, `code-reviewer`, `codereviewer`
- `data-engineer`: `analytics`, `data`, `data engineer`, `data-engineer`, `dataengineer`
- `database-optimizer`: `analytics`, `data`, `database optimizer`, `database-optimizer`, `databaseoptimizer`
- `devops-automator`: `ci-cd`, `cicd`, `devops`, `devops automator`, `devops-automator`, `devopsautomator`, `platform`
- `embedded-firmware-engineer`: `embedded firmware engineer`, `embedded-firmware-engineer`, `embeddedfirmwareengineer`
- `frontend-developer`: `frontend`, `frontend developer`, `frontend-developer`, `frontenddeveloper`, `ui`, `web`
- `git-workflow-master`: `git workflow master`, `git-workflow-master`, `gitworkflowmaster`
- `incident-response-commander`: `incident response commander`, `incident-response-commander`, `incidentresponsecommander`
- `mobile-app-builder`: `mobile app builder`, `mobile-app-builder`, `mobileappbuilder`
- `rapid-prototyper`: `rapid prototyper`, `rapid-prototyper`, `rapidprototyper`
- `security-engineer`: `appsec`, `secure-coding`, `security`, `security engineer`, `security-engineer`, `securityengineer`
- `senior-developer`: `senior developer`, `senior-developer`, `seniordeveloper`
- `software-architect`: `architect`, `software architect`, `software-architect`, `softwarearchitect`
- `solidity-smart-contract-engineer`: `solidity smart contract engineer`, `solidity-smart-contract-engineer`, `soliditysmartcontractengineer`
- `sre`: `ops`, `reliability`, `site-reliability-engineer`, `sre`
- `technical-writer`: `technical writer`, `technical-writer`, `technicalwriter`
- `threat-detection-engineer`: `threat detection engineer`, `threat-detection-engineer`, `threatdetectionengineer`

## Multi-role examples

- `use role backend-architect + security-engineer`
- `use roles frontend-developer + qa-engineer`
- `act as sre + backend-architect`

When multiple roles are requested, combine them in the order given unless the user specifies a priority.

## Default skill and command bindings

OpenCaw also defines default skill and command bindings for common engineering roles.
See:

- `./.roles/ROLE_SKILL_MAP.md`
- `./.roles/ROLE_SKILL_MAP.json`

These bindings are used to bias skill and command selection after a role is activated.
