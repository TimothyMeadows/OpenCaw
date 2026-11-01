#!/usr/bin/env bash
set -euo pipefail

# Bounded storage regression: no GitHub publication or Gauntlet lifecycle replay.
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temp_root="$(mktemp -d "${TMPDIR:-/tmp}/hephaera-cache-workflows.XXXXXX")"
cleanup() {
  case "$temp_root" in "${TMPDIR:-/tmp}"/hephaera-cache-workflows.*) rm -rf -- "$temp_root" ;; esac
}
trap cleanup EXIT
project="$temp_root/project"
cache="$project/.hephaera/.cache"
mkdir -p "$cache/tasks/demo" "$project/.ai/tasks/legacy" "$project/.ai/goals/legacy"
fail() { echo "FAIL: $*" >&2; exit 1; }
expect_failure() {
  if "$@" >"$temp_root/rejection.log" 2>&1; then fail "unexpected success: $*"; fi
}
run_command() {
  local command="$1"
  shift
  HEPHAERA_PROJECT_ROOT="$project" bash "$repo_root/commands/$command" "$@"
}
cat >"$cache/tasks/demo/TASK.md" <<'EOF'
# Cache workflow fixture
## Goal
Verify durable delivery state uses the fixed cache.
## Issue
## Review
Synthetic fixture only; no product acceptance is claimed.
EOF
printf '%s\n' '# Legacy task stays untouched' >"$project/.ai/tasks/legacy/TASK.md"
printf '%s\n' '# Legacy goal stays untouched' >"$project/.ai/goals/legacy/GOAL.md"
old_hash="$(sha256sum "$project/.ai/tasks/legacy/TASK.md")"

echo '[1/6] task and subagent state stays under the resolved cache'
run_command create-subagent-plan.sh demo 1 >/dev/null
[[ -f "$cache/tasks/demo/SUBAGENTS.md" ]] || fail 'subagent plan escaped the cache'
printf '%s\n' 'Synthetic lane evidence.' >"$temp_root/lane.txt"
run_command record-subagent-result.sh demo lane-1 complete "$temp_root/lane.txt" >/dev/null
grep -Fq 'Synthetic lane evidence.' "$cache/tasks/demo/SUBAGENTS.md" || fail 'lane evidence was not recorded'
expect_failure run_command create-subagent-plan.sh ../../escaped 1
expect_failure run_command record-subagent-result.sh ../../escaped lane-1 complete "$temp_root/lane.txt"
expect_failure run_command validate-subagent-plan.sh "$project/.ai/tasks/legacy/TASK.md"
[[ ! -e "$project/escaped" ]] || fail 'task traversal wrote outside the cache'

echo '[2/6] Goal references resolve only from canonical cache storage'
run_command create-goal-file.sh demo 'Storage fixture' >/dev/null
run_command create-goal-completion-report.sh .hephaera/.cache/goals/demo/GOAL.md >/dev/null
[[ -f "$cache/goals/demo/GOAL_REPORT.md" ]] || fail 'Goal report escaped the cache'
expect_failure run_command create-goal-completion-report.sh "$project/.ai/goals/legacy/GOAL.md"
[[ ! -e "$project/.ai/goals/legacy/GOAL_REPORT.md" ]] || fail 'legacy Goal storage was reused'

echo '[3/6] Gauntlet storage and task evidence use canonical project-relative paths'
run_command create-gauntlet-file.sh demo 'Storage fixture' --task demo >/dev/null
gauntlet_file="$cache/gauntlets/demo/GAUNTLET.md"
[[ -f "$gauntlet_file" ]] || fail 'Gauntlet escaped the cache'
grep -Fq '.hephaera/.cache/tasks/demo/TASK.md' "$gauntlet_file" || fail 'Gauntlet task reference uses the wrong storage root'
(
  export HEPHAERA_PROJECT_ROOT="$project"
  source "$repo_root/commands/lib/gauntlet-common.sh"
  [[ "$(gauntlet_resolve_file demo)" == "$gauntlet_file" ]] || fail 'Gauntlet name did not resolve in the cache'
  expect_failure gauntlet_resolve_file "$project/.ai/gauntlets/demo/GAUNTLET.md"
)

echo '[4/6] archival accepts canonical relative references and rejects legacy/outside paths'
run_command archive-task-context.sh .hephaera/.cache/tasks/demo/TASK.md >/dev/null
grep -q '^Archived on ' "$cache/tasks/demo/TASK.md" || fail 'canonical task reference was not archived'
[[ -n "$(find "$cache/archive/tasks" -name 'demo-*.md' -print -quit)" ]] || fail 'task evidence was not retained in the cache archive'
expect_failure run_command archive-task-context.sh "$project/.ai/tasks/legacy/TASK.md"
[[ "$(sha256sum "$project/.ai/tasks/legacy/TASK.md")" == "$old_hash" ]] || fail 'legacy task was modified'
outside_task="$temp_root/other-project/.hephaera/.cache/tasks/demo/TASK.md"
mkdir -p "$(dirname "$outside_task")"
printf '%s\n' 'Another project owns this task.' >"$outside_task"
expect_failure run_command archive-task-context.sh "$outside_task"
grep -Fqx 'Another project owns this task.' "$outside_task" || fail 'another project task was modified'
expect_failure run_command archive-task-note.sh "$temp_root/lane.txt" ../../outside.txt

echo '[5/6] report defaults derive the host root when invoked inside the install folder'
mkdir -p "$project/test-results" "$project/.playwright-cli"
printf '%s\n' '{"suites":[]}' >"$project/test-results/results.json"
printf '%s\n' 'Page URL: https://example.test/game' >"$project/.playwright-cli/page.yaml"
(
  cd "$project/.hephaera"
  run_command playwright-evidence-report.sh >"$temp_root/reports.log"
)
[[ -n "$(find "$cache/reports" -name 'playwright-test-run-*.md' -print -quit)" ]] || fail 'Playwright summary did not use the host cache'
[[ -n "$(find "$cache/reports" -name 'playwright-discovery-*.md' -print -quit)" ]] || fail 'Playwright discovery did not use the host cache'
[[ ! -e "$project/.hephaera/.hephaera" ]] || fail 'report invocation nested an install/cache under the mount'

echo '[6/6] workflow child symlinks cannot redirect durable state'
mkdir -p "$temp_root/outside"
if ln -s "$temp_root/outside" "$cache/tasks/linked" 2>/dev/null && [[ -L "$cache/tasks/linked" ]]; then
  expect_failure run_command create-subagent-plan.sh linked 1
  [[ ! -e "$temp_root/outside/SUBAGENTS.md" ]] || fail 'subagent plan followed a storage symlink'
  ln -s "$temp_root/outside" "$cache/goals/linked"
  expect_failure run_command create-goal-file.sh linked
  [[ ! -e "$temp_root/outside/GOAL.md" ]] || fail 'Goal creation followed a storage symlink'
else
  echo 'SKIP: host could not create a symbolic link for child-storage confinement.'
fi
echo 'Cache workflow storage regression passed (task/Goal/Gauntlet/archive/report paths; no legacy fallback).'
