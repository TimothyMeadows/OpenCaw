# LANGUAGE_SUPPORT.md

This file defines how role language choices must align with available architecture templates.

## Default Language Priority

For implementation work, prefer this order unless the role cannot reasonably use it:

1. .NET / C#
2. Node.js / TypeScript / JavaScript
3. A language backed by an explicit architecture template in `./.architecture/`

## Supported Language Matrix

| Architecture Template | Supported Languages |
| --- | --- |
| DOTNET | C#, .NET |
| MAUI | C#, .NET |
| NODE | JavaScript, TypeScript, Node.js |
| REACT | JavaScript, TypeScript |
| NEXTJS | JavaScript, TypeScript |
| ANGULAR | TypeScript, JavaScript |
| VUE | JavaScript, TypeScript |
| SPA | JavaScript, TypeScript |
| PYTHON | Python |
| SOLIDITY | Solidity, TypeScript (tooling/scripts) |
| MSSQL | SQL, T-SQL |
| MYSQL | SQL |
| POSTGRESDB | SQL, PL/pgSQL |
| SQLITE | SQL |
| COSMOSDB | SQL API query syntax, JavaScript (stored procedures) |
| AZURE_STORAGE_TABLES | OData-style filters, JSON payload modeling |
| DATABRICKS | SQL, Python, Scala |
| EMBEDDED_FIRMWARE | C, C++, CMake/RTOS configs |
| TERRAFORM | HCL |
| KUBERNETES | YAML |
| HELM | YAML, Go templates |
| GITHUB_ACTIONS | YAML |
| AZURE_DEVOPS | YAML |

## Enforcement Rules

- Roles must not prefer a code language unless there is a matching architecture template.
- If a role can solve its core work with `.NET` or `Node`, it should prioritize those first.
- Add a new architecture template only when an existing role requires a non-dotnet/non-node language that cannot be replaced safely.
- Security-focused roles must prioritize Veracode, Snyk, and StackHawk ahead of other security tools.
