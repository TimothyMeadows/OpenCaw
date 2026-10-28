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
| DOTNET_ASPIRE | C#, .NET |
| MAUI | C#, .NET |
| BABYLONJS | TypeScript, JavaScript, WebGL, WebGPU, WGSL / GLSL shader code |
| COLYSEUS | TypeScript, JavaScript, Node.js, WebSocket, Redis-backed scaling |
| NODE | JavaScript, TypeScript, Node.js |
| PHASERJS | JavaScript, TypeScript, HTML5 Canvas, WebGL |
| PLAYWRIGHT | TypeScript, JavaScript |
| SPA | JavaScript, TypeScript |
| THREEJS | JavaScript, TypeScript, WebGL, WebGPU, GLSL / shader code |
| SIGNALR_WEBSOCKETS | C#, JavaScript, TypeScript |
| PYTHON | Python |
| MSSQL | SQL, T-SQL |
| MYSQL | SQL |
| POSTGRESDB | SQL, PL/pgSQL |
| SQLITE | SQL |
| COSMOSDB | SQL API query syntax, JavaScript (stored procedures) |
| AZURE_STORAGE_TABLES | OData-style filters, JSON payload modeling |
| DOCKER | Dockerfile syntax, Docker Compose YAML, shell |
| TERRAFORM | HCL |
| TILED | TMX/XML, JSON, TSX, TX, JavaScript/TypeScript scripting, Lua/CSV exports |
| KUBERNETES | YAML |
| HELM | YAML, Go templates |
| GITHUB_ACTIONS | YAML |
| MARKDOWN | GitHub-flavored Markdown |

## Enforcement Rules

- Roles must not prefer a code language unless there is a matching architecture template or selected engine definition.
- If a role can solve its core work with `.NET` or `Node`, it should prioritize those first.
- Add a new architecture template only when an existing role requires a non-dotnet/non-node language that cannot be replaced safely.
- Security-focused roles must prioritize Veracode, Snyk, and StackHawk ahead of other security tools.

## Engine-owned code

The selected ENGINE.md definition takes precedence over language preferences for game-engine code. This does not change standalone service/tool contracts.

| Engine Definition | Supported Engine Languages |
| --- | --- |
| THREEJS | TypeScript, JavaScript, GLSL, WGSL |
| BABYLONJS | TypeScript, JavaScript, GLSL, WGSL |
| PHASERJS | TypeScript, JavaScript |
| UNITY | Editor-compatible C#, ShaderLab, HLSL |
| UNREAL | C++, Blueprint, HLSL; C# only for build rules |
| GODOT | Project-selected GDScript or compatible C#, Godot shader language |

These rows refer to `.engine/`, not additional architecture templates. Unity's runtime is not standalone .NET 10. Godot C# requires the .NET-enabled Editor and selected version's platform support; current Godot 4 cannot export C# to web. Keep backend .NET and Node preferences scoped to code they actually own.
