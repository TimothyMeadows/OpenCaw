#!/usr/bin/env bash
set -euo pipefail

commands_dir="./commands"
schema_file="./commands/SCHEMA.md"

if [[ ! -d "$commands_dir" ]]; then
  echo "Missing commands directory: $commands_dir" >&2
  exit 1
fi

if [[ ! -f "$schema_file" ]]; then
  echo "Missing commands schema: $schema_file" >&2
  exit 1
fi

status=0

while IFS= read -r -d '' cmd; do
  name="$(basename "$cmd")"

  if [[ ! "$name" =~ ^[a-z0-9]+(-[a-z0-9]+)*\.sh$ ]]; then
    echo "Invalid command name: $name" >&2
    status=1
  fi

  if [[ ! -x "$cmd" ]]; then
    echo "Command is not executable: $cmd" >&2
    status=1
  fi

  first_nonempty_line="$(sed -e 's/\r$//' -e '/^[[:space:]]*$/d' "$cmd" | head -n1 || true)"
  first_nonempty_line_trimmed="$(printf '%s' "$first_nonempty_line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  if [[ "$first_nonempty_line_trimmed" != "#!/usr/bin/env bash" ]]; then
    echo "Missing bash shebang in $cmd" >&2
    status=1
  fi

  if ! grep -Eq '^[[:space:]]*set -euo pipefail[[:space:]]*$' "$cmd"; then
    echo "Missing strict mode in $cmd" >&2
    status=1
  fi

done < <(find "$commands_dir" -maxdepth 1 -type f -name "*.sh" -print0)

if [[ $status -eq 0 ]]; then
  echo "Commands validation passed."
fi

exit $status
