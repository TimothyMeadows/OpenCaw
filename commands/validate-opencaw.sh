#!/usr/bin/env bash
set -euo pipefail

exclude_gauntlet=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --exclude-gauntlet) exclude_gauntlet=1; shift ;;
    -h|--help)
      echo 'Usage: ./commands/validate-opencaw.sh [--exclude-gauntlet]'
      echo 'Runs all integrated checks by default; --exclude-gauntlet omits only the monolithic Gauntlet regression.'
      exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

./tests/test-opencaw-layout.sh
./tests/test-cache-workflows.sh
./tests/test-runtime-cache-layout.sh
./commands/validate-engines.sh
./tests/test-engine-selection.sh
./tests/test-unreal-capabilities.sh
./tests/test-unity-capabilities.sh
./tests/test-unity-service-contracts.sh
./tests/test-native-engine-fixtures.sh
./tests/test-gameplay-profiles.sh
./commands/validate-roles.sh
./commands/validate-skills.sh
./commands/validate-commands.sh
./commands/validate-styles.sh
./commands/validate-role-skill-map.sh
./commands/validate-role-language-alignment.sh
./commands/validate-cloud-preferences.sh
./commands/validate-art-pipelines.sh
./commands/validate-media-templates.sh
./commands/validate-readme.sh
./tests/test-memory-system.sh
./tests/test-windows-bash-bootstrap.sh
./tests/test-brainstorm-flow.sh
./tests/test-task-execution.sh
./tests/test-selected-capability-import.sh
bash ./tests/test-game-template-catalog.sh
./tests/test-art-pipelines.sh
bash ./tests/test-proof-to-model.sh
python_bin=''
for candidate in python python3 python.exe; do
  if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import sys; assert sys.version_info >= (3, 10)' >/dev/null 2>&1; then
    python_bin="$candidate"
    break
  fi
done
[[ -n "$python_bin" ]] || { echo 'Python 3.10+ is required for native proof-to-model integration checks.' >&2; exit 1; }
"$python_bin" tests/test-proof-model-blender.py
"$python_bin" tests/test-proof-model-native-integration.py
bash ./tests/test-model-to-animation.sh
"$python_bin" tests/test-model-animation-blender.py
"$python_bin" tests/test-model-animation-native-integration.py
bash ./tests/test-model-to-action.sh
"$python_bin" tests/test-model-action-blender.py
"$python_bin" tests/test-model-action-native-integration.py
./tests/test-code-character-contract.sh
./tests/test-code-character-skills.sh
./tests/test-code-character-evidence.sh
./tests/test-code-character-integration.sh
./tests/test-blender-art-capabilities.sh
./tests/test-external-asset-library.sh
if [[ $exclude_gauntlet -eq 0 ]]; then
  ./tests/test-gauntlet-flow.sh
else
  echo 'Excluded tests/test-gauntlet-flow.sh (--exclude-gauntlet).'
fi

echo "OpenCaw validation passed."
