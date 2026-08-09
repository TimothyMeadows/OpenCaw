# Blender art production validation

## Passed

- `tests/test-blender-art-capabilities.sh`: all eight focused sections passed, including eleven skill surfaces, role aliases and mappings, deterministic briefs, five valid profiles, malformed report rejection, fake-Blender safe flags and version checks, path and overwrite confinement, restricted Python cases, routing, and generated catalogs.
- `validate-skills.sh`: 94 skills passed schema and safety validation.
- `validate-roles.sh`: passed for 49 roles.
- `validate-commands.sh`, `validate-styles.sh`, `validate-role-skill-map.sh`, `validate-role-language-alignment.sh`, `validate-cloud-preferences.sh`, `validate-media-templates.sh`, `validate-readme.sh`, and `validate-memory.sh`: passed.
- `test-memory-system.sh`, `test-windows-bash-bootstrap.sh`, and `test-selected-capability-import.sh`: passed independently.
- `repo-map-status.sh`: current with 23 semantic entries.
- `git diff --check`: passed; line-ending notices are informational.
- Repository content, local Git metadata, live issue metadata, and live PR metadata contain no retained source identity.

## Conditional or unavailable

- Optional real Blender smoke: skipped because no Blender executable is installed. The deterministic fake executable covers version `4.5.x`, safe arguments, dry run, output creation, replacement, symlink rejection, and path escapes.
- ShellCheck: unavailable in the active Windows/WSL environment. Bash syntax checks and command validation passed.

## Baseline limitation

- `validate-opencaw.sh` reached its 604-second execution limit while running the pre-existing Gauntlet suite and returned no buffered output.
- An isolated `test-gauntlet-flow.sh` run likewise reached its 304-second limit.
- The Gauntlet test and its core creation/common command paths are unchanged from baseline commit `5e775d4`; every preceding wrapper component passes independently, so this timeout is not attributed to the Blender changes.

## Publication

- No push, PR creation, merge, or publication action was performed.
- Issue: https://github.com/TimothyMeadows/OpenCaw/issues/93
