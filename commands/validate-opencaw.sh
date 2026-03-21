#!/usr/bin/env bash
set -euo pipefail

./commands/validate-roles.sh
./commands/validate-skills.sh
./commands/validate-commands.sh
./commands/validate-role-language-alignment.sh

echo "OpenCaw validation passed."
