# Roles Index

OpenCaw role catalog with categories and common aliases.

Current role catalog location:

- `./.roles/computer-science/<role-name>/ROLE.md`
- `./.roles/arts/<role-name>/ROLE.md`

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

### Arts & Visual Design
- `css-vector-artist`

### Full Stack
- `fullstack-engineer`

### Quality & Testing
- `qa-engineer`

### Migration & Modernization
- `code-migrator`

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
Alias entries use domain-qualified role ids so collisions can be disambiguated when needed.

- `computer-science/ai-data-remediation-engineer`: `ai`, `ai data remediation engineer`, `ai-data-remediation-engineer`, `aidataremediationengineer`, `analytics`, `data`, `llm`, `ml`
- `computer-science/ai-engineer`: `ai`, `ai engineer`, `ai-engineer`, `aiengineer`, `llm`, `ml`
- `computer-science/autonomous-optimization-architect`: `architect`, `autonomous optimization architect`, `autonomous-optimization-architect`, `autonomousoptimizationarchitect`
- `computer-science/backend-architect`: `api`, `api-architect`, `architect`, `backend`, `backend architect`, `backend-architect`, `backendarchitect`
- `computer-science/code-migrator`: `code migrator`, `code-migrator`, `codemigrator`, `migration-engineer`, `modernization-engineer`
- `computer-science/code-reviewer`: `code reviewer`, `code-reviewer`, `codereviewer`
- `arts/css-vector-artist`: `css-vector-artist`, `css-vector`, `interface-vector-artist`, `logo-vector-artist`, `vector-ui-artist`
- `computer-science/data-engineer`: `analytics`, `data`, `data engineer`, `data-engineer`, `dataengineer`
- `computer-science/database-optimizer`: `analytics`, `data`, `database optimizer`, `database-optimizer`, `databaseoptimizer`
- `computer-science/devops-automator`: `ci-cd`, `cicd`, `devops`, `devops automator`, `devops-automator`, `devopsautomator`, `platform`
- `computer-science/embedded-firmware-engineer`: `embedded firmware engineer`, `embedded-firmware-engineer`, `embeddedfirmwareengineer`
- `computer-science/frontend-developer`: `frontend`, `frontend developer`, `frontend-developer`, `frontenddeveloper`, `ui`, `web`
- `computer-science/fullstack-engineer`: `full stack`, `full-stack`, `fullstack`, `fullstack engineer`, `fullstack-engineer`, `fullstackengineer`
- `computer-science/git-workflow-master`: `git workflow master`, `git-workflow-master`, `gitworkflowmaster`
- `computer-science/incident-response-commander`: `incident response commander`, `incident-response-commander`, `incidentresponsecommander`
- `computer-science/mobile-app-builder`: `mobile app builder`, `mobile-app-builder`, `mobileappbuilder`
- `computer-science/qa-engineer`: `qa`, `qa engineer`, `qa-engineer`, `quality assurance`, `quality engineer`, `quality-engineer`, `test engineer`, `test-engineer`
- `computer-science/rapid-prototyper`: `rapid prototyper`, `rapid-prototyper`, `rapidprototyper`
- `computer-science/security-engineer`: `appsec`, `secure-coding`, `security`, `security engineer`, `security-engineer`, `securityengineer`
- `computer-science/senior-developer`: `senior developer`, `senior-developer`, `seniordeveloper`
- `computer-science/software-architect`: `architect`, `software architect`, `software-architect`, `softwarearchitect`
- `computer-science/solidity-smart-contract-engineer`: `solidity smart contract engineer`, `solidity-smart-contract-engineer`, `soliditysmartcontractengineer`
- `computer-science/sre`: `ops`, `reliability`, `site-reliability-engineer`, `sre`
- `computer-science/technical-writer`: `technical writer`, `technical-writer`, `technicalwriter`
- `computer-science/threat-detection-engineer`: `threat detection engineer`, `threat-detection-engineer`, `threatdetectionengineer`

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

