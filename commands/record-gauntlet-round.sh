#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/record-gauntlet-round.sh "<gauntlet>" "<item-id>" "<verdict>" "<builder-id>" "<critic-id>" "<native-subagent|fresh-session>" "<critic-report.md>" [--dry-run]

Records immutable critic evidence as rounds/<item-id>/round-NNN.md and updates
the Gauntlet work-unit state and round ledger only after all checks pass. Use the
reserved item id "integration" for the final independent integration review.
EOF
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/gauntlet-common.sh"
invocation_dir="$(pwd)"

dry_run=0
positional=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) dry_run=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --*) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    *) positional+=("$1"); shift ;;
  esac
done

[[ ${#positional[@]} -eq 7 ]] || { usage >&2; exit 1; }
gauntlet_ref="${positional[0]}"
item_id="${positional[1]}"
verdict="${positional[2]}"
builder_id="${positional[3]}"
critic_id="${positional[4]}"
isolation="${positional[5]}"
critic_report="${positional[6]}"

if [[ "$item_id" != 'integration' ]]; then
  gauntlet_validate_name "$item_id" 'item-id'
fi
case "$verdict" in pass|fail|blocked) ;; *) echo "verdict must be pass, fail, or blocked: $verdict" >&2; exit 1 ;; esac
gauntlet_validate_identifier "$builder_id" 'builder-id'
gauntlet_validate_identifier "$critic_id" 'critic-id'
[[ "$builder_id" != "$critic_id" ]] || { echo 'Builder and critic IDs must be distinct.' >&2; exit 1; }
case "$isolation" in native-subagent|fresh-session) ;; *) echo "Invalid critic isolation: $isolation" >&2; exit 1 ;; esac

if [[ "$critic_report" != /* ]]; then
  critic_report="$invocation_dir/$critic_report"
fi
[[ -f "$critic_report" ]] || { echo "Critic report not found: ${positional[6]}" >&2; exit 1; }

gauntlet_file="$(gauntlet_resolve_file "$gauntlet_ref")"
gauntlet_dir="$(cd "$(dirname "$gauntlet_file")" && pwd -P)"
gauntlet_name="$(basename "$gauntlet_dir")"
if [[ -e "$gauntlet_dir/rounds" || -L "$gauntlet_dir/rounds" ]]; then
  gauntlet_assert_safe_ai_path "$gauntlet_dir/rounds" 'Gauntlet rounds directory'
fi
bash "$script_dir/validate-gauntlet.sh" "$gauntlet_file" --phase ready >/dev/null

if [[ -d "$gauntlet_dir/rounds" ]]; then
  while IFS= read -r prior_round; do
    if grep -Fqx -- "- Critic ID: $critic_id" "$prior_round"; then
      echo "Critic invocation ID has already been used in this Gauntlet: $critic_id" >&2
      exit 1
    fi
  done < <(find "$gauntlet_dir/rounds" -type f -name 'round-*.md' -print)
fi

gauntlet_validate_critic_report "$critic_report" "$verdict"
quality_fingerprint="$(gauntlet_quality_bar_fingerprint "$gauntlet_file")"
recorded_fingerprint="$(gauntlet_section_field "$gauntlet_file" 'Current State' 'Quality bar fingerprint')"
if [[ "$recorded_fingerprint" != 'pending' && "${recorded_fingerprint,,}" != "${quality_fingerprint,,}" ]]; then
  echo 'Approved Quality Bar changed after it was frozen; no round was recorded.' >&2
  exit 1
fi

if [[ "$item_id" == 'integration' ]]; then
  while IFS= read -r unit_line; do
    if [[ "$unit_line" =~ \|[[:space:]]status:[[:space:]]superseded[[:space:]]\| ]]; then
      continue
    fi
    if [[ ! "$unit_line" =~ ^-[[:space:]]\[[xX]\].*\|[[:space:]]status:[[:space:]]passed[[:space:]]\| ]]; then
      echo "Integration review requires every active work unit to pass first: $unit_line" >&2
      exit 1
    fi
  done < <(gauntlet_work_unit_lines "$gauntlet_file")
else
  unit_line="$(gauntlet_work_unit_lines "$gauntlet_file" | awk -v item="$item_id" '$0 ~ "^- \\[[ xX]\\] " item " \\|" { print; exit }')"
  [[ -n "$unit_line" ]] || { echo "Unknown work-unit id: $item_id" >&2; exit 1; }
  if [[ "$unit_line" =~ \|[[:space:]]status:[[:space:]]superseded[[:space:]]\| ]]; then
    echo "Cannot record a round for superseded work unit: $item_id" >&2
    exit 1
  fi
fi

item_round_dir="$gauntlet_dir/rounds/$item_id"
if [[ -e "$item_round_dir" || -L "$item_round_dir" ]]; then
  gauntlet_assert_safe_ai_path "$item_round_dir" 'Gauntlet item rounds directory'
fi
max_round=0
if [[ -d "$item_round_dir" ]]; then
  while IFS= read -r existing_round; do
    existing_name="$(basename "$existing_round")"
    if [[ "$existing_name" =~ ^round-([0-9]+)\.md$ ]]; then
      existing_number=$((10#${BASH_REMATCH[1]}))
      (( existing_number > max_round )) && max_round=$existing_number
    fi
  done < <(find "$item_round_dir" -maxdepth 1 -type f -name 'round-*.md' -print)
fi
next_round=$((max_round + 1))
printf -v round_label '%03d' "$next_round"
round_relative=".ai/gauntlets/$gauntlet_name/rounds/$item_id/round-$round_label.md"
round_target="$OPENCAW_PROJECT_ROOT_RESOLVED/$round_relative"
[[ ! -e "$round_target" ]] || { echo "Round evidence already exists: $round_relative" >&2; exit 1; }

if [[ "$verdict" != 'pass' && -d "$item_round_dir" ]]; then
  while IFS= read -r previous_round; do
    [[ -n "$previous_round" ]] || continue
    previous_verdict="$(gauntlet_section_field "$previous_round" 'Round Metadata' 'Verdict')"
    previous_strategy="$(gauntlet_section_field "$previous_round" 'Round Metadata' 'Strategy fingerprint')"
    previous_bar="$(gauntlet_section_field "$previous_round" 'Round Metadata' 'Quality bar fingerprint')"
    if [[ "$previous_bar" == "$quality_fingerprint" \
      && "$previous_verdict" != 'pass' \
      && "$previous_strategy" == "$GAUNTLET_CRITIC_STRATEGY_FINGERPRINT" ]]; then
      echo "Failed or blocked rounds require a changed strategy; this strategy repeats $(basename "$previous_round")." >&2
      exit 1
    fi
  done < <(find "$item_round_dir" -maxdepth 1 -type f -name 'round-*.md' -print | LC_ALL=C sort)
fi

recorded_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
round_stage="$(mktemp "${TMPDIR:-/tmp}/opencaw-gauntlet-round.XXXXXX")"
main_stage="$(mktemp "${TMPDIR:-/tmp}/opencaw-gauntlet-main.XXXXXX")"
trap 'rm -f "$round_stage" "$main_stage"' EXIT

cat > "$round_stage" <<EOF
# Gauntlet Round: $item_id / $round_label

## Round Metadata
- Item: $item_id
- Round: $round_label
- Verdict: $verdict
- Builder ID: $builder_id
- Critic ID: $critic_id
- Isolation: $isolation
- Quality bar fingerprint: $quality_fingerprint
- Strategy fingerprint: $GAUNTLET_CRITIC_STRATEGY_FINGERPRINT
- Recorded at: $recorded_at

EOF
sed 's/\r$//' "$critic_report" >> "$round_stage"
printf '\n' >> "$round_stage"
round_hash="$(gauntlet_hash_file "$round_stage")"

cp "$gauntlet_file" "$main_stage"
gauntlet_set_section_field "$main_stage" 'Current State' 'Quality bar fingerprint' "$quality_fingerprint"
gauntlet_set_section_field "$main_stage" 'Current State' 'Latest round' "$item_id/$round_label ($verdict)"
gauntlet_set_section_field "$main_stage" 'Current State' 'Active work unit' "$item_id"
gauntlet_set_section_field "$main_stage" 'Delivery' 'PR eligible' 'no'

if [[ "$item_id" == 'integration' ]]; then
  gauntlet_set_section_field "$main_stage" 'Integration Review' 'Verdict' "$verdict"
  gauntlet_set_section_field "$main_stage" 'Integration Review' 'Critic ID' "$critic_id"
  gauntlet_set_section_field "$main_stage" 'Integration Review' 'Isolation' "$isolation"
  gauntlet_set_section_field "$main_stage" 'Integration Review' 'Evidence' "\`$round_relative\`"
  gauntlet_set_section_field "$main_stage" 'Integration Review' 'Quality bar fingerprint' "$quality_fingerprint"
  case "$verdict" in
    pass)
      gauntlet_set_section_field "$main_stage" 'Flow and Status' 'Status' 'running'
      gauntlet_set_section_field "$main_stage" 'Current State' 'Active work unit' 'none'
      gauntlet_set_section_field "$main_stage" 'Current State' 'Next action' 'Generate the Gauntlet completion report and pass the human PR readiness gate.'
      ;;
    fail)
      gauntlet_reopen_active_units "$main_stage"
      gauntlet_set_section_field "$main_stage" 'Flow and Status' 'Status' 'running'
      gauntlet_set_section_field "$main_stage" 'Current State' 'Next action' 'Rebuild every reopened active unit with changed strategies, then run a fresh integration critic.'
      ;;
    blocked)
      gauntlet_set_section_field "$main_stage" 'Flow and Status' 'Status' 'blocked'
      gauntlet_set_section_field "$main_stage" 'Current State' 'Next action' 'Resolve the recorded integration blocker or generate a blocked completion report.'
      ;;
  esac
else
  case "$verdict" in
    pass)
      unit_status='passed'
      next_action='Continue remaining work units or run the fresh integration critic when all active units pass.'
      ;;
    fail)
      unit_status='critic-failed'
      next_action='Rebuild this work unit using the critic changed strategy, then use a new critic invocation.'
      ;;
    blocked)
      unit_status='blocked'
      next_action='Resolve the recorded blocker or generate a blocked completion report.'
      ;;
  esac
  gauntlet_set_work_unit_status "$main_stage" "$item_id" "$unit_status"
  gauntlet_set_section_field "$main_stage" 'Flow and Status' 'Status' "$([[ "$verdict" == 'blocked' ]] && printf blocked || printf running)"
  gauntlet_set_section_field "$main_stage" 'Current State' 'Next action' "$next_action"

  # Any unit work after an integration review invalidates that integration pass.
  if [[ "$(gauntlet_section_field "$main_stage" 'Integration Review' 'Verdict')" != 'pending' ]]; then
    gauntlet_set_section_field "$main_stage" 'Integration Review' 'Verdict' 'pending'
    gauntlet_set_section_field "$main_stage" 'Integration Review' 'Critic ID' ''
    gauntlet_set_section_field "$main_stage" 'Integration Review' 'Isolation' ''
    gauntlet_set_section_field "$main_stage" 'Integration Review' 'Evidence' ''
    gauntlet_set_section_field "$main_stage" 'Integration Review' 'Quality bar fingerprint' 'pending'
  fi
fi

ledger_entry="- $item_id | round: $round_label | verdict: $verdict | builder: $builder_id | critic: $critic_id | isolation: $isolation | evidence: $round_relative | sha256: $round_hash"
gauntlet_append_round_ledger "$main_stage" "$ledger_entry"
chmod 0644 "$main_stage" "$round_stage"

if [[ $dry_run -eq 1 ]]; then
  echo "Dry run: would create $round_target"
  echo "GAUNTLET_FILE=$gauntlet_file"
  echo "ROUND_FILE=$round_target"
  echo "ROUND_NUMBER=$round_label"
  echo "VERDICT=$verdict"
  echo "QUALITY_BAR_FINGERPRINT=$quality_fingerprint"
  echo
  cat "$round_stage"
  exit 0
fi

mkdir -p "$item_round_dir"
mv "$round_stage" "$round_target"
if ! mv "$main_stage" "$gauntlet_file"; then
  rm -f "$round_target"
  exit 1
fi
trap - EXIT

echo "GAUNTLET_FILE=$gauntlet_file"
echo "ROUND_FILE=$round_target"
echo "ROUND_NUMBER=$round_label"
echo "VERDICT=$verdict"
echo "QUALITY_BAR_FINGERPRINT=$quality_fingerprint"
