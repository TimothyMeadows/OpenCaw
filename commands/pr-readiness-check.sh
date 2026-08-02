#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/pr-readiness-check.sh [task_or_issue_ref] [validation_summary_file]
       ./commands/pr-readiness-check.sh --goal [task_or_issue_ref] [validation_summary_file]
       ./commands/pr-readiness-check.sh --gauntlet <gauntlet_name_or_path> [validation_summary_file]
       ./commands/pr-readiness-check.sh --gauntlet-progress <gauntlet_name_or_path> <item-id> [validation_summary_file]

Creates a non-destructive PR readiness report and prints the required user
confirmation prompt unless --goal or --gauntlet-progress is supplied. Approved
Gauntlet progress PR publication is automatic, while final promotion requires a
passed, PR-eligible completion report and human confirmation. This command never
commits, pushes, or opens a PR. Progress and remediation PR bodies use a
non-closing `Refs #<issue>` exact first line; only the approved promotion PR
uses `Closes #<issue>` as its exact first line and targets the GitHub default
branch.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

goal_flow=0
gauntlet_flow=0
gauntlet_progress_flow=0
invocation_dir="$(pwd)"

args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --goal)
      goal_flow=1
      shift
      ;;
    --gauntlet)
      gauntlet_flow=1
      shift
      ;;
    --gauntlet-progress)
      gauntlet_progress_flow=1
      shift
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done

mode_count=$((goal_flow + gauntlet_flow + gauntlet_progress_flow))
if [[ $mode_count -gt 1 ]]; then
  echo '--goal, --gauntlet, and --gauntlet-progress are mutually exclusive.' >&2
  exit 1
fi

task_ref="${args[0]:-Unspecified task}"
if [[ $gauntlet_progress_flow -eq 1 ]]; then
  validation_summary_file="${args[2]:-}"
else
  validation_summary_file="${args[1]:-}"
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/gauntlet-common.sh"
opencaw_root="$OPENCAW_ROOT"
host_root="$OPENCAW_PROJECT_ROOT_RESOLVED"
output_dir="${OPENCAW_REPORT_DIR:-$host_root/.ai/reports}"
gauntlet_execution_fingerprint='none'
gauntlet_base_commit_sha='none'
gauntlet_manifest_fingerprint='none'

if [[ $gauntlet_flow -eq 1 ]]; then
  if [[ "${args[0]+set}" != 'set' ]]; then
    echo '--gauntlet requires a Gauntlet name or path.' >&2
    exit 1
  fi
  gauntlet_file="$(gauntlet_resolve_file "${args[0]}")"
  gauntlet_dir="$(cd "$(dirname "$gauntlet_file")" && pwd -P)"
  gauntlet_acquire_lock "$gauntlet_dir"
  trap 'gauntlet_release_lock' EXIT
  gauntlet_validation="$(bash "$script_dir/validate-gauntlet.sh" "$gauntlet_file" --phase complete)" || exit 1
  gauntlet_file="$(awk -F= '$1 == "GAUNTLET_FILE" { sub(/^[^=]*=/, ""); print; exit }' <<< "$gauntlet_validation")"
  gauntlet_report="$(dirname "$gauntlet_file")/GAUNTLET_REPORT.md"
  [[ -f "$gauntlet_report" && ! -L "$gauntlet_report" ]] || {
    echo "Gauntlet completion report is missing: $gauntlet_report" >&2
    exit 1
  }
  if ! grep -Fqx -- '- Completion outcome: complete' "$gauntlet_report" \
    || ! grep -Fqx -- '- Gauntlet status: passed' "$gauntlet_report" \
    || ! grep -Fqx -- '- PR eligible: yes' "$gauntlet_report"; then
    echo "Gauntlet completion report is stopped, blocked, stale, or not PR eligible: $gauntlet_report" >&2
    exit 1
  fi
  gauntlet_promotion_source="$(gauntlet_section_field "$gauntlet_file" 'Delivery' 'Integration branch')"
  gauntlet_promotion_target="$(gauntlet_section_field "$gauntlet_file" 'Delivery' 'Base branch')"
  gauntlet_base_commit_sha="$(gauntlet_section_field "$gauntlet_file" 'Delivery' 'Base commit SHA')"
  gauntlet_base_commit_sha="${gauntlet_base_commit_sha,,}"
  gauntlet_execution_fingerprint="$(gauntlet_assert_frozen_execution_contract "$gauntlet_file")"
  gauntlet_manifest_fingerprint="$(gauntlet_assert_frozen_unit_manifest "$gauntlet_file")"
  if ! grep -Fqx -- "- Execution contract fingerprint: $gauntlet_execution_fingerprint" "$gauntlet_report" \
    || ! grep -Fqx -- "- Unit manifest fingerprint: $gauntlet_manifest_fingerprint" "$gauntlet_report" \
    || ! grep -Fqx -- "- Base commit SHA: $gauntlet_base_commit_sha" "$gauntlet_report"; then
    echo "Gauntlet completion report does not match the frozen execution contract: $gauntlet_report" >&2
    exit 1
  fi
  gauntlet_promotion_source_sha="$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Head SHA')"
  gauntlet_assert_local_branch_at_sha "$gauntlet_promotion_source" "$gauntlet_promotion_source_sha" 'Gauntlet integration branch'
  gauntlet_assert_commit_ancestor "$gauntlet_base_commit_sha" "$gauntlet_promotion_source_sha" 'Promotion readiness approved base'
  gauntlet_assert_remote_integration_tip "$gauntlet_file" "$gauntlet_promotion_source_sha"
fi

gauntlet_progress_item=''
gauntlet_progress_target=''
gauntlet_progress_head=''
gauntlet_remote_integration_state='none'
gauntlet_remote_integration_sha='none'
gauntlet_remote_work_state='none'
gauntlet_remote_work_sha='none'
if [[ $gauntlet_progress_flow -eq 1 ]]; then
  [[ "${args[0]+set}" == 'set' && "${args[1]+set}" == 'set' ]] || {
    echo '--gauntlet-progress requires a Gauntlet name/path and work-unit id.' >&2
    exit 1
  }
  [[ ${#args[@]} -le 3 ]] || { usage >&2; exit 1; }
  gauntlet_progress_item="${args[1]}"
  gauntlet_validate_name "$gauntlet_progress_item" 'Gauntlet progress item id'
  gauntlet_file="$(gauntlet_resolve_file "${args[0]}")"
  gauntlet_dir="$(cd "$(dirname "$gauntlet_file")" && pwd -P)"
  gauntlet_acquire_lock "$gauntlet_dir"
  trap 'gauntlet_release_lock' EXIT
  gauntlet_validation="$(bash "$script_dir/validate-gauntlet.sh" "$gauntlet_file" --phase ready)" || exit 1
  gauntlet_file="$(awk -F= '$1 == "GAUNTLET_FILE" { sub(/^[^=]*=/, ""); print; exit }' <<< "$gauntlet_validation")"
  gauntlet_capture_source_hash "$gauntlet_file"
  gauntlet_dir="$(cd "$(dirname "$gauntlet_file")" && pwd -P)"
  gauntlet_name="$(basename "$gauntlet_dir")"
  gauntlet_execution_fingerprint="$(gauntlet_execution_contract_fingerprint "$gauntlet_file")"
  recorded_execution_fingerprint="$(gauntlet_section_field "$gauntlet_file" 'Current State' 'Execution contract fingerprint')"
  [[ "$recorded_execution_fingerprint" == 'pending' \
    || "${recorded_execution_fingerprint,,}" == "$gauntlet_execution_fingerprint" ]] || {
    echo 'Gauntlet execution contract changed after progress-PR publication was authorized.' >&2
    exit 1
  }
  gauntlet_base_commit_sha="$(gauntlet_section_field "$gauntlet_file" 'Delivery' 'Base commit SHA')"
  gauntlet_base_commit_sha="${gauntlet_base_commit_sha,,}"
  gauntlet_status="$(gauntlet_section_field "$gauntlet_file" 'Flow and Status' 'Status')"
  case "$gauntlet_status" in
    ready|running) ;;
    passed) echo 'A passed Gauntlet must be reopened by a recorded promotion-QA failure before publishing remediation work.' >&2; exit 1 ;;
    *) echo "Gauntlet progress PR publication requires ready or running status, not $gauntlet_status." >&2; exit 1 ;;
  esac
  progress_unit_line="$(gauntlet_work_unit_lines "$gauntlet_file" | awk -v item="$gauntlet_progress_item" '$0 ~ "^- \\[[ xX]\\] " item " \\|" { print; exit }')"
  [[ -n "$progress_unit_line" ]] || { echo "Unknown Gauntlet work-unit id: $gauntlet_progress_item" >&2; exit 1; }
  [[ ! "$progress_unit_line" =~ \|[[:space:]]status:[[:space:]]superseded[[:space:]]\| ]] || {
    echo "Superseded work units cannot publish progress PRs: $gauntlet_progress_item" >&2
    exit 1
  }
  gauntlet_load_latest_progress_pr "$gauntlet_dir" "$gauntlet_progress_item"
  remediation_trigger='none'
  if [[ -n "$GAUNTLET_PROGRESS_EVENT_FILE" \
    && "$GAUNTLET_PROGRESS_EVENT" != 'merged' \
    && "$GAUNTLET_PROGRESS_EVENT" != 'closed' ]]; then
    echo "Work unit already has a live progress PR: $GAUNTLET_PROGRESS_PR_URL" >&2
    exit 1
  fi
  gauntlet_progress_target="$(gauntlet_section_field "$gauntlet_file" 'Delivery' 'Integration branch')"
  opened_count=0
  if [[ -d "$gauntlet_dir/pr-events/$gauntlet_progress_item" ]]; then
    while IFS= read -r prior_event_file; do
      [[ "$(gauntlet_section_field "$prior_event_file" 'PR Event Metadata' 'Event')" == 'opened' ]] \
        && opened_count=$((opened_count + 1))
    done < <(find "$gauntlet_dir/pr-events/$gauntlet_progress_item" -maxdepth 1 -type f -name 'event-*.md' -print)
  fi
  if [[ $opened_count -eq 0 ]]; then
    gauntlet_progress_head="gauntlet-work/$gauntlet_name/$gauntlet_progress_item"
    if inherited_trigger="$(gauntlet_remediation_trigger "$gauntlet_file" "$gauntlet_progress_item" '')"; then
      remediation_trigger="$inherited_trigger"
    fi
  else
    gauntlet_progress_head="gauntlet-work/$gauntlet_name/$gauntlet_progress_item-remediation-$opened_count"
    remediation_trigger="$(gauntlet_remediation_trigger "$gauntlet_file" "$gauntlet_progress_item" "$GAUNTLET_PROGRESS_EVENT_FILE")" || {
      echo 'A merged progress PR may reopen only after a later integration failure/block, a promotion-QA failure naming this unit, or an approved quality-bar revision reset.' >&2
      exit 1
    }
    while IFS= read -r prior_event_file; do
      if grep -Fqx -- "- Remediation trigger: $remediation_trigger" "$prior_event_file"; then
        echo "Remediation trigger was already consumed for this work unit: $remediation_trigger" >&2
        exit 1
      fi
    done < <(find "$gauntlet_dir/pr-events/$gauntlet_progress_item" -maxdepth 1 -type f -name 'event-*.md' -print)
  fi
  gauntlet_progress_head_sha="$(gauntlet_local_branch_sha "$gauntlet_progress_head" 'Gauntlet progress branch')"
  gauntlet_assert_commit_object "$gauntlet_progress_head_sha" 'Gauntlet progress branch SHA'
  gauntlet_assert_remote_progress_preflight \
    "$gauntlet_file" "$gauntlet_progress_head" "$gauntlet_progress_head_sha"
  gauntlet_remote_integration_state="$GAUNTLET_REMOTE_INTEGRATION_STATE"
  gauntlet_remote_integration_sha="$GAUNTLET_REMOTE_INTEGRATION_SHA"
  gauntlet_remote_work_state="$GAUNTLET_REMOTE_WORK_STATE"
  gauntlet_remote_work_sha="$GAUNTLET_REMOTE_WORK_SHA"
  gauntlet_progress_chain_tip="$(gauntlet_progress_merge_chain_tip "$gauntlet_file")"
  gauntlet_assert_commit_ancestor "$gauntlet_progress_chain_tip" "$gauntlet_progress_head_sha" \
    'Gauntlet progress branch from current integration chain tip'
  gauntlet_progress_quality_fingerprint="$(gauntlet_quality_bar_fingerprint "$gauntlet_file")"
  gauntlet_progress_quality_approved_at="$(gauntlet_section_field \
    "$gauntlet_file" 'Approved Quality Bar' 'Approved at')"
  gauntlet_progress_scope_fingerprint="$(gauntlet_unit_scope_fingerprint "$gauntlet_file" "$gauntlet_progress_item")"
  gauntlet_progress_manifest_fingerprint="$(gauntlet_unit_manifest_fingerprint "$gauntlet_file")"
  gauntlet_progress_manifest_approved_at="$(gauntlet_unit_manifest_approved_at \
    "$gauntlet_file" "$gauntlet_progress_manifest_fingerprint")"
  remediation_trigger_hash="$(gauntlet_remediation_trigger_hash "$gauntlet_file" "$remediation_trigger")"
  checkpoint_recorded_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  [[ "$gauntlet_progress_quality_approved_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ \
    && ( "$gauntlet_progress_quality_approved_at" < "$checkpoint_recorded_at" \
      || "$gauntlet_progress_quality_approved_at" == "$checkpoint_recorded_at" ) ]] || {
    echo 'Approved Quality Bar timestamp must be canonical UTC and no later than the publication checkpoint.' >&2
    exit 1
  }
  [[ "$gauntlet_progress_manifest_approved_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ \
    && ( "$gauntlet_progress_manifest_approved_at" < "$checkpoint_recorded_at" \
      || "$gauntlet_progress_manifest_approved_at" == "$checkpoint_recorded_at" ) ]] || {
    echo 'Approved Unit manifest timestamp must be canonical UTC and no later than the publication checkpoint.' >&2
    exit 1
  }
  remediation_root="$(gauntlet_remediation_root_for_trigger \
    "$gauntlet_file" "$gauntlet_progress_item" "$remediation_trigger" "$checkpoint_recorded_at")"
  if [[ "$remediation_root" == 'none' ]]; then
    remediation_root_hash='none'
  else
    remediation_root_hash="$(gauntlet_hash_file "$OPENCAW_PROJECT_ROOT_RESOLVED/$remediation_root")"
  fi

  checkpoint_dir="$gauntlet_dir/publication-checkpoints/$gauntlet_progress_item"
  if [[ -e "$gauntlet_dir/publication-checkpoints" || -L "$gauntlet_dir/publication-checkpoints" ]]; then
    gauntlet_assert_safe_ai_path "$gauntlet_dir/publication-checkpoints" 'Gauntlet publication checkpoints directory'
  fi
  if [[ -e "$checkpoint_dir" || -L "$checkpoint_dir" ]]; then
    gauntlet_assert_safe_ai_path "$checkpoint_dir" 'Gauntlet item publication checkpoints directory'
  fi
  max_checkpoint=0
  if [[ -d "$checkpoint_dir" ]]; then
    while IFS= read -r existing_checkpoint; do
      checkpoint_name="$(basename "$existing_checkpoint")"
      if [[ "$checkpoint_name" =~ ^checkpoint-([0-9]+)\.md$ ]]; then
        checkpoint_number=$((10#${BASH_REMATCH[1]}))
        (( checkpoint_number > max_checkpoint )) && max_checkpoint=$checkpoint_number
      fi
    done < <(find "$checkpoint_dir" -maxdepth 1 -type f -name 'checkpoint-*.md' -print)
  fi
  next_checkpoint=$((max_checkpoint + 1))
  printf -v checkpoint_label '%03d' "$next_checkpoint"
  gauntlet_publication_checkpoint_relative=".ai/gauntlets/$gauntlet_name/publication-checkpoints/$gauntlet_progress_item/checkpoint-$checkpoint_label.md"
  gauntlet_publication_checkpoint="$OPENCAW_PROJECT_ROOT_RESOLVED/$gauntlet_publication_checkpoint_relative"
  checkpoint_stage="$(mktemp "$gauntlet_dir/.publication-checkpoint-stage.XXXXXX")"
  checkpoint_root_created=0
  checkpoint_dir_created=0
  cleanup_publication_checkpoint_stage() {
    rm -f "${checkpoint_stage:-}"
    if [[ $checkpoint_dir_created -eq 1 ]]; then
      rmdir "$checkpoint_dir" 2>/dev/null || true
    fi
    if [[ $checkpoint_root_created -eq 1 ]]; then
      rmdir "$gauntlet_dir/publication-checkpoints" 2>/dev/null || true
    fi
    gauntlet_release_lock
  }
  trap cleanup_publication_checkpoint_stage EXIT
  cat > "$checkpoint_stage" <<EOF
# Gauntlet Publication Checkpoint: $gauntlet_progress_item / $checkpoint_label

## Publication Checkpoint Metadata
- Item: $gauntlet_progress_item
- Sequence: $checkpoint_label
- Head branch: $gauntlet_progress_head
- Head SHA: $gauntlet_progress_head_sha
- Target branch: $gauntlet_progress_target
- Chain tip: $gauntlet_progress_chain_tip
- Remediation trigger: $remediation_trigger
- Remediation trigger sha256: $remediation_trigger_hash
- Remediation root: $remediation_root
- Remediation root sha256: $remediation_root_hash
- Quality bar fingerprint: $gauntlet_progress_quality_fingerprint
- Quality bar approved at: $gauntlet_progress_quality_approved_at
- Unit scope fingerprint: $gauntlet_progress_scope_fingerprint
- Unit manifest fingerprint: $gauntlet_progress_manifest_fingerprint
- Unit manifest approved at: $gauntlet_progress_manifest_approved_at
- Execution contract fingerprint: $gauntlet_execution_fingerprint
- Remote integration state: $gauntlet_remote_integration_state
- Remote integration SHA: $gauntlet_remote_integration_sha
- Remote work state: $gauntlet_remote_work_state
- Remote work SHA: $gauntlet_remote_work_sha
- Recorded at: $checkpoint_recorded_at
EOF
  chmod 0644 "$checkpoint_stage"
  gauntlet_publication_checkpoint_hash="$(gauntlet_hash_file "$checkpoint_stage")"
  gauntlet_assert_source_hash
  [[ -d "$gauntlet_dir/publication-checkpoints" ]] || checkpoint_root_created=1
  [[ -d "$checkpoint_dir" ]] || checkpoint_dir_created=1
  mkdir -p "$checkpoint_dir"
  gauntlet_assert_safe_ai_path "$checkpoint_dir" 'Gauntlet item publication checkpoints directory'
  gauntlet_install_no_clobber "$checkpoint_stage" "$gauntlet_publication_checkpoint"
  checkpoint_stage=''
  if ! gauntlet_assert_source_hash; then
    rm -f "$gauntlet_publication_checkpoint"
    echo 'GAUNTLET.md changed during publication preflight; checkpoint creation was rolled back.' >&2
    exit 1
  fi
  gauntlet_publication_marker="<!-- opencaw-gauntlet-publication:v1 checkpoint=$gauntlet_publication_checkpoint_relative checkpoint-sha256=$gauntlet_publication_checkpoint_hash -->"
  task_ref="${args[0]}/$gauntlet_progress_item"
fi

gauntlet_issue_number='none'
if [[ $gauntlet_flow -eq 1 || $gauntlet_progress_flow -eq 1 ]]; then
  gauntlet_issue_url="$(gauntlet_section_field "$gauntlet_file" 'Parent Task' 'Issue')"
  gauntlet_issue_number="$(gauntlet_github_issue_number "$gauntlet_issue_url")" || exit 1
fi

detect_repo_root() {
  if git -C "$host_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf '%s\n' "$host_root"
    return
  fi

  if git -C "$opencaw_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf '%s\n' "$opencaw_root"
    return
  fi

  echo "Unable to detect a git repository root for PR readiness." >&2
  exit 1
}

repo_root="$(detect_repo_root)"
mkdir -p "$output_dir"

pushd "$repo_root" >/dev/null

repo_name="$(basename "$repo_root")"
branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || printf 'unknown')"
last_commit="$(git log -1 --oneline 2>/dev/null || printf 'No commits found')"
status_short="$(git status --short 2>/dev/null || true)"
if [[ -z "$status_short" ]]; then
  status_short="Working tree clean"
fi

upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
ahead_behind="No upstream configured"
if [[ -n "$upstream" ]]; then
  ahead_behind="$(git rev-list --left-right --count "$upstream...HEAD" 2>/dev/null | awk '{print "behind="$1" ahead="$2}' || printf 'Unable to calculate ahead/behind')"
fi

validation_summary="No validation summary file supplied. Include commands run, pass/fail status, and any residual risk before asking for PR approval."
if [[ -n "$validation_summary_file" ]]; then
  validation_summary_path="$validation_summary_file"
  if [[ "$validation_summary_path" != /* ]]; then
    validation_summary_path="$invocation_dir/$validation_summary_path"
  fi

  if [[ ! -f "$validation_summary_path" ]]; then
    echo "Validation summary file not found: $validation_summary_file" >&2
    exit 1
  fi
  validation_summary="$(cat "$validation_summary_path")"
fi

stamp="$(date -u +"%Y%m%d-%H%M%S")"
report_file="$output_dir/pr-readiness-$stamp.md"

if [[ $goal_flow -eq 1 ]]; then
  checkpoint_heading="## Goal Flow Automation Checkpoint"
  checkpoint_body="Goal flow is active for this task. This is the only OpenCaw exception to the human PR readiness approval prompt.

Because the user explicitly selected goal flow, the agent may automatically push/open a PR for this completed task after local validation is complete. Goal flow must not merge PRs, approve PRs, or enable auto-merge.

The agent must still:

1. Confirm the PR is available using the GitHub tool priority below.
2. Start post-PR QA immediately.
3. Post QA pass/fail evidence to the PR.
4. Record branch dependency when a later goal task should be based on this task branch or PR head.
5. Stop goal automation if PR creation or post-PR QA fails.
6. Move to the next goal task only after post-PR QA completes."
  next_steps_heading="## Automated Goal-Flow Next Steps"
  next_steps_body="1. Push/open the PR after local validation is complete.
2. Confirm the PR is available using the GitHub tool priority above.
3. Start task QA immediately.
4. Post QA pass/fail evidence to the PR using GitHub comments.
5. Include inline screenshot URLs when screenshots are part of the evidence.
6. If the next goal task depends on this unmerged work or risks conflicts later, branch it from this task branch or PR head.
7. Move to the next goal task only after QA is complete.
8. Never merge, approve, or enable auto-merge from goal flow."
elif [[ $gauntlet_progress_flow -eq 1 ]]; then
  checkpoint_heading="## Automated Gauntlet Progress Publication Checkpoint"
  checkpoint_body="The user-approved Gauntlet delivery contract authorizes automatic publication of this work-unit progress PR.

Publish the unit branch as a PR into the durable integration branch. This automation does not authorize merge, approval, auto-merge, or promotion to the delivery base."
  next_steps_heading="## Automated Gauntlet Progress Next Steps"
  remote_creation_requirement=''
  if [[ "$gauntlet_remote_integration_state" == 'absent-create-only' ]]; then
    remote_creation_requirement=" The integration ref is absent at origin before the first immutable event; create it only with a no-force, no-overwrite operation at the exact frozen chain tip, abort if the ref appears, then re-run this preflight."
  fi
  next_steps_body="1.$remote_creation_requirement Push/open the work-unit progress PR from \`$gauntlet_progress_head\` into \`$gauntlet_progress_target\`. Use \`Refs #$gauntlet_issue_number\` as the exact first PR-body line, then include this exact marker: \`$gauntlet_publication_marker\`. If either remote ref changes, abort and re-run readiness; never force-update either ref.
2. Confirm the PR is available using the GitHub tool priority above.
3. Record its \`opened\` event with \`record-gauntlet-pr-event.sh ... --head-sha <observed-full-sha>\`.
4. Run the fresh critic and per-progress-PR QA, posting evidence to that PR.
5. Record the QA event with its observed \`--head-sha\`; a QA failure reopens the unit and requires a new commit, changed builder strategy, and fresh critic round.
6. Leave merge approval and merge execution to a human.
7. Never enable auto-merge or promote the integration branch from this checkpoint."
elif [[ $gauntlet_flow -eq 1 ]]; then
  checkpoint_heading="## Required Gauntlet Human Checkpoint"
  checkpoint_body="Gauntlet flow passed every active work unit, retained its ordered progress-PR/QA history, and passed its latest independent integration review at commit \`$gauntlet_promotion_source_sha\`. The final promotion PR remains human-gated and does not inherit progress publication automation.

Before any PR-related push or PR creation, ask the user:

> The Gauntlet passed its progressive reviews and final integration check. Are you ready for me to open the promotion pull request from \`$gauntlet_promotion_source\` to \`$gauntlet_promotion_target\`?

Do not run \`git push\`, \`gh pr create\`, \`github\` CLI PR creation, GitHub MCP/connector PR creation tools, auto-merge, or PR update automation until the user explicitly confirms."
  next_steps_heading="## After Gauntlet Confirmation"
  next_steps_body="1. Verify \`$gauntlet_promotion_source\` still resolves to reviewed commit \`$gauntlet_promotion_source_sha\`, then push/open its final promotion PR to the verified GitHub default branch \`$gauntlet_promotion_target\` only after the user confirms readiness. Use \`Closes #$gauntlet_issue_number\` as the exact first PR-body line so only this promotion PR closes the parent issue.
2. Confirm the PR is available using the GitHub tool priority above.
3. Link the ordered progress PR and QA ledger in the promotion PR.
4. Start post-promotion QA immediately.
5. Post QA pass/fail evidence to the promotion PR using GitHub comments.
6. If post-promotion QA fails, publish affected remediation progress PRs into the same integration branch, rerun integration review, update the promotion PR, and repeat QA.
7. Never merge, approve, or enable auto-merge from Gauntlet flow."
else
  checkpoint_heading="## Required Human Checkpoint"
  checkpoint_body="Before any PR-related push or PR creation, ask the user:

> The implementation is complete enough for your validation. Are you ready for me to push this branch and open a pull request?

Do not run \`git push\`, \`gh pr create\`, \`github\` CLI PR creation, GitHub MCP/connector PR creation tools, auto-merge, or PR update automation until the user explicitly confirms."
  next_steps_heading="## After Confirmation"
  next_steps_body="1. Push/open the PR only after the user confirms readiness.
2. Confirm the PR is available using the GitHub tool priority above.
3. Start task QA immediately.
4. Post QA pass/fail evidence to the PR using GitHub comments.
5. Include inline screenshot URLs when screenshots are part of the evidence.
6. Notify the user when QA is complete and the PR is ready for review."
fi

gauntlet_summary_fields=''
if [[ $gauntlet_flow -eq 1 || $gauntlet_progress_flow -eq 1 ]]; then
  gauntlet_summary_fields="- Execution contract fingerprint: \`$gauntlet_execution_fingerprint\`
- Unit manifest fingerprint: \`$([[ $gauntlet_progress_flow -eq 1 ]] && printf '%s' "$gauntlet_progress_manifest_fingerprint" || printf '%s' "$gauntlet_manifest_fingerprint")\`
- Gauntlet base commit SHA: \`$gauntlet_base_commit_sha\`"
  if [[ $gauntlet_progress_flow -eq 1 ]]; then
    gauntlet_summary_fields="$gauntlet_summary_fields
- Remote integration preflight: \`$gauntlet_remote_integration_state:$gauntlet_remote_integration_sha\`
- Remote work-ref preflight: \`$gauntlet_remote_work_state:$gauntlet_remote_work_sha\`
- Publication checkpoint: \`$gauntlet_publication_checkpoint_relative\`
- Publication checkpoint sha256: \`$gauntlet_publication_checkpoint_hash\`"
  fi
fi

cat >"$report_file" <<EOF
# PR Readiness Gate

## Summary

- Generated: $(date -u +"%Y-%m-%d %H:%M:%SZ")
- Repository: \`$repo_name\`
- Repository root: \`$repo_root\`
- Task or issue: \`$task_ref\`
- Branch: \`$branch\`
- Upstream: \`${upstream:-none}\`
- Ahead/behind: \`$ahead_behind\`
- Last commit: \`$last_commit\`
- Goal flow: \`$([[ $goal_flow -eq 1 ]] && printf 'enabled' || printf 'disabled')\`
- Gauntlet flow: \`$([[ $gauntlet_flow -eq 1 || $gauntlet_progress_flow -eq 1 ]] && printf 'enabled' || printf 'disabled')\`
- Gauntlet progress publication: \`$([[ $gauntlet_progress_flow -eq 1 ]] && printf 'enabled' || printf 'disabled')\`
$gauntlet_summary_fields

## Working Tree

\`\`\`
$status_short
\`\`\`

## Validation Supplied

\`\`\`
$validation_summary
\`\`\`

$checkpoint_heading

$checkpoint_body

## GitHub Tool Priority

When choosing a tool for GitHub PR work, use:

1. \`gh\` from the local shell
2. an available \`github\` CLI executable or repository-provided GitHub CLI wrapper
3. GitHub MCP/app connector tools only when both CLI options are unavailable or unsuitable

$next_steps_heading

$next_steps_body
EOF

popd >/dev/null

if [[ $gauntlet_flow -eq 1 || $gauntlet_progress_flow -eq 1 ]]; then
  gauntlet_release_lock
  trap - EXIT
fi

echo "REPORT_FILE=$report_file"
if [[ $goal_flow -eq 1 ]]; then
  echo "USER_CONFIRMATION_REQUIRED=NO"
  echo "GOAL_FLOW_AUTOMATION=YES"
  echo "GAUNTLET_FLOW=NO"
  echo "GAUNTLET_PROGRESS_AUTOMATION=NO"
  echo "PROMPT=Goal flow is active. Automatically push/open the PR for this completed task, run post-PR QA, then continue to the next goal task only after QA completes."
elif [[ $gauntlet_progress_flow -eq 1 ]]; then
  echo "USER_CONFIRMATION_REQUIRED=NO"
  echo "GOAL_FLOW_AUTOMATION=NO"
  echo "GAUNTLET_FLOW=YES"
  echo "GAUNTLET_PROGRESS_AUTOMATION=YES"
  echo "HEAD_BRANCH=$gauntlet_progress_head"
  echo "HEAD_SHA=$gauntlet_progress_head_sha"
  echo "TARGET_BRANCH=$gauntlet_progress_target"
  echo "EXECUTION_CONTRACT_FINGERPRINT=$gauntlet_execution_fingerprint"
  echo "BASE_COMMIT_SHA=$gauntlet_base_commit_sha"
  echo "UNIT_MANIFEST_FINGERPRINT=$gauntlet_progress_manifest_fingerprint"
  echo "PUBLICATION_CHECKPOINT=$gauntlet_publication_checkpoint_relative"
  echo "PUBLICATION_CHECKPOINT_SHA256=$gauntlet_publication_checkpoint_hash"
  echo "PUBLICATION_MARKER=$gauntlet_publication_marker"
  echo "ISSUE_LINK=Refs #$gauntlet_issue_number"
  echo "PROMPT=Gauntlet approval authorizes automatic publication of this work-unit progress PR into the integration branch; record its PR event and QA evidence, but leave merge to a human."
elif [[ $gauntlet_flow -eq 1 ]]; then
  echo "USER_CONFIRMATION_REQUIRED=YES"
  echo "GOAL_FLOW_AUTOMATION=NO"
  echo "GAUNTLET_FLOW=YES"
  echo "GAUNTLET_PROGRESS_AUTOMATION=NO"
  echo "SOURCE_BRANCH=$gauntlet_promotion_source"
  echo "SOURCE_SHA=$gauntlet_promotion_source_sha"
  echo "TARGET_BRANCH=$gauntlet_promotion_target"
  echo "EXECUTION_CONTRACT_FINGERPRINT=$gauntlet_execution_fingerprint"
  echo "UNIT_MANIFEST_FINGERPRINT=$gauntlet_manifest_fingerprint"
  echo "BASE_COMMIT_SHA=$gauntlet_base_commit_sha"
  echo "ISSUE_LINK=Closes #$gauntlet_issue_number"
  echo "PROMPT=The Gauntlet passed its progressive reviews and final integration check. Are you ready for me to open the promotion pull request from $gauntlet_promotion_source to $gauntlet_promotion_target?"
else
  echo "USER_CONFIRMATION_REQUIRED=YES"
  echo "GOAL_FLOW_AUTOMATION=NO"
  echo "GAUNTLET_FLOW=NO"
  echo "GAUNTLET_PROGRESS_AUTOMATION=NO"
  echo "PROMPT=The implementation is complete enough for your validation. Are you ready for me to push this branch and open a pull request?"
fi
