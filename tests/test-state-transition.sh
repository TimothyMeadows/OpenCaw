#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_parent="$repo_root/.hephaera/.cache/tasks/hephaera-rename/evidence"
mkdir -p "$fixture_parent"
fixtures="$(mktemp -d "$fixture_parent/state-transition-shell-XXXXXX")"
cleanup() {
  local resolved
  resolved="$(cd "$fixtures" && pwd -P)"
  [[ "$resolved" == "$fixture_parent"/state-transition-shell-* ]] || { echo 'Unsafe shell fixture cleanup target.' >&2; return 1; }
  rm -rf -- "$resolved"
}
trap cleanup EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
reject() { if "$@" > "$fixtures/rejected.log" 2>&1; then fail 'State operation unexpectedly succeeded.'; fi; }
source "$repo_root/commands/lib/state-transition-common.sh"
fresh="$fixtures/fresh";mkdir -p "$fresh"
hephaera_transition_assert_production_allowed "$fresh"
hephaera_transition_assert_bootstrap_allowed "$fresh"
[[ ! -e "$fresh/.hephaera" ]] || fail 'Pure discovery created state.'

legacy="$fixtures/legacy";mkdir -p "$legacy/.opencaw/.cache"
printf 'retained bytes\n' > "$legacy/.opencaw/.cache/sentinel"
reject hephaera_transition_assert_production_allowed "$legacy" generation
[[ "$(cat "$legacy/.opencaw/.cache/sentinel")" == 'retained bytes' ]] || fail 'Legacy bytes changed.'
mv -- "$legacy/.opencaw" "$legacy/retained-history"
mkdir -p "$legacy/.hephaera/.cache"
printf 'malformed marker remains a fence\n' > "$legacy/.hephaera/.cache/STATE_TRANSITION.json"
reject hephaera_transition_assert_production_allowed "$legacy" generation

copy_runtime() {
  local destination="$1"
  mkdir -p "$destination/commands/lib"
  cp "$repo_root/commands/lib/memory-common.sh" "$repo_root/commands/lib/platform-common.sh" "$repo_root/commands/lib/state-transition-common.sh" "$destination/commands/lib/"
  cp "$repo_root/commands/create-host-ai-scaffold.sh" "$destination/commands/"
  printf '# Controlled baseline\n' > "$destination/AGENTS.md"
}
project="$fixtures/host";mkdir -p "$project";copy_runtime "$project/.hephaera"
printf '# Custom host\n<!-- OPENCAW_BOOTSTRAP_START -->\nOld directive.\n<!-- OPENCAW_BOOTSTRAP_END -->\n' > "$project/AGENTS.md"
cp "$project/AGENTS.md" "$fixtures/original-agents.md"
reject env -u HEPHAERA_PROJECT_ROOT bash "$project/.hephaera/commands/create-host-ai-scaffold.sh"
cmp "$project/AGENTS.md" "$fixtures/original-agents.md" || fail 'Old managed bootstrap was rewritten.'
[[ ! -e "$project/.hephaera/.cache" ]] || fail 'Rejected bootstrap created new state.'
printf '# Custom host\nKeep these notes.\n' > "$project/AGENTS.md"
env -u HEPHAERA_PROJECT_ROOT bash "$project/.hephaera/commands/create-host-ai-scaffold.sh" > "$fixtures/fresh-scaffold.log"
grep -Fq 'HEPHAERA_BOOTSTRAP_START' "$project/AGENTS.md" || fail 'Fresh bootstrap missing.'
grep -Fq 'Keep these notes.' "$project/AGENTS.md" || fail 'Custom host notes lost.'
[[ -f "$project/.hephaera/.cache/SYSTEM_MEMORY.md" ]] || fail 'Fresh canonical memory missing.'

unprepared="$fixtures/unprepared";mkdir -p "$unprepared/.opencaw/.cache";copy_runtime "$unprepared/.hephaera"
printf '# Host notes\n' > "$unprepared/AGENTS.md"
reject env -u HEPHAERA_PROJECT_ROOT bash "$unprepared/.hephaera/commands/create-host-ai-scaffold.sh"
[[ ! -e "$unprepared/.hephaera/.cache" ]] || fail 'Unprepared legacy host silently initialized a second cache.'
python3 -B -X utf8 "$repo_root/commands/lib/state_transition.py" prepare --root "$unprepared" > "$fixtures/prepared.json"
env -u HEPHAERA_PROJECT_ROOT bash "$unprepared/.hephaera/commands/create-host-ai-scaffold.sh" > "$fixtures/prepared-scaffold.log"
[[ -f "$unprepared/.hephaera/.cache/SYSTEM_MEMORY.md" ]] || fail 'Prepared local maintenance unavailable.'
reject hephaera_transition_assert_production_allowed "$unprepared" generation
echo 'State transition shell: fresh discovery/scaffold, persistent fence, explicit preparation, legacy bootstrap pre-write refusal and byte preservation passed.'
