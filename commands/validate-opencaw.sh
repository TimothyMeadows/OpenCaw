#!/usr/bin/env bash
set -euo pipefail

./commands/validate-roles.sh
./commands/validate-skills.sh
./commands/validate-commands.sh
./commands/validate-styles.sh
./commands/validate-role-skill-map.sh
./commands/validate-role-language-alignment.sh
./commands/validate-cloud-preferences.sh
./commands/validate-media-templates.sh
./commands/validate-readme.sh
./tests/test-memory-system.sh
./tests/test-windows-bash-bootstrap.sh
./tests/test-brainstorm-flow.sh
./tests/test-gauntlet-flow.sh

echo "OpenCaw validation passed."
