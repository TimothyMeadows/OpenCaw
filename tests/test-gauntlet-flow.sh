#!/usr/bin/env bash
# shellcheck disable=SC2016 # Markdown backticks are intentional literal fixture content.
set -euo pipefail
export LC_ALL=C
export LANG=C

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

temp_root="$(mktemp -d "${TMPDIR:-/tmp}/opencaw-gauntlet.XXXXXX")"
network_marker="$temp_root/network-command-used"
cleanup() {
  case "$temp_root" in
    */opencaw-gauntlet.*) rm -rf -- "$temp_root" ;;
  esac
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

expect_failure() {
  local output_file="$1"
  shift
  set +e
  "$@" >"$output_file" 2>&1
  local result=$?
  set -e
  [[ $result -ne 0 ]] || fail "command unexpectedly succeeded: $*"
}

expect_file() {
  [[ -f "$1" ]] || fail "expected file was not created: $1"
}

expect_line() {
  local expected="$1"
  local file="$2"
  awk -v expected="$expected" '{ sub(/\r$/, ""); if ($0 == expected) found=1 } END { exit !found }' "$file" \
    || fail "expected line was not found in $file: $expected"
}

replace_line() {
  local file="$1"
  local before="$2"
  local after="$3"
  local temporary="$file.replace"
  awk -v before="$before" -v after="$after" '
    { sub(/\r$/, "") }
    $0 == before { print after; replaced=1; next }
    { print }
    END { if (!replaced) exit 42 }
  ' "$file" >"$temporary" || {
    rm -f -- "$temporary"
    fail "fixture line was not found in $file: $before"
  }
  mv "$temporary" "$file"
}

replace_matching_line() {
  local file="$1"
  local pattern="$2"
  local after="$3"
  local temporary="$file.replace"
  awk -v pattern="$pattern" -v after="$after" '
    { sub(/\r$/, "") }
    $0 ~ pattern { print after; replaced=1; next }
    { print }
    END { if (!replaced) exit 42 }
  ' "$file" >"$temporary" || {
    rm -f -- "$temporary"
    fail "fixture pattern was not found in $file: $pattern"
  }
  mv "$temporary" "$file"
}

insert_after_matching_line() {
  local file="$1"
  local pattern="$2"
  local inserted_line="$3"
  local temporary="$file.insert"
  awk -v pattern="$pattern" -v inserted="$inserted_line" '
    { print }
    $0 ~ pattern { print inserted; matched=1 }
    END { if (!matched) exit 42 }
  ' "$file" >"$temporary" || {
    rm -f -- "$temporary"
    fail "fixture insertion pattern was not found in $file: $pattern"
  }
  mv "$temporary" "$file"
}

replace_all_literal() {
  local file="$1"
  local before="$2"
  local after="$3"
  local temporary="$file.replace"
  local line
  : >"$temporary"
  while IFS= read -r line || [[ -n "$line" ]]; do
    printf '%s\n' "${line//$before/$after}" >>"$temporary"
  done <"$file"
  mv "$temporary" "$file"
}

round_file_count() {
  local gauntlet="$1"
  if [[ ! -d "$gauntlet/rounds" ]]; then
    echo 0
    return
  fi
  find "$gauntlet/rounds" -type f -name 'round-*.md' | wc -l | tr -d ' '
}

convert_to_crlf() {
  local file="$1"
  local temporary="$file.crlf"
  awk '{ sub(/\r$/, ""); printf "%s\r\n", $0 }' "$file" >"$temporary"
  mv "$temporary" "$file"
}

new_project() {
  local name="$1"
  local project="$temp_root/$name"
  mkdir -p "$project"
  git -C "$project" init -q
  git -C "$project" config user.name 'OpenCaw Gauntlet Test'
  git -C "$project" config user.email 'opencaw-gauntlet@example.invalid'
  printf 'inspectable fixture artifact\n' >"$project/artifact.txt"
  git -C "$project" add artifact.txt
  git -C "$project" commit -qm 'test: initialize fixture'
  printf '%s\n' "$project"
}

run_for() {
  local project="$1"
  shift
  OPENCAW_PROJECT_ROOT="$project" "$@"
}

write_parent_task() {
  local project="$1"
  local task_name="$2"
  local issue_number="$3"
  mkdir -p "$project/.ai/tasks/$task_name"
  cat >"$project/.ai/tasks/$task_name/TASK.md" <<EOF
# Gauntlet parent fixture

## Goal

Exercise the Gauntlet lifecycle against local fixture evidence.

## Scope

Local fixture files only.

## Assumptions

No external services are available.

## Work Instructions

Build and inspect the fixture artifact.

## Verification

Run deterministic local checks.

## Review

Use a separate critic identity.

## Issue
https://github.com/example/opencaw-fixture/issues/$issue_number
EOF
}

copy_gauntlet() {
  local source_dir="$1"
  local destination_dir="$2"
  mkdir -p "$(dirname "$destination_dir")"
  cp -R "$source_dir" "$destination_dir"
}

write_ready_gauntlet() {
  local target="$1"
  cat >"$target" <<'EOF'
# Fixture Gauntlet

## Flow and Status
- Type: gauntlet
- Status: ready

## Parent Task
- Task name: gauntlet-parent
- Task file: `.ai/tasks/gauntlet-parent/TASK.md`
- Issue: https://github.com/example/opencaw-fixture/issues/101

## Objective

Produce an inspectable local artifact that satisfies the approved fixture benchmark.

## Approved Quality Bar
- Approval: approved
- Approved by: fixture-user
- Approved at: 2026-08-01T12:00:00Z
- Frozen: yes
- Benchmark: Local artifact quality contract version 1.

### Criteria
- The artifact exists and contains the expected verified behavior.
- The focused local verifier passes without network access.

## Constraints and Permissions

### Constraints
- Keep all writes inside the explicit fixture project root.
- Do not use network services or credentials.

### Permissions
- Read and edit the local fixture artifact.
- Run deterministic local shell verification.

## Work Units
- [ ] unit-1 | status: pending | title: Complete the inspectable fixture artifact

### Unit History
- No unit changes recorded.

## Current State
- Active work unit: unit-1
- Latest round: none
- Quality bar fingerprint: pending
- Next action: Build unit-1 and request a fresh isolated critic.

## Round Ledger
- No rounds recorded.

## Integration Review
- Verdict: pending
- Critic ID:
- Isolation:
- Evidence:
- Quality bar fingerprint: pending

## Delivery
- PR readiness confirmation: human required
- One final PR: required
- Post-PR QA: required
- Auto-merge: disabled
- Merge approval: human only
- PR eligible: no
- PR:

## Review Notes

Fixture lifecycle evidence only.
EOF
}

write_critic_report() {
  local target="$1"
  local verdict="$2"
  local artifact="$3"
  local gap="$4"
  local strategy="$5"
  cat >"$target" <<EOF
# Critic Report

## Artifact Inspected
- Artifact: $artifact
- Evidence: The critic inspected the concrete local artifact and its focused verifier output.

## Bar Comparison
- Comparison: The artifact was compared directly with every approved fixture criterion.

## Guardrail Results
- Result: Root confinement, offline operation, and fixture integrity were checked.

## Verdict
- Verdict: $verdict

## Largest Remaining Gap
- Gap: $gap

## Next Strategy
- Strategy: $strategy
EOF
}

fake_network_bin="$temp_root/fake-network-bin"
mkdir -p "$fake_network_bin"
for command_name in gh github curl wget; do
  cat >"$fake_network_bin/$command_name" <<EOF
#!/usr/bin/env bash
printf '%s\n' '$command_name' >>'$network_marker'
exit 97
EOF
  chmod +x "$fake_network_bin/$command_name"
done
export PATH="$fake_network_bin:$PATH"
unset GH_TOKEN GITHUB_TOKEN 2>/dev/null || true

echo '[1/7] checking command interfaces and isolated scaffold behavior'
for command_name in create-gauntlet-file validate-gauntlet record-gauntlet-round; do
  command_file="commands/$command_name.sh"
  [[ -x "$command_file" ]] || fail "Gauntlet command is missing or not executable: $command_file"
  bash "$command_file" --help >/dev/null || fail "$command_name --help failed"
done

project="$(new_project gauntlet-project)"
run_for "$project" bash commands/create-host-ai-scaffold.sh >/dev/null
run_for "$project" bash commands/create-host-ai-scaffold.sh >/dev/null
[[ -d "$project/.ai/gauntlets" ]] || fail 'scaffold omitted .ai/gauntlets'
[[ -d "$project/.ai/archive/gauntlets" ]] || fail 'scaffold omitted .ai/archive/gauntlets'
[[ ! -e "$temp_root/.ai" ]] || fail 'scaffold escaped the explicit project root'

write_parent_task "$project" gauntlet-parent 101
dry_run_output="$temp_root/create-dry-run.log"
run_for "$project" bash commands/create-gauntlet-file.sh dry-run-gauntlet 'Dry-run Gauntlet' --task gauntlet-parent --dry-run >"$dry_run_output"
grep -q 'Dry run:' "$dry_run_output" || fail 'create dry-run did not identify itself'
grep -q -- '- Type: gauntlet' "$dry_run_output" || fail 'create dry-run omitted the Gauntlet flow marker'
[[ ! -e "$project/.ai/gauntlets/dry-run-gauntlet" ]] || fail 'create dry-run changed project state'

expect_failure "$temp_root/invalid-name.log" run_for "$project" bash commands/create-gauntlet-file.sh 'Invalid_Name' --task gauntlet-parent
expect_failure "$temp_root/escaping-name.log" run_for "$project" bash commands/create-gauntlet-file.sh '../../escape' --task gauntlet-parent
expect_failure "$temp_root/missing-task.log" run_for "$project" bash commands/create-gauntlet-file.sh missing-task-gauntlet --task absent-task

create_output="$temp_root/create.log"
run_for "$project" bash commands/create-gauntlet-file.sh fixture-gauntlet 'Fixture Gauntlet' --task gauntlet-parent >"$create_output"
gauntlet_dir="$project/.ai/gauntlets/fixture-gauntlet"
gauntlet_file="$gauntlet_dir/GAUNTLET.md"
expect_file "$gauntlet_file"
grep -Fq '.ai/tasks/gauntlet-parent/TASK.md' "$gauntlet_file" || fail 'Gauntlet did not link its parent task'
grep -Fq 'https://github.com/example/opencaw-fixture/issues/101' "$gauntlet_file" || fail 'Gauntlet did not link its parent issue'
[[ ! -e "$temp_root/escape" ]] || fail 'invalid Gauntlet name escaped the project root'

before_hash="$(git hash-object "$gauntlet_file")"
run_for "$project" bash commands/create-gauntlet-file.sh fixture-gauntlet 'Replacement title' --task gauntlet-parent >/dev/null
after_hash="$(git hash-object "$gauntlet_file")"
[[ "$before_hash" == "$after_hash" ]] || fail 'idempotent create overwrote an existing Gauntlet'

echo '[2/7] enforcing ready-state quality, linkage, and delivery gates'
write_ready_gauntlet "$gauntlet_file"
run_for "$project" bash commands/validate-gauntlet.sh fixture-gauntlet --phase ready >/dev/null
run_for "$project" bash commands/validate-gauntlet.sh "$gauntlet_dir" --phase ready >/dev/null
run_for "$project" bash commands/validate-gauntlet.sh "$gauntlet_file" --phase ready >/dev/null

linked_root_project="$(new_project linked-gauntlet-root-project)"
mkdir -p "$linked_root_project/.ai" "$temp_root/outside-gauntlet-root"
write_parent_task "$linked_root_project" gauntlet-parent 101
ln -s "$temp_root/outside-gauntlet-root" "$linked_root_project/.ai/gauntlets"
expect_failure "$temp_root/linked-gauntlet-root.log" run_for "$linked_root_project" \
  bash commands/create-gauntlet-file.sh escaped-root-gauntlet --task gauntlet-parent

outside_gauntlet_dir="$temp_root/outside-direct-gauntlet"
copy_gauntlet "$gauntlet_dir" "$outside_gauntlet_dir"
ln -s "$outside_gauntlet_dir" "$project/.ai/gauntlets/linked-gauntlet"
expect_failure "$temp_root/linked-gauntlet-dir.log" run_for "$project" \
  bash commands/validate-gauntlet.sh linked-gauntlet --phase ready
expect_failure "$temp_root/outside-gauntlet-ref.log" run_for "$project" \
  bash commands/validate-gauntlet.sh "$outside_gauntlet_dir/GAUNTLET.md" --phase ready

nested_gauntlet_dir="$project/.ai/gauntlets/nested-container/child"
mkdir -p "$nested_gauntlet_dir"
cp "$gauntlet_file" "$nested_gauntlet_dir/GAUNTLET.md"
expect_failure "$temp_root/nested-gauntlet-ref.log" run_for "$project" \
  bash commands/validate-gauntlet.sh "$nested_gauntlet_dir/GAUNTLET.md" --phase ready

outside_task_dir="$temp_root/outside-parent-task"
mkdir -p "$outside_task_dir"
cp "$project/.ai/tasks/gauntlet-parent/TASK.md" "$outside_task_dir/TASK.md"
ln -s "$outside_task_dir" "$project/.ai/tasks/symlink-task-dir"
case_dir="$project/.ai/gauntlets/symlink-task-directory"
copy_gauntlet "$gauntlet_dir" "$case_dir"
replace_line "$case_dir/GAUNTLET.md" '- Task name: gauntlet-parent' '- Task name: symlink-task-dir'
replace_line "$case_dir/GAUNTLET.md" '- Task file: `.ai/tasks/gauntlet-parent/TASK.md`' '- Task file: `.ai/tasks/symlink-task-dir/TASK.md`'
expect_failure "$temp_root/symlink-task-directory.log" run_for "$project" \
  bash commands/validate-gauntlet.sh symlink-task-directory --phase ready

mkdir -p "$project/.ai/tasks/symlink-task-file"
ln -s ../gauntlet-parent/TASK.md "$project/.ai/tasks/symlink-task-file/TASK.md"
case_dir="$project/.ai/gauntlets/symlink-task-file"
copy_gauntlet "$gauntlet_dir" "$case_dir"
replace_line "$case_dir/GAUNTLET.md" '- Task name: gauntlet-parent' '- Task name: symlink-task-file'
replace_line "$case_dir/GAUNTLET.md" '- Task file: `.ai/tasks/gauntlet-parent/TASK.md`' '- Task file: `.ai/tasks/symlink-task-file/TASK.md`'
expect_failure "$temp_root/symlink-task-file.log" run_for "$project" \
  bash commands/validate-gauntlet.sh symlink-task-file --phase ready

mkdir -p "$project/.ai/tasks/crlf-task"
cp "$project/.ai/tasks/gauntlet-parent/TASK.md" "$project/.ai/tasks/crlf-task/TASK.md"
convert_to_crlf "$project/.ai/tasks/crlf-task/TASK.md"
case_dir="$project/.ai/gauntlets/crlf-gauntlet"
copy_gauntlet "$gauntlet_dir" "$case_dir"
replace_line "$case_dir/GAUNTLET.md" '- Task name: gauntlet-parent' '- Task name: crlf-task'
replace_line "$case_dir/GAUNTLET.md" '- Task file: `.ai/tasks/gauntlet-parent/TASK.md`' '- Task file: `.ai/tasks/crlf-task/TASK.md`'
convert_to_crlf "$case_dir/GAUNTLET.md"
run_for "$project" bash commands/validate-gauntlet.sh crlf-gauntlet --phase ready >/dev/null

case_dir="$project/.ai/gauntlets/missing-objective"
copy_gauntlet "$gauntlet_dir" "$case_dir"
replace_line "$case_dir/GAUNTLET.md" 'Produce an inspectable local artifact that satisfies the approved fixture benchmark.' ''
expect_failure "$temp_root/missing-objective.log" run_for "$project" bash commands/validate-gauntlet.sh missing-objective --phase ready

case_dir="$project/.ai/gauntlets/unapproved-bar"
copy_gauntlet "$gauntlet_dir" "$case_dir"
replace_line "$case_dir/GAUNTLET.md" '- Approval: approved' '- Approval: pending'
expect_failure "$temp_root/unapproved-bar.log" run_for "$project" bash commands/validate-gauntlet.sh unapproved-bar --phase ready

case_dir="$project/.ai/gauntlets/placeholder-bar"
copy_gauntlet "$gauntlet_dir" "$case_dir"
replace_line "$case_dir/GAUNTLET.md" '- The artifact exists and contains the expected verified behavior.' '- TODO: Define inspectable pass criteria.'
expect_failure "$temp_root/placeholder-bar.log" run_for "$project" bash commands/validate-gauntlet.sh placeholder-bar --phase ready

write_parent_task "$project" task-without-issue 102
awk '$0 !~ /^https:\/\/github\.com\/example\/opencaw-fixture\/issues\/102$/' \
  "$project/.ai/tasks/task-without-issue/TASK.md" >"$project/.ai/tasks/task-without-issue/TASK.md.tmp"
mv "$project/.ai/tasks/task-without-issue/TASK.md.tmp" "$project/.ai/tasks/task-without-issue/TASK.md"
case_dir="$project/.ai/gauntlets/missing-issue"
copy_gauntlet "$gauntlet_dir" "$case_dir"
replace_line "$case_dir/GAUNTLET.md" '- Task name: gauntlet-parent' '- Task name: task-without-issue'
replace_line "$case_dir/GAUNTLET.md" '- Task file: `.ai/tasks/gauntlet-parent/TASK.md`' '- Task file: `.ai/tasks/task-without-issue/TASK.md`'
replace_line "$case_dir/GAUNTLET.md" '- Issue: https://github.com/example/opencaw-fixture/issues/101' '- Issue:'
expect_failure "$temp_root/missing-issue.log" run_for "$project" bash commands/validate-gauntlet.sh missing-issue --phase ready

case_dir="$project/.ai/gauntlets/invalid-unit"
copy_gauntlet "$gauntlet_dir" "$case_dir"
replace_line "$case_dir/GAUNTLET.md" \
  '- [ ] unit-1 | status: pending | title: Complete the inspectable fixture artifact' \
  '- [ ] unit-1 | status: invented | title: Complete the inspectable fixture artifact'
expect_failure "$temp_root/invalid-unit.log" run_for "$project" bash commands/validate-gauntlet.sh invalid-unit --phase ready

case_dir="$project/.ai/gauntlets/reserved-integration-unit"
copy_gauntlet "$gauntlet_dir" "$case_dir"
replace_line "$case_dir/GAUNTLET.md" \
  '- [ ] unit-1 | status: pending | title: Complete the inspectable fixture artifact' \
  '- [ ] integration | status: pending | title: Reserved IDs cannot be normal work units'
expect_failure "$temp_root/reserved-integration-unit.log" run_for "$project" \
  bash commands/validate-gauntlet.sh reserved-integration-unit --phase ready

case_dir="$project/.ai/gauntlets/forbidden-pr-setting"
copy_gauntlet "$gauntlet_dir" "$case_dir"
replace_line "$case_dir/GAUNTLET.md" '- Auto-merge: disabled' '- Auto-merge: enabled'
expect_failure "$temp_root/forbidden-pr.log" run_for "$project" bash commands/validate-gauntlet.sh forbidden-pr-setting --phase ready

case_dir="$project/.ai/gauntlets/premature-pr-eligibility"
copy_gauntlet "$gauntlet_dir" "$case_dir"
replace_line "$case_dir/GAUNTLET.md" '- PR eligible: no' '- PR eligible: yes'
expect_failure "$temp_root/premature-pr-eligibility.log" run_for "$project" \
  bash commands/validate-gauntlet.sh premature-pr-eligibility --phase ready

echo '[3/7] rejecting invalid critic evidence without mutating round history'
ready_snapshot="$temp_root/ready-snapshot"
copy_gauntlet "$gauntlet_dir" "$ready_snapshot"
critic_dir="$project/critic-reports"
mkdir -p "$critic_dir"
valid_fail_report="$critic_dir/fail-round.md"
write_critic_report "$valid_fail_report" fail artifact.txt \
  'The fixture still lacks the required verified behavior.' \
  'Rework the parsing boundary and rerun the focused verifier.'

crlf_report="$critic_dir/crlf-report.md"
cp "$valid_fail_report" "$crlf_report"
convert_to_crlf "$crlf_report"
run_for "$project" bash commands/record-gauntlet-round.sh crlf-gauntlet unit-1 fail \
  crlf-builder crlf-critic fresh-session "$crlf_report" --dry-run >/dev/null
[[ "$(round_file_count "$project/.ai/gauntlets/crlf-gauntlet")" == 0 ]] \
  || fail 'CRLF record dry-run created evidence'

expect_failure "$temp_root/unknown-unit.log" run_for "$project" bash commands/record-gauntlet-round.sh \
  fixture-gauntlet absent-unit fail builder-1 critic-unknown native-subagent "$valid_fail_report"
expect_failure "$temp_root/self-critique.log" run_for "$project" bash commands/record-gauntlet-round.sh \
  fixture-gauntlet unit-1 fail same-identity same-identity native-subagent "$valid_fail_report"

malformed_report="$critic_dir/malformed.md"
cp "$valid_fail_report" "$malformed_report"
awk '
  $0 == "## Guardrail Results" { skip=1; next }
  /^## / && skip { skip=0 }
  !skip { print }
' "$malformed_report" >"$malformed_report.tmp"
mv "$malformed_report.tmp" "$malformed_report"
expect_failure "$temp_root/malformed-report.log" run_for "$project" bash commands/record-gauntlet-round.sh \
  fixture-gauntlet unit-1 fail builder-1 critic-malformed native-subagent "$malformed_report"

missing_artifact_report="$critic_dir/missing-artifact.md"
write_critic_report "$missing_artifact_report" fail missing-artifact.txt \
  'No inspectable artifact was available.' \
  'Produce the real artifact before requesting another review.'
expect_failure "$temp_root/missing-artifact.log" run_for "$project" bash commands/record-gauntlet-round.sh \
  fixture-gauntlet unit-1 fail builder-1 critic-missing native-subagent "$missing_artifact_report"

escaping_artifact_report="$critic_dir/escaping-artifact.md"
write_critic_report "$escaping_artifact_report" fail ../outside.txt \
  'The claimed evidence escaped the fixture root.' \
  'Inspect a project-root artifact in the next isolated review.'
expect_failure "$temp_root/escaping-artifact.log" run_for "$project" bash commands/record-gauntlet-round.sh \
  fixture-gauntlet unit-1 fail builder-1 critic-escaping native-subagent "$escaping_artifact_report"

ln -s artifact.txt "$project/artifact-link.txt"
symlink_artifact_report="$critic_dir/symlink-artifact.md"
write_critic_report "$symlink_artifact_report" fail artifact-link.txt \
  'The claimed evidence was not a regular non-symlink artifact.' \
  'Inspect the real regular file in the next isolated review.'
expect_failure "$temp_root/symlink-artifact.log" run_for "$project" bash commands/record-gauntlet-round.sh \
  fixture-gauntlet unit-1 fail builder-1 critic-symlink native-subagent "$symlink_artifact_report"

mismatched_report="$critic_dir/mismatched-verdict.md"
write_critic_report "$mismatched_report" pass artifact.txt \
  'No material gap remains in the inspected unit.' \
  'Advance to integration only after the recorded pass is accepted.'
expect_failure "$temp_root/mismatched-verdict.log" run_for "$project" bash commands/record-gauntlet-round.sh \
  fixture-gauntlet unit-1 fail builder-1 critic-mismatch native-subagent "$mismatched_report"

none_gap_report="$critic_dir/none-gap.md"
write_critic_report "$none_gap_report" fail artifact.txt none \
  'Replace the incomplete boundary implementation with the verified design.'
expect_failure "$temp_root/none-gap.log" run_for "$project" bash commands/record-gauntlet-round.sh \
  fixture-gauntlet unit-1 fail builder-1 critic-none-gap native-subagent "$none_gap_report"

retry_strategy_report="$critic_dir/retry-strategy.md"
write_critic_report "$retry_strategy_report" blocked artifact.txt \
  'The required local verifier is unavailable in the current fixture state.' retry
expect_failure "$temp_root/retry-strategy.log" run_for "$project" bash commands/record-gauntlet-round.sh \
  fixture-gauntlet unit-1 blocked builder-1 critic-retry-strategy fresh-session "$retry_strategy_report"

[[ "$(round_file_count "$gauntlet_dir")" == 0 ]] || fail 'rejected critic evidence created round history'

echo '[4/7] preserving failed rounds, bar immutability, and fresh-critic strategy changes'
gauntlet_before_dry_run="$(git hash-object "$gauntlet_file")"
run_for "$project" bash commands/record-gauntlet-round.sh fixture-gauntlet unit-1 fail \
  builder-1 critic-dry-run native-subagent "$valid_fail_report" --dry-run >"$temp_root/round-dry-run.log"
[[ "$(round_file_count "$gauntlet_dir")" == 0 ]] || fail 'record-round dry-run created evidence'
[[ "$gauntlet_before_dry_run" == "$(git hash-object "$gauntlet_file")" ]] || fail 'record-round dry-run changed GAUNTLET.md'

run_for "$project" bash commands/record-gauntlet-round.sh fixture-gauntlet unit-1 fail \
  builder-1 critic-1 native-subagent "$valid_fail_report" >/dev/null
round_one="$gauntlet_dir/rounds/unit-1/round-001.md"
expect_file "$round_one"
grep -q 'critic-1' "$round_one" || fail 'round evidence omitted the critic identity'
grep -q 'critic-failed' "$gauntlet_file" || fail 'failed verdict did not update the work-unit state'
current_fingerprint_line="$(awk '
  $0 == "## Current State" { active=1; next }
  /^## / && active { exit }
  active && /Quality bar fingerprint:/ { print }
' "$gauntlet_file")"
[[ -n "$current_fingerprint_line" && "$current_fingerprint_line" != *pending* ]] \
  || fail 'first round did not freeze a quality-bar fingerprint'
quality_bar_v1="${current_fingerprint_line#- Quality bar fingerprint: }"
round_one_hash="$(git hash-object "$round_one")"

replace_line "$gauntlet_file" \
  '- Benchmark: Local artifact quality contract version 1.' \
  '- Benchmark: Mutated quality contract that was not re-approved.'
expect_failure "$temp_root/changed-bar-validation.log" run_for "$project" bash commands/validate-gauntlet.sh fixture-gauntlet --phase ready
expect_failure "$temp_root/changed-bar-record.log" run_for "$project" bash commands/record-gauntlet-round.sh \
  fixture-gauntlet unit-1 fail builder-2 critic-bar-drift fresh-session "$valid_fail_report"
replace_line "$gauntlet_file" \
  '- Benchmark: Mutated quality contract that was not re-approved.' \
  '- Benchmark: Local artifact quality contract version 1.'

changed_fail_report="$critic_dir/changed-fail-round.md"
write_critic_report "$changed_fail_report" fail artifact.txt \
  'The output contract is correct, but its boundary recovery remains incomplete.' \
  'Replace the boundary adapter with deterministic validation and add a recovery assertion.'
expect_failure "$temp_root/reused-critic.log" run_for "$project" bash commands/record-gauntlet-round.sh \
  fixture-gauntlet unit-1 fail builder-2 critic-1 fresh-session "$changed_fail_report"
expect_failure "$temp_root/reused-strategy.log" run_for "$project" bash commands/record-gauntlet-round.sh \
  fixture-gauntlet unit-1 fail builder-2 critic-2 fresh-session "$valid_fail_report"

run_for "$project" bash commands/record-gauntlet-round.sh fixture-gauntlet unit-1 fail \
  builder-2 critic-2 fresh-session "$changed_fail_report" >/dev/null
round_two="$gauntlet_dir/rounds/unit-1/round-002.md"
expect_file "$round_two"

pass_report="$critic_dir/pass-round.md"
write_critic_report "$pass_report" pass artifact.txt \
  'No remaining unit-level gap was found against the approved bar.' \
  'Advance the passed unit to a fresh integration review.'
run_for "$project" bash commands/record-gauntlet-round.sh fixture-gauntlet unit-1 pass \
  builder-3 critic-3 native-subagent "$pass_report" >/dev/null
round_three="$gauntlet_dir/rounds/unit-1/round-003.md"
expect_file "$round_three"
[[ "$round_one_hash" == "$(git hash-object "$round_one")" ]] || fail 'later recording overwrote immutable round-001 evidence'
[[ "$(find "$gauntlet_dir/rounds/unit-1" -type f -name 'round-*.md' | wc -l | tr -d ' ')" == 3 ]] \
  || fail 'failed invocations consumed round numbers or valid rounds were lost'
grep -Eq '^- \[[ x]\] unit-1 \| status: passed \|' "$gauntlet_file" || fail 'passing verdict did not mark the work unit passed'

reapproval_dir="$project/.ai/gauntlets/reapproved-bar"
copy_gauntlet "$gauntlet_dir" "$reapproval_dir"
replace_all_literal "$reapproval_dir/GAUNTLET.md" \
  '.ai/gauntlets/fixture-gauntlet/' '.ai/gauntlets/reapproved-bar/'
replace_line "$reapproval_dir/GAUNTLET.md" \
  '- Benchmark: Local artifact quality contract version 1.' \
  '- Benchmark: Local artifact quality contract version 2 with explicit recovery behavior.'
replace_line "$reapproval_dir/GAUNTLET.md" '- Approved by: fixture-user' '- Approved by: fixture-user-v2'
replace_line "$reapproval_dir/GAUNTLET.md" \
  '- Approved at: 2026-08-01T12:00:00Z' '- Approved at: 2026-08-01T13:00:00Z'
replace_line "$reapproval_dir/GAUNTLET.md" \
  "- Quality bar fingerprint: $quality_bar_v1" '- Quality bar fingerprint: pending'
replace_matching_line "$reapproval_dir/GAUNTLET.md" '^- .*unit-1 .*status:' \
  '- [ ] unit-1 | status: critic-failed | title: Complete the inspectable fixture artifact'
replace_line "$reapproval_dir/GAUNTLET.md" '- No unit changes recorded.' \
  "- Quality bar revision: recovery-v2 | approved by: fixture-user-v2 | approved at: 2026-08-01T13:00:00Z | supersedes: $quality_bar_v1 | reason: Add explicit recovery behavior after reviewing retained round evidence."
run_for "$project" bash commands/validate-gauntlet.sh reapproved-bar --phase ready >/dev/null
expect_failure "$temp_root/reapproval-old-passes.log" run_for "$project" \
  bash commands/validate-gauntlet.sh reapproved-bar --phase complete

reapproval_old_round_hash="$(git hash-object "$reapproval_dir/rounds/unit-1/round-001.md")"
reapproval_unit_report="$critic_dir/reapproval-unit-pass.md"
write_critic_report "$reapproval_unit_report" pass artifact.txt \
  'The artifact now satisfies every criterion in the explicitly reapproved quality bar.' \
  'Advance the revised artifact to a new independent integration review.'
run_for "$project" bash commands/record-gauntlet-round.sh reapproved-bar unit-1 pass \
  reapproval-builder-1 reapproval-critic-1 fresh-session "$reapproval_unit_report" >/dev/null
expect_file "$reapproval_dir/rounds/unit-1/round-004.md"
[[ "$reapproval_old_round_hash" == "$(git hash-object "$reapproval_dir/rounds/unit-1/round-001.md")" ]] \
  || fail 'quality-bar reapproval changed retained historical evidence'

reapproval_integration_report="$critic_dir/reapproval-integration-pass.md"
write_critic_report "$reapproval_integration_report" pass artifact.txt \
  'The complete revised artifact passes the newly approved integration bar.' \
  'Generate the revised completion report and retain all earlier round history.'
run_for "$project" bash commands/record-gauntlet-round.sh reapproved-bar integration pass \
  reapproval-integration-builder reapproval-integration-critic native-subagent "$reapproval_integration_report" >/dev/null
expect_file "$reapproval_dir/rounds/integration/round-001.md"

echo '[5/7] gating complete, stopped, and blocked completion reports'
[[ -x commands/create-gauntlet-completion-report.sh ]] \
  || fail 'Gauntlet completion command is missing or not executable'
bash commands/create-gauntlet-completion-report.sh --help >/dev/null \
  || fail 'create-gauntlet-completion-report --help failed'
run_for "$project" bash commands/create-gauntlet-completion-report.sh reapproved-bar --status complete --dry-run \
  >"$temp_root/reapproved-complete-dry-run.log"
[[ ! -f "$reapproval_dir/GAUNTLET_REPORT.md" ]] || fail 'reapproved completion dry-run wrote a report'
expect_failure "$temp_root/premature-complete.log" run_for "$project" bash commands/create-gauntlet-completion-report.sh \
  fixture-gauntlet --status complete

stopped_dir="$project/.ai/gauntlets/stopped-gauntlet"
copy_gauntlet "$ready_snapshot" "$stopped_dir"
stopped_hash="$(git hash-object "$stopped_dir/GAUNTLET.md")"
run_for "$project" bash commands/create-gauntlet-completion-report.sh stopped-gauntlet --status stopped --dry-run \
  >"$temp_root/stopped-dry-run.log"
[[ ! -f "$stopped_dir/GAUNTLET_REPORT.md" ]] || fail 'completion dry-run created a report'
[[ "$stopped_hash" == "$(git hash-object "$stopped_dir/GAUNTLET.md")" ]] || fail 'completion dry-run changed Gauntlet state'
run_for "$project" bash commands/create-gauntlet-completion-report.sh stopped-gauntlet --status stopped >/dev/null
expect_file "$stopped_dir/GAUNTLET_REPORT.md"
grep -Eiq 'PR eligible[^[:alnum:]]+no|not PR[- ]eligible|PR-ineligible' "$stopped_dir/GAUNTLET_REPORT.md" \
  || fail 'stopped report was not explicitly PR-ineligible'
expect_failure "$temp_root/stopped-complete-validation.log" run_for "$project" bash commands/validate-gauntlet.sh stopped-gauntlet --phase complete

blocked_dir="$project/.ai/gauntlets/blocked-gauntlet"
copy_gauntlet "$ready_snapshot" "$blocked_dir"
run_for "$project" bash commands/create-gauntlet-completion-report.sh blocked-gauntlet --status blocked >/dev/null
expect_file "$blocked_dir/GAUNTLET_REPORT.md"
grep -Eiq 'PR eligible[^[:alnum:]]+no|not PR[- ]eligible|PR-ineligible' "$blocked_dir/GAUNTLET_REPORT.md" \
  || fail 'blocked report was not explicitly PR-ineligible'
expect_failure "$temp_root/blocked-complete-validation.log" run_for "$project" bash commands/validate-gauntlet.sh blocked-gauntlet --phase complete

integration_report="$critic_dir/integration-pass.md"
write_critic_report "$integration_report" pass artifact.txt \
  'No remaining integration gap was found across the complete fixture artifact.' \
  'Hold the passing artifact for final reporting and the human PR readiness checkpoint.'
run_for "$project" bash commands/record-gauntlet-round.sh fixture-gauntlet integration pass \
  integration-builder-1 integration-critic-1 fresh-session "$integration_report" >/dev/null
expect_file "$gauntlet_dir/rounds/integration/round-001.md"
grep -q -- '- Verdict: pass' "$gauntlet_file" || fail 'integration pass was not recorded in GAUNTLET.md'
run_for "$project" bash commands/create-gauntlet-completion-report.sh fixture-gauntlet --status complete --dry-run \
  >"$temp_root/first-integration-complete-dry-run.log"
[[ ! -f "$gauntlet_dir/GAUNTLET_REPORT.md" ]] || fail 'complete dry-run wrote a report after the first integration pass'

integration_fail_report="$critic_dir/integration-fail.md"
write_critic_report "$integration_fail_report" fail artifact.txt \
  'The assembled artifact exposes a cross-unit recovery regression.' \
  'Reopen affected units, correct recovery as one coherent change, and rerun focused checks.'
run_for "$project" bash commands/record-gauntlet-round.sh fixture-gauntlet integration fail \
  integration-builder-2 integration-critic-2 native-subagent "$integration_fail_report" >/dev/null
expect_file "$gauntlet_dir/rounds/integration/round-002.md"
grep -q -- '- Verdict: fail' "$gauntlet_file" || fail 'later integration failure did not supersede the earlier pass'
! grep -Eq '^- \[[ x]\] unit-1 \| status: passed \|' "$gauntlet_file" \
  || fail 'integration failure left the active unit pass current'
expect_failure "$temp_root/stale-integration-pass.log" run_for "$project" \
  bash commands/validate-gauntlet.sh fixture-gauntlet --phase complete

stale_reference_dir="$project/.ai/gauntlets/stale-integration-reference"
copy_gauntlet "$gauntlet_dir" "$stale_reference_dir"
replace_all_literal "$stale_reference_dir/GAUNTLET.md" \
  '.ai/gauntlets/fixture-gauntlet/' '.ai/gauntlets/stale-integration-reference/'
replace_line "$stale_reference_dir/GAUNTLET.md" '- Status: running' '- Status: passed'
replace_matching_line "$stale_reference_dir/GAUNTLET.md" '^- .*unit-1 .*status:' \
  '- [x] unit-1 | status: passed | title: Complete the inspectable fixture artifact'
replace_line "$stale_reference_dir/GAUNTLET.md" '- Verdict: fail' '- Verdict: pass'
replace_line "$stale_reference_dir/GAUNTLET.md" '- Critic ID: integration-critic-2' '- Critic ID: integration-critic-1'
replace_line "$stale_reference_dir/GAUNTLET.md" \
  '- Evidence: `.ai/gauntlets/stale-integration-reference/rounds/integration/round-002.md`' \
  '- Evidence: `.ai/gauntlets/stale-integration-reference/rounds/integration/round-001.md`'
replace_line "$stale_reference_dir/GAUNTLET.md" '- PR eligible: no' '- PR eligible: yes'
expect_failure "$temp_root/stale-integration-reference.log" run_for "$project" \
  bash commands/validate-gauntlet.sh stale-integration-reference --phase complete

orphan_dir="$project/.ai/gauntlets/orphan-history"
copy_gauntlet "$gauntlet_dir" "$orphan_dir"
replace_all_literal "$orphan_dir/GAUNTLET.md" \
  '.ai/gauntlets/fixture-gauntlet/' '.ai/gauntlets/orphan-history/'
replace_matching_line "$orphan_dir/GAUNTLET.md" '^- .*unit-1 .*status:' \
  '- [ ] unit-2 | status: pending | title: Replacement unit that erased prior history'
replace_matching_line "$orphan_dir/GAUNTLET.md" '^- Active work unit:' '- Active work unit: unit-2'
expect_failure "$temp_root/orphan-history.log" run_for "$project" \
  bash commands/validate-gauntlet.sh orphan-history --phase ready

superseded_dir="$project/.ai/gauntlets/superseded-history"
copy_gauntlet "$gauntlet_dir" "$superseded_dir"
replace_all_literal "$superseded_dir/GAUNTLET.md" \
  '.ai/gauntlets/fixture-gauntlet/' '.ai/gauntlets/superseded-history/'
replace_matching_line "$superseded_dir/GAUNTLET.md" '^- .*unit-1 .*status:' \
  '- [x] unit-1 | status: superseded | title: Preserved prior unit history'
insert_after_matching_line "$superseded_dir/GAUNTLET.md" '^- .*unit-1 .*status:' \
  '- [ ] unit-2 | status: pending | title: Replacement active unit'
replace_matching_line "$superseded_dir/GAUNTLET.md" '^- Active work unit:' '- Active work unit: unit-2'
run_for "$project" bash commands/validate-gauntlet.sh superseded-history --phase ready >/dev/null

post_integration_unit_report="$critic_dir/post-integration-unit-pass.md"
write_critic_report "$post_integration_unit_report" pass artifact.txt \
  'The reopened recovery behavior now satisfies the frozen unit criteria.' \
  'Return the corrected complete artifact to a new integration critic.'
run_for "$project" bash commands/record-gauntlet-round.sh fixture-gauntlet unit-1 pass \
  builder-4 critic-4 fresh-session "$post_integration_unit_report" >/dev/null
expect_file "$gauntlet_dir/rounds/unit-1/round-004.md"

final_integration_report="$critic_dir/final-integration-pass.md"
write_critic_report "$final_integration_report" pass artifact.txt \
  'No remaining integration gap exists after the reopened unit correction.' \
  'Generate the final report and proceed to the human PR readiness checkpoint.'
run_for "$project" bash commands/record-gauntlet-round.sh fixture-gauntlet integration pass \
  integration-builder-3 integration-critic-3 fresh-session "$final_integration_report" >/dev/null
expect_file "$gauntlet_dir/rounds/integration/round-003.md"
run_for "$project" bash commands/create-gauntlet-completion-report.sh fixture-gauntlet --status complete >/dev/null
expect_file "$gauntlet_dir/GAUNTLET_REPORT.md"
grep -Eiq 'PR eligible[^[:alnum:]]+yes' "$gauntlet_dir/GAUNTLET_REPORT.md" || fail 'passed report was not marked PR-eligible'
run_for "$project" bash commands/validate-gauntlet.sh fixture-gauntlet --phase complete >/dev/null

post_pr_reopen_dir="$project/.ai/gauntlets/post-pr-reopen"
copy_gauntlet "$gauntlet_dir" "$post_pr_reopen_dir"
replace_all_literal "$post_pr_reopen_dir/GAUNTLET.md" \
  '.ai/gauntlets/fixture-gauntlet/' '.ai/gauntlets/post-pr-reopen/'
run_for "$project" bash commands/record-gauntlet-round.sh post-pr-reopen unit-1 pass \
  post-pr-builder post-pr-critic fresh-session "$post_integration_unit_report" >/dev/null
expect_file "$post_pr_reopen_dir/rounds/unit-1/round-005.md"
expect_line '- Status: running' "$post_pr_reopen_dir/GAUNTLET.md"
expect_line '- PR eligible: no' "$post_pr_reopen_dir/GAUNTLET.md"
expect_line '- Verdict: pending' "$post_pr_reopen_dir/GAUNTLET.md"
run_for "$project" bash commands/validate-gauntlet.sh post-pr-reopen --phase ready >/dev/null
expect_failure "$temp_root/post-pr-reopen-readiness.log" run_for "$project" \
  bash commands/pr-readiness-check.sh --gauntlet post-pr-reopen

numeric_round_dir="$temp_root/numeric-round-selection"
mkdir -p "$numeric_round_dir"
: >"$numeric_round_dir/round-999.md"
: >"$numeric_round_dir/round-1000.md"
numeric_latest="$(OPENCAW_PROJECT_ROOT="$project" bash -c \
  'source commands/lib/gauntlet-common.sh; gauntlet_latest_round_file "$1"' \
  _ "$numeric_round_dir")"
[[ "$numeric_latest" == "$numeric_round_dir/round-1000.md" ]] \
  || fail 'numeric latest-round selection imposed a three-digit ceiling or used lexicographic order'

echo '[6/7] preserving task, goal, and Gauntlet PR-readiness behavior'
printf '# Validation Summary\n\nAll local Gauntlet fixture checks passed.\n' >"$project/validation-summary.md"
task_pr_output="$(OPENCAW_REPORT_DIR="$project/.ai/reports/task" run_for "$project" \
  bash commands/pr-readiness-check.sh gauntlet-parent "$project/validation-summary.md")"
grep -q '^USER_CONFIRMATION_REQUIRED=YES$' <<<"$task_pr_output" || fail 'task readiness lost its human confirmation gate'
grep -q '^GOAL_FLOW_AUTOMATION=NO$' <<<"$task_pr_output" || fail 'task readiness enabled goal automation'

goal_pr_output="$(OPENCAW_REPORT_DIR="$project/.ai/reports/goal" run_for "$project" \
  bash commands/pr-readiness-check.sh --goal gauntlet-parent "$project/validation-summary.md")"
grep -q '^USER_CONFIRMATION_REQUIRED=NO$' <<<"$goal_pr_output" || fail 'goal readiness lost its automatic PR exception'
grep -q '^GOAL_FLOW_AUTOMATION=YES$' <<<"$goal_pr_output" || fail 'goal readiness did not identify goal automation'

gauntlet_pr_output="$(OPENCAW_REPORT_DIR="$project/.ai/reports/gauntlet" run_for "$project" \
  bash commands/pr-readiness-check.sh --gauntlet fixture-gauntlet "$project/validation-summary.md")"
grep -q '^USER_CONFIRMATION_REQUIRED=YES$' <<<"$gauntlet_pr_output" || fail 'Gauntlet readiness bypassed human confirmation'
grep -q '^GOAL_FLOW_AUTOMATION=NO$' <<<"$gauntlet_pr_output" || fail 'Gauntlet readiness enabled goal automation'
grep -q '^GAUNTLET_FLOW=YES$' <<<"$gauntlet_pr_output" || fail 'Gauntlet readiness did not identify Gauntlet mode'

expect_failure "$temp_root/stopped-pr-readiness.log" env OPENCAW_PROJECT_ROOT="$project" \
  OPENCAW_REPORT_DIR="$project/.ai/reports/stopped" bash commands/pr-readiness-check.sh --gauntlet stopped-gauntlet "$project/validation-summary.md"
expect_failure "$temp_root/blocked-pr-readiness.log" env OPENCAW_PROJECT_ROOT="$project" \
  OPENCAW_REPORT_DIR="$project/.ai/reports/blocked" bash commands/pr-readiness-check.sh --gauntlet blocked-gauntlet "$project/validation-summary.md"

echo '[7/7] checking owned shell syntax and offline isolation'
bash -n tests/test-gauntlet-flow.sh commands/validate-opencaw.sh \
  commands/create-gauntlet-file.sh commands/validate-gauntlet.sh \
  commands/record-gauntlet-round.sh commands/create-gauntlet-completion-report.sh \
  commands/pr-readiness-check.sh commands/create-host-ai-scaffold.sh

[[ ! -e "$network_marker" ]] || fail 'Gauntlet tests invoked a network-capable command'
echo 'Gauntlet flow tests passed.'
