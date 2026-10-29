#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/validate-art-sanity-report.sh "<report_file>" [expected_language]
EOF
}

report_file="${1:-}"
expected_language="${2:-english}"

if [[ -z "$report_file" ]]; then
  usage >&2
  exit 1
fi

if [[ ! -f "$report_file" ]]; then
  echo "Report file not found: $report_file" >&2
  exit 1
fi

normalize() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
}

get_value() {
  local key="$1"
  local line value
  line="$(grep -Ei "^${key}=" "$report_file" | tail -n1 || true)"
  value="${line#*=}"
  normalize "$value"
}

expected_language="$(normalize "$expected_language")"
hands_ok="$(get_value 'hands_ok')"
text_double_letters_ok="$(get_value 'text_double_letters_ok')"
text_language="$(get_value 'text_language')"
nudity_ok="$(get_value 'nudity_ok')"
graphic_violence_ok="$(get_value 'graphic_violence_ok')"

status=0

check_true() {
  local field="$1"
  local value="$2"
  if [[ "$value" != "true" ]]; then
    echo "FAIL: $field must be true (found: $value)" >&2
    status=1
  fi
}

check_true "hands_ok" "$hands_ok"
check_true "text_double_letters_ok" "$text_double_letters_ok"
check_true "nudity_ok" "$nudity_ok"
check_true "graphic_violence_ok" "$graphic_violence_ok"

if [[ -z "$text_language" ]]; then
  echo "FAIL: text_language is missing." >&2
  status=1
elif [[ "$text_language" != "$expected_language" ]]; then
  echo "FAIL: text_language mismatch (expected: $expected_language, found: $text_language)" >&2
  status=1
fi

if [[ $status -ne 0 ]]; then
  echo "Art sanity report validation failed." >&2
  exit 1
fi

echo "Art sanity report validation passed."
echo "Language: $text_language"
echo "Rules: no extra hands, no duplicated text artifacts, no nudity, no graphic violence"
