#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

temp_root="$(mktemp -d)"
trap 'rm -rf -- "$temp_root"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
expect_failure() {
  local output_file="$1"
  shift
  set +e
  "$@" >"$output_file" 2>&1
  local result=$?
  set -e
  [[ $result -ne 0 ]] || fail "command unexpectedly succeeded: $*"
}
new_project() {
  local name="$1"
  local project="$temp_root/$name"
  mkdir -p "$project"
  git -C "$project" init -q
  printf 'fixture\n' > "$project/app.txt"
  git -C "$project" add app.txt
  printf '%s\n' "$project"
}
run_for() {
  local project="$1"
  shift
  OPENCAW_PROJECT_ROOT="$project" "$@"
}

write_sample_brainstorm() {
  local project="$1"
  cat > "$project/BRAINSTORM.md" <<'EOF'
# Brainstorm

## Mode
- Status: active
- Active session: BS-001
- Activated at: 2026-08-07T12:00:00Z
- Deactivated at: pending

## Session History
- BS-001 | started: 2026-08-07T12:00:00Z | ended: pending

## Branches
- BR-001 | parent: ROOT | title: Applications | summary: User-facing application concepts.
- BR-002 | parent: BR-001 | title: Cooperative Games | summary: Games built around meaningful cooperation.

## Elements

### IDEA-001
- Title: Disaster recovery city builder
- Branch: BR-002
- Status: plan-ready
- Created at: 2026-08-07T12:01:00Z
- Updated at: 2026-08-07T12:10:00Z
- Plan readiness: yes
- Summary: Cooperative city recovery with measurable shared resilience.

#### User Idea
Create a cooperative city-building game about recovering after disasters.

#### Base Understanding
Players coordinate limited resources to restore services and improve resilience.

#### Research Findings and Citations
Evidence: public preparedness guidance emphasizes whole-community coordination ([FEMA](https://www.fema.gov/emergency-managers/national-preparedness/goal)). Inference: shared recovery objectives can support cooperative play.

#### Dependencies
A deterministic simulation, scenario data, cooperative state synchronization, and accessibility review.

#### Risks
Disaster themes require respectful framing and the simulation must remain understandable.

#### Open Questions
The target player count and session duration need product validation during planning.

#### Start Conditions
Choose the target platform, audience, player count, and one representative recovery scenario.

#### Definition of Complete
A playable vertical slice lets the target group complete one recovery scenario, exposes shared tradeoffs, and passes agreed usability and synchronization checks.

### IDEA-002
- Title: Neighborhood mutual-aid directory
- Branch: BR-001
- Status: captured
- Created at: 2026-08-07T12:11:00Z
- Updated at: 2026-08-07T12:11:00Z
- Plan readiness: no
- Summary: Early concept for matching neighborhood needs and offers.

#### User Idea
Create a mutual-aid directory for neighborhoods.

#### Base Understanding
_Pending._

#### Research Findings and Citations
_Pending._

#### Dependencies
_Pending._

#### Risks
_Pending._

#### Open Questions
_Pending._

#### Start Conditions
_Pending._

#### Definition of Complete
_Pending._
EOF
}

echo '[1/8] verifying absent state and non-mutating dry runs'
project="$(new_project lifecycle)"
status_output="$(run_for "$project" bash commands/brainstorm-mode.sh status)"
grep -q '^BRAINSTORM_STATUS=absent$' <<< "$status_output" || fail 'absent state was not reported'
dry_output="$(run_for "$project" bash commands/brainstorm-mode.sh start --dry-run)"
grep -q 'would activate' <<< "$dry_output" || fail 'start dry-run did not explain the mutation'
[[ ! -e "$project/BRAINSTORM.md" && ! -e "$project/BRAINSTORM_SUMMARY.md" ]] || fail 'start dry-run wrote Brainstorm artifacts'

echo '[2/8] verifying sticky activation and idempotence'
run_for "$project" bash commands/brainstorm-mode.sh start >/dev/null
[[ -f "$project/BRAINSTORM.md" ]] || fail 'Brainstorm was not created at repository root'
[[ ! -e "$temp_root/BRAINSTORM.md" ]] || fail 'Brainstorm escaped the resolved project root'
run_for "$project" bash commands/validate-brainstorm.sh --phase active >/dev/null
before_hash="$(sha256sum "$project/BRAINSTORM.md" | awk '{print $1}')"
run_for "$project" bash commands/brainstorm-mode.sh start >/dev/null
after_hash="$(sha256sum "$project/BRAINSTORM.md" | awk '{print $1}')"
[[ "$before_hash" == "$after_hash" ]] || fail 'repeated active start changed BRAINSTORM.md'

echo '[3/8] validating branches, elements, plan readiness, and views'
write_sample_brainstorm "$project"
run_for "$project" bash commands/validate-brainstorm.sh --phase active >/dev/null
graph_output="$(run_for "$project" bash commands/show-brainstorm.sh)"
grep -q '^mindmap$' <<< "$graph_output" || fail 'default view was not a Mermaid mindmap'
grep -q 'BR_001\[Applications\]' <<< "$graph_output" || fail 'mindmap omitted the root branch'
grep -q 'IDEA_001\[IDEA-001: Disaster recovery city builder (plan-ready)\]' <<< "$graph_output" || fail 'mindmap omitted the plan-ready idea'
run_for "$project" bash commands/show-brainstorm.sh --markdown > "$temp_root/brainstorm-copy.md"
cmp -s "$project/BRAINSTORM.md" "$temp_root/brainstorm-copy.md" || fail '--markdown did not return BRAINSTORM.md verbatim'

echo '[4/8] rejecting malformed structure and plan-readiness claims'
invalid_project="$(new_project invalid)"
write_sample_brainstorm "$invalid_project"
sed -i 's/parent: ROOT | title: Applications/parent: BR-002 | title: Applications/' "$invalid_project/BRAINSTORM.md"
expect_failure "$temp_root/cycle.log" run_for "$invalid_project" bash commands/validate-brainstorm.sh --phase active
grep -q 'cycle detected' "$temp_root/cycle.log" || fail 'branch cycle was not explained'
write_sample_brainstorm "$invalid_project"
sed -i 's|https://www.fema.gov/emergency-managers/national-preparedness/goal|citation-unavailable|' "$invalid_project/BRAINSTORM.md"
expect_failure "$temp_root/citation.log" run_for "$invalid_project" bash commands/validate-brainstorm.sh --phase active
grep -q 'requires at least one HTTP(S)' "$temp_root/citation.log" || fail 'plan-ready citation requirement was not enforced'
write_sample_brainstorm "$invalid_project"
sed -i '0,/^- Status: active$/s//- Status: malformed/' "$invalid_project/BRAINSTORM.md"
expect_failure "$temp_root/state.log" run_for "$invalid_project" bash commands/brainstorm-mode.sh status
grep -q '^BRAINSTORM_STATUS=malformed$' "$temp_root/state.log" || fail 'malformed mode state did not fail closed'
expect_failure "$temp_root/malformed-guard.log" run_for "$invalid_project" bash commands/create-task-file.sh malformed-task 'Malformed task' --no-issue
grep -q 'malformed mode state' "$temp_root/malformed-guard.log" || fail 'delivery creation did not fail closed on malformed Brainstorm state'
[[ ! -e "$invalid_project/.ai/tasks/malformed-task" ]] || fail 'malformed Brainstorm guard wrote task state'
write_sample_brainstorm "$invalid_project"
printf '\n### IDEA-001\n' >> "$invalid_project/BRAINSTORM.md"
expect_failure "$temp_root/duplicate.log" run_for "$invalid_project" bash commands/validate-brainstorm.sh --phase active
grep -q 'Duplicate Brainstorm element id' "$temp_root/duplicate.log" || fail 'duplicate element id was not rejected'
write_sample_brainstorm "$invalid_project"
sed -i '0,/^- Branch: BR-002$/s//- Branch: BR-999/' "$invalid_project/BRAINSTORM.md"
expect_failure "$temp_root/missing-branch.log" run_for "$invalid_project" bash commands/validate-brainstorm.sh --phase active
grep -q 'references missing branch BR-999' "$temp_root/missing-branch.log" || fail 'missing idea branch was not rejected'
write_sample_brainstorm "$invalid_project"
sed -i '0,/^- Status: plan-ready$/s//- Status: captured/' "$invalid_project/BRAINSTORM.md"
expect_failure "$temp_root/readiness.log" run_for "$invalid_project" bash commands/validate-brainstorm.sh --phase active
grep -q 'plan readiness must be no' "$temp_root/readiness.log" || fail 'status/readiness mismatch was not rejected'
symlink_project="$(new_project symlink-state)"
write_sample_brainstorm "$symlink_project"
mv "$symlink_project/BRAINSTORM.md" "$temp_root/outside-brainstorm.md"
ln -s "$temp_root/outside-brainstorm.md" "$symlink_project/BRAINSTORM.md"
if [[ -L "$symlink_project/BRAINSTORM.md" ]]; then
  expect_failure "$temp_root/symlink-state.log" run_for "$symlink_project" bash commands/brainstorm-mode.sh status
  grep -q '^BRAINSTORM_STATUS=malformed$' "$temp_root/symlink-state.log" || fail 'symlinked Brainstorm state did not fail closed'
fi

echo '[5/8] generating a complete hash-bound exit index'
write_sample_brainstorm "$project"
stop_dry_hash="$(sha256sum "$project/BRAINSTORM.md" | awk '{print $1}')"
run_for "$project" bash commands/brainstorm-mode.sh stop --dry-run >/dev/null
[[ "$stop_dry_hash" == "$(sha256sum "$project/BRAINSTORM.md" | awk '{print $1}')" ]] || fail 'stop dry-run changed BRAINSTORM.md'
[[ ! -e "$project/BRAINSTORM_SUMMARY.md" ]] || fail 'stop dry-run created a summary'
run_for "$project" bash commands/brainstorm-mode.sh stop >/dev/null
run_for "$project" bash commands/validate-brainstorm.sh --phase inactive >/dev/null
summary_hash="$(sed -n 's/^- Source SHA-256: `\([0-9a-f]\{64\}\)`$/\1/p' "$project/BRAINSTORM_SUMMARY.md")"
[[ "$summary_hash" == "$(sha256sum "$project/BRAINSTORM.md" | awk '{print $1}')" ]] || fail 'summary hash does not bind final BRAINSTORM.md'
[[ "$(grep -Ec '^- \[IDEA-[0-9]{3,}\]' "$project/BRAINSTORM_SUMMARY.md")" -eq 2 ]] || fail 'summary did not contain exactly one entry per element'
grep -q 'IDEA-002.*status: captured.*plan-ready: no' "$project/BRAINSTORM_SUMMARY.md" || fail 'incomplete element was not preserved in the summary'
summary_before_repair="$(sha256sum "$project/BRAINSTORM_SUMMARY.md" | awk '{print $1}')"
rm -f -- "$project/BRAINSTORM_SUMMARY.md"
run_for "$project" bash commands/brainstorm-mode.sh stop >/dev/null
[[ "$summary_before_repair" == "$(sha256sum "$project/BRAINSTORM_SUMMARY.md" | awk '{print $1}')" ]] || fail 'repairing an unchanged exit summary was not deterministic'

echo '[6/8] reactivating without losing ids or history'
run_for "$project" bash commands/brainstorm-mode.sh start >/dev/null
grep -q '^- Active session: BS-002$' "$project/BRAINSTORM.md" || fail 'reactivation did not allocate the next session id'
grep -q '^### IDEA-001$' "$project/BRAINSTORM.md" || fail 'reactivation lost a retained idea'
status_output="$(run_for "$project" bash commands/brainstorm-mode.sh status)"
grep -q '^BRAINSTORM_SUMMARY_CURRENT=no$' <<< "$status_output" || fail 'reactivation did not mark the prior summary stale'
run_for "$project" bash commands/brainstorm-mode.sh stop >/dev/null
run_for "$project" bash commands/validate-brainstorm.sh --phase inactive >/dev/null

echo '[7/8] enforcing delivery-creation guards without changing inactive behavior'
guard_project="$(new_project guards)"
run_for "$guard_project" bash commands/create-task-file.sh existing-task 'Existing task' --no-issue >/dev/null
run_for "$guard_project" bash commands/brainstorm-mode.sh start >/dev/null
expect_failure "$temp_root/task-guard.log" run_for "$guard_project" bash commands/create-task-file.sh blocked-task 'Blocked task' --no-issue
expect_failure "$temp_root/issue-guard.log" run_for "$guard_project" bash commands/create-task-issue.sh blocked-task 'Blocked issue'
expect_failure "$temp_root/import-guard.log" run_for "$guard_project" bash commands/import-task-from-issue.sh '#1'
expect_failure "$temp_root/goal-guard.log" run_for "$guard_project" bash commands/create-goal-file.sh blocked-goal 'Blocked goal'
expect_failure "$temp_root/gauntlet-guard.log" run_for "$guard_project" bash commands/create-gauntlet-file.sh blocked-gauntlet 'Blocked Gauntlet' --task existing-task
for log in task-guard issue-guard import-guard goal-guard gauntlet-guard; do
  grep -q 'blocked while Brainstorm mode is active' "$temp_root/$log.log" || fail "$log did not report the active Brainstorm guard"
done
[[ ! -e "$guard_project/.ai/tasks/blocked-task" && ! -e "$guard_project/.ai/goals/blocked-goal" && ! -e "$guard_project/.ai/gauntlets/blocked-gauntlet" ]] || fail 'a guarded creation command wrote delivery state'
run_for "$guard_project" bash commands/create-goal-file.sh preview-goal 'Preview goal' --dry-run >/dev/null
[[ ! -e "$guard_project/.ai/goals/preview-goal" ]] || fail 'Goal dry-run wrote state'
run_for "$guard_project" bash commands/brainstorm-mode.sh stop >/dev/null
printf '\n' >> "$guard_project/BRAINSTORM.md"
expect_failure "$temp_root/stale-summary-guard.log" run_for "$guard_project" bash commands/create-task-file.sh stale-summary-task 'Stale summary task' --no-issue
grep -q 'lacks a current exit summary' "$temp_root/stale-summary-guard.log" || fail 'stale inactive summary did not fail closed'
run_for "$guard_project" bash commands/brainstorm-mode.sh stop >/dev/null
run_for "$guard_project" bash commands/create-task-file.sh allowed-task 'Allowed task' --no-issue >/dev/null
run_for "$guard_project" bash commands/create-goal-file.sh allowed-goal 'Allowed goal' >/dev/null
[[ -f "$guard_project/.ai/tasks/allowed-task/TASK.md" && -f "$guard_project/.ai/goals/allowed-goal/GOAL.md" ]] || fail 'inactive Brainstorm changed existing creation behavior'

echo '[8/8] checking role, skill, command, and integrated validation hooks'
grep -q '^description:.*Use ' skills/brainstorm-flow/SKILL.md || fail 'brainstorm skill metadata has no trigger'
grep -Fq '$brainstorm-flow' skills/brainstorm-flow/agents/openai.yaml || fail 'brainstorm skill interface metadata is missing'
bash commands/resolve-role.sh researcher | grep -q '^ROLE_ID=computer-science/researcher$' || fail 'researcher role did not resolve'
bash -n commands/lib/brainstorm-common.sh commands/brainstorm-mode.sh commands/validate-brainstorm.sh commands/show-brainstorm.sh \
  commands/create-task-file.sh commands/create-task-issue.sh commands/import-task-from-issue.sh commands/create-goal-file.sh commands/create-gauntlet-file.sh
bash commands/validate-commands.sh >/dev/null
bash commands/validate-skills.sh >/dev/null
bash commands/validate-roles.sh >/dev/null
bash commands/validate-role-skill-map.sh >/dev/null

echo 'Brainstorm flow tests passed.'
