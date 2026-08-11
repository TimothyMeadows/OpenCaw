# External asset library validation

## Result

PASS for the feature and every directly affected subsystem.

## Passing evidence

- `bash tests/test-external-asset-library.sh`
- `bash tests/test-art-pipelines.sh`
- `bash tests/test-blender-art-capabilities.sh`
- `bash tests/test-generative-media.sh`
- `bash tests/test-selected-capability-import.sh`
- `bash commands/validate-skills.sh`
- `bash commands/validate-commands.sh`
- `bash commands/validate-role-skill-map.sh`
- `bash commands/validate-role-language-alignment.sh`
- `bash commands/generate-role-skill-map.sh --check`
- `bash commands/validate-styles.sh`
- `bash commands/validate-style-contract.sh STYLE.md`
- `bash commands/validate-readme.sh`
- `bash commands/validate-memory.sh`
- `bash commands/repo-map-status.sh`
- `python C:/Users/timot/.codex/skills/.system/skill-creator/scripts/quick_validate.py skills/use-external-asset-library`
- `node --check commands/lib/external-asset-library.js`
- Bash syntax checks for every added or changed external-library command and test
- `git diff --check`

The feature test proves optional generation, preservation/replacement/clearing, absolute POSIX/Windows/UNC syntax, malformed-contract rejection, metadata-only inventory, symbolic-link rejection, deterministic file and bundle copying, source immutability, copied-file hashes, overwrite refusal, project/evidence confinement, and source/project non-overlap.

## Umbrella-suite note

`bash commands/validate-opencaw.sh` was allowed to run for 15 minutes. It reached the pre-existing `tests/test-gauntlet-flow.sh` fixture without emitting a failing assertion, then the command timeout stopped it. The resulting umbrella status is inconclusive, not a pass. Its remaining wrapper processes and `/tmp/opencaw-gauntlet.*` fixture directory were removed. All focused suites for this feature and every changed subsystem passed independently.

ShellCheck was not installed in the current environment; Bash syntax and repository command validators passed.
