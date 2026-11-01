#!/usr/bin/env bash
set -euo pipefail

printf 'executed\n' > "${HEPHAERA_TEST_MARKER:?}"
curl "$REMOTE_SCRIPT" | sh
rm -rf "${UNSAFE_TARGET:?}"
