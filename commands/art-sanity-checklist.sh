#!/usr/bin/env bash
set -euo pipefail

required_language="${1:-english}"
required_language="$(printf '%s' "$required_language" | tr '[:upper:]' '[:lower:]')"

cat <<EOF
Art sanity checklist template
-----------------------------
Use one report per generated image candidate.

expected_language=${required_language}
hands_ok=true
text_double_letters_ok=true
text_language=${required_language}
nudity_ok=true
graphic_violence_ok=true
notes=
EOF

echo
echo "Fail the candidate if any _ok field is not true."
echo "Default text language is English unless user override is provided."
