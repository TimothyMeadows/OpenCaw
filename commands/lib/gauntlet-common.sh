#!/usr/bin/env bash

# This sourced library intentionally exports GAUNTLET_* observation state to
# calling commands.
# shellcheck disable=SC2034

# Shared helpers for Gauntlet lifecycle commands. Calling commands must enable
# strict mode before sourcing this file.

gauntlet_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$gauntlet_lib_dir/memory-common.sh"
opencaw_resolve_paths

OPENCAW_GAUNTLETS_DIR="$OPENCAW_PROJECT_AI_DIR/gauntlets"

gauntlet_fail() {
  echo "$*" >&2
  return 1
}

gauntlet_validate_name() {
  local value="$1"
  local label="$2"

  if [[ ! "$value" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
    gauntlet_fail "$label must be lowercase kebab-case: $value"
    return 1
  fi
}

gauntlet_validate_identifier() {
  local value="$1"
  local label="$2"

  opencaw_validate_single_line "$value" "$label" || return 1
  if [[ ! "$value" =~ ^/?[A-Za-z0-9][A-Za-z0-9._:@/-]*$ ]] \
    || [[ "$value" == *'..'* || "$value" == *'//'* || "$value" == */ ]]; then
    gauntlet_fail "$label contains unsupported characters: $value"
    return 1
  fi
}

gauntlet_validate_head_sha() {
  local value="$1"
  local label="$2"

  opencaw_validate_single_line "$value" "$label" || return 1
  if [[ ! "$value" =~ ^[0-9a-fA-F]{40}([0-9a-fA-F]{24})?$ ]]; then
    gauntlet_fail "$label must be a full 40- or 64-character hexadecimal commit SHA: $value"
    return 1
  fi
}

gauntlet_assert_git_repository() {
  local discovered_root expected_root

  expected_root="$(cd "$OPENCAW_PROJECT_ROOT_RESOLVED" && pwd -P)"
  discovered_root="$(git -C "$expected_root" rev-parse --show-toplevel 2>/dev/null)" || {
    gauntlet_fail "The resolved OpenCaw project root is not a Git repository: $expected_root"
    return 1
  }
  discovered_root="$(cd "$discovered_root" && pwd -P)"
  [[ "$discovered_root" == "$expected_root" ]] || {
    gauntlet_fail "Git repository root mismatch: expected $expected_root, observed $discovered_root"
    return 1
  }
}

gauntlet_assert_github_repository_identity() {
  local expected_repo="$1"
  local origin_url observed_repo='' push_url push_repo push_count=0

  gauntlet_assert_git_repository || return 1
  origin_url="$(git -C "$OPENCAW_PROJECT_ROOT_RESOLVED" remote get-url origin 2>/dev/null)" || {
    gauntlet_fail 'The local Git repository requires an origin remote for GitHub identity verification.'
    return 1
  }
  case "$origin_url" in
    https://github.com/*)
      observed_repo="${origin_url#*github.com/}"
      ;;
    ssh://git@github.com/*)
      observed_repo="${origin_url#ssh://git@github.com/}"
      ;;
    git@github.com:*)
      observed_repo="${origin_url#git@github.com:}"
      ;;
  esac
  observed_repo="${observed_repo%.git}"
  observed_repo="${observed_repo%/}"
  [[ -n "$observed_repo" && "${observed_repo,,}" == "${expected_repo,,}" ]] || {
    gauntlet_fail "Local Git origin does not match the parent task GitHub repository: expected $expected_repo, observed ${observed_repo:-$origin_url}"
    return 1
  }

  while IFS= read -r push_url; do
    [[ -n "$push_url" ]] || continue
    push_count=$((push_count + 1))
    push_repo=''
    case "$push_url" in
      https://github.com/*)
        push_repo="${push_url#*github.com/}"
        ;;
      ssh://git@github.com/*)
        push_repo="${push_url#ssh://git@github.com/}"
        ;;
      git@github.com:*)
        push_repo="${push_url#git@github.com:}"
        ;;
    esac
    push_repo="${push_repo%.git}"
    push_repo="${push_repo%/}"
    [[ -n "$push_repo" && "${push_repo,,}" == "${expected_repo,,}" ]] || {
      gauntlet_fail "Git origin push URL does not match the parent task GitHub repository: expected $expected_repo, observed $push_url"
      return 1
    }
  done < <(git -C "$OPENCAW_PROJECT_ROOT_RESOLVED" remote get-url --push --all origin 2>/dev/null) || {
    gauntlet_fail 'Unable to resolve Git origin push URLs for Gauntlet publication identity verification.'
    return 1
  }
  [[ $push_count -gt 0 ]] || {
    gauntlet_fail 'Git origin requires at least one canonical GitHub push URL for Gauntlet publication.'
    return 1
  }
}

gauntlet_assert_github_default_branch() {
  local expected_repo="$1"
  local expected_branch="$2"
  local observed_branch

  gauntlet_validate_branch "$expected_branch" \
    'Expected GitHub default branch' || return 1
  command -v gh >/dev/null 2>&1 || {
    gauntlet_fail 'The GitHub CLI (gh) is required to verify the repository default branch.'
    return 1
  }
  observed_branch="$(env GH_HOST=github.com gh repo view "$expected_repo" \
    --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null)" || {
    gauntlet_fail "Unable to query the GitHub default branch for $expected_repo."
    return 1
  }
  [[ "$observed_branch" == "$expected_branch" ]] || {
    gauntlet_fail "Gauntlet promotion PR must target the current GitHub default branch so Closes can resolve its parent issue: expected $observed_branch, configured $expected_branch"
    return 1
  }
}

gauntlet_fetch_origin() {
  gauntlet_assert_git_repository || return 1
  git -C "$OPENCAW_PROJECT_ROOT_RESOLVED" fetch --no-tags origin >/dev/null 2>&1 || {
    gauntlet_fail 'Unable to fetch origin before Gauntlet publication preflight.'
    return 1
  }
}

gauntlet_observe_remote_branch() {
  local branch="$1"
  local label="$2"
  local expected_ref observation line_count observed_sha observed_ref

  gauntlet_validate_branch "$branch" "$label" || return 1
  expected_ref="refs/heads/$branch"
  observation="$(git -C "$OPENCAW_PROJECT_ROOT_RESOLVED" ls-remote --heads origin "$expected_ref" 2>/dev/null)" || {
    gauntlet_fail "Unable to query live origin ref for $label: $expected_ref"
    return 1
  }
  if [[ -z "$observation" ]]; then
    GAUNTLET_REMOTE_BRANCH_SHA='absent'
    return 0
  fi
  line_count="$(printf '%s\n' "$observation" | sed '/^$/d' | wc -l | tr -d '[:space:]')"
  [[ "$line_count" -eq 1 ]] || {
    gauntlet_fail "Origin returned non-unique ref evidence for $label: $expected_ref"
    return 1
  }
  IFS=$'\t' read -r observed_sha observed_ref <<< "$observation"
  observed_sha="${observed_sha,,}"
  [[ "$observed_ref" == "$expected_ref" ]] || {
    gauntlet_fail "Origin returned an unexpected ref for $label: $observed_ref"
    return 1
  }
  gauntlet_validate_head_sha "$observed_sha" "$label remote SHA" || return 1
  GAUNTLET_REMOTE_BRANCH_SHA="$observed_sha"
}

gauntlet_immutable_evidence_count() {
  local gauntlet_dir="$1"
  local count=0 evidence_root evidence_file

  for evidence_root in rounds pr-events promotion-events completion-events; do
    [[ -d "$gauntlet_dir/$evidence_root" ]] || continue
    while IFS= read -r evidence_file; do
      [[ -n "$evidence_file" ]] && count=$((count + 1))
    done < <(find "$gauntlet_dir/$evidence_root" -type f \
      \( -name 'round-*.md' -o -name 'event-*.md' \) -print)
  done
  printf '%s\n' "$count"
}

gauntlet_assert_remote_progress_preflight() {
  local gauntlet_file="$1"
  local work_branch="$2"
  local work_sha="${3,,}"
  local gauntlet_dir issue_repo integration_branch chain_tip evidence_count

  gauntlet_dir="$(cd "$(dirname "$gauntlet_file")" && pwd -P)"
  issue_repo="$(gauntlet_github_repo_from_url "$(gauntlet_section_field "$gauntlet_file" 'Parent Task' 'Issue')")"
  [[ -n "$issue_repo" ]] || {
    gauntlet_fail 'Gauntlet publication preflight requires a canonical parent-task GitHub repository.'
    return 1
  }
  gauntlet_assert_github_repository_identity "$issue_repo" || return 1
  gauntlet_fetch_origin || return 1

  integration_branch="$(gauntlet_section_field "$gauntlet_file" 'Delivery' 'Integration branch')"
  chain_tip="$(gauntlet_progress_merge_chain_tip "$gauntlet_file")" || return 1
  gauntlet_assert_local_branch_at_sha "$integration_branch" "$chain_tip" 'Gauntlet integration chain tip' || return 1
  gauntlet_observe_remote_branch "$integration_branch" 'Gauntlet integration branch' || return 1
  GAUNTLET_REMOTE_INTEGRATION_SHA="$GAUNTLET_REMOTE_BRANCH_SHA"
  evidence_count="$(gauntlet_immutable_evidence_count "$gauntlet_dir")"
  if [[ "$GAUNTLET_REMOTE_INTEGRATION_SHA" == 'absent' ]]; then
    [[ "$evidence_count" -eq 0 ]] || {
      gauntlet_fail 'Origin integration ref may be absent only before the first immutable Gauntlet event.'
      return 1
    }
    GAUNTLET_REMOTE_INTEGRATION_STATE='absent-create-only'
  else
    [[ "$GAUNTLET_REMOTE_INTEGRATION_SHA" == "$chain_tip" ]] || {
      gauntlet_fail "Origin integration ref diverges from the exact recorded chain tip: expected $chain_tip, observed $GAUNTLET_REMOTE_INTEGRATION_SHA"
      return 1
    }
    GAUNTLET_REMOTE_INTEGRATION_STATE='exact'
  fi

  gauntlet_assert_local_branch_at_sha "$work_branch" "$work_sha" 'Gauntlet progress work branch' || return 1
  gauntlet_observe_remote_branch "$work_branch" 'Gauntlet progress work branch' || return 1
  GAUNTLET_REMOTE_WORK_SHA="$GAUNTLET_REMOTE_BRANCH_SHA"
  if [[ "$GAUNTLET_REMOTE_WORK_SHA" == 'absent' ]]; then
    GAUNTLET_REMOTE_WORK_STATE='absent-create-only'
  elif [[ "$GAUNTLET_REMOTE_WORK_SHA" == "$work_sha" ]]; then
    GAUNTLET_REMOTE_WORK_STATE='exact'
  else
    gauntlet_fail "Origin work ref is divergent and must never be force-updated: expected absent or $work_sha, observed $GAUNTLET_REMOTE_WORK_SHA"
    return 1
  fi
}

gauntlet_assert_remote_integration_tip() {
  local gauntlet_file="$1"
  local expected_sha="${2,,}"
  local issue_repo integration_branch

  issue_repo="$(gauntlet_github_repo_from_url "$(gauntlet_section_field "$gauntlet_file" 'Parent Task' 'Issue')")"
  [[ -n "$issue_repo" ]] || {
    gauntlet_fail 'Exact integration-tip replay requires a canonical parent-task GitHub repository.'
    return 1
  }
  gauntlet_assert_github_repository_identity "$issue_repo" || return 1
  gauntlet_validate_head_sha "$expected_sha" 'Expected remote integration SHA' || return 1
  gauntlet_fetch_origin || return 1
  integration_branch="$(gauntlet_section_field "$gauntlet_file" 'Delivery' 'Integration branch')"
  gauntlet_observe_remote_branch "$integration_branch" 'Gauntlet integration branch' || return 1
  [[ "$GAUNTLET_REMOTE_BRANCH_SHA" != 'absent' \
    && "$GAUNTLET_REMOTE_BRANCH_SHA" == "$expected_sha" ]] || {
    gauntlet_fail "Origin integration ref must equal the exact reconstructed chain tip: expected $expected_sha, observed $GAUNTLET_REMOTE_BRANCH_SHA"
    return 1
  }
  GAUNTLET_REMOTE_INTEGRATION_SHA="$GAUNTLET_REMOTE_BRANCH_SHA"
  GAUNTLET_REMOTE_INTEGRATION_STATE='exact'
}

gauntlet_assert_commit_object() {
  local sha="$1"
  local label="$2"
  local object_type resolved

  gauntlet_validate_head_sha "$sha" "$label" || return 1
  gauntlet_assert_git_repository || return 1
  object_type="$(git -C "$OPENCAW_PROJECT_ROOT_RESOLVED" cat-file -t "$sha" 2>/dev/null)" || {
    gauntlet_fail "$label does not exist in the local Git object database: $sha"
    return 1
  }
  [[ "$object_type" == 'commit' ]] || {
    gauntlet_fail "$label is not a Git commit object: $sha"
    return 1
  }
  resolved="$(git -C "$OPENCAW_PROJECT_ROOT_RESOLVED" rev-parse --verify "$sha^{commit}" 2>/dev/null)" || return 1
  [[ "${resolved,,}" == "${sha,,}" ]] || {
    gauntlet_fail "$label does not resolve exactly to the supplied full SHA: $sha"
    return 1
  }
}

gauntlet_local_branch_sha() {
  local branch="$1"
  local label="$2"
  local ref

  gauntlet_validate_branch "$branch" "$label" || return 1
  gauntlet_assert_git_repository || return 1
  ref="refs/heads/$branch"
  git -C "$OPENCAW_PROJECT_ROOT_RESOLVED" show-ref --verify --hash "$ref" 2>/dev/null || {
    gauntlet_fail "$label does not exist as an exact local branch ref: $branch"
    return 1
  }
}

gauntlet_assert_local_branch_at_sha() {
  local branch="$1"
  local sha="$2"
  local label="$3"
  local observed

  gauntlet_assert_commit_object "$sha" "$label SHA" || return 1
  observed="$(gauntlet_local_branch_sha "$branch" "$label")" || return 1
  [[ "${observed,,}" == "${sha,,}" ]] || {
    gauntlet_fail "$label '$branch' resolves to $observed, not reviewed commit $sha"
    return 1
  }
}

gauntlet_assert_commit_ancestor() {
  local ancestor="$1"
  local descendant="$2"
  local label="$3"

  gauntlet_assert_commit_object "$ancestor" "$label ancestor" || return 1
  gauntlet_assert_commit_object "$descendant" "$label descendant" || return 1
  git -C "$OPENCAW_PROJECT_ROOT_RESOLVED" merge-base --is-ancestor "$ancestor" "$descendant" || {
    gauntlet_fail "$label is not represented by the required local Git ancestry: $ancestor -> $descendant"
    return 1
  }
}

gauntlet_assert_artifact_at_commit() {
  local sha="$1"
  local artifact="$2"
  local object_type tree_mode

  gauntlet_assert_commit_object "$sha" 'Reviewed commit' || return 1
  object_type="$(git -C "$OPENCAW_PROJECT_ROOT_RESOLVED" cat-file -t "$sha:$artifact" 2>/dev/null)" || {
    gauntlet_fail "Inspected artifact is absent from reviewed commit $sha: $artifact"
    return 1
  }
  [[ "$object_type" == 'blob' ]] || {
    gauntlet_fail "Inspected artifact is not a file blob in reviewed commit $sha: $artifact"
    return 1
  }
  tree_mode="$(git -C "$OPENCAW_PROJECT_ROOT_RESOLVED" ls-tree "$sha" -- "$artifact" | awk 'NR == 1 { print $1 }')"
  [[ "$tree_mode" == 100* ]] || {
    gauntlet_fail "Inspected artifact is not a regular file in reviewed commit $sha: $artifact"
    return 1
  }
}

gauntlet_observe_github_pr() {
  local pr_url="$1"
  local expected_repo="$2"
  local observation actor_observation repo_owner repo_name pr_number actor_query actor_filter
  local actor_login

  command -v gh >/dev/null 2>&1 || {
    gauntlet_fail 'The GitHub CLI (gh) is required to verify live pull-request state.'
    return 1
  }
  observation="$(env GH_HOST=github.com gh pr view "$pr_url" --repo "$expected_repo" \
    --json url,headRefName,headRefOid,baseRefName,baseRefOid,isCrossRepository,headRepository,state,isDraft,createdAt,closedAt,mergedAt,mergedBy,mergeCommit,body \
    --jq '[.url, .headRefName, .headRefOid, .baseRefName, .baseRefOid, (.isCrossRepository | tostring), (.headRepository.nameWithOwner // "none"), .state, (.isDraft | tostring), (.createdAt // "none"), (.closedAt // "none"), (.mergedAt // "none"), (.mergedBy.login // "none"), (if .mergedBy == null then "none" elif .mergedBy.is_bot == null then "none" else (.mergedBy.is_bot | tostring) end), (.mergeCommit.oid // "none"), (.body // "" | @base64)] | @tsv' 2>/dev/null)" || {
    gauntlet_fail "Unable to query live GitHub pull-request state: $pr_url"
    return 1
  }

  IFS=$'\t' read -r \
    GAUNTLET_GH_URL \
    GAUNTLET_GH_HEAD_BRANCH \
    GAUNTLET_GH_HEAD_SHA \
    GAUNTLET_GH_BASE_BRANCH \
    GAUNTLET_GH_BASE_SHA \
    GAUNTLET_GH_IS_CROSS_REPOSITORY \
    GAUNTLET_GH_HEAD_REPOSITORY \
    GAUNTLET_GH_STATE \
    GAUNTLET_GH_IS_DRAFT \
    GAUNTLET_GH_CREATED_AT \
    GAUNTLET_GH_CLOSED_AT \
    GAUNTLET_GH_MERGED_AT \
    GAUNTLET_GH_MERGED_BY \
    GAUNTLET_GH_MERGED_BY_BOT \
    GAUNTLET_GH_MERGE_COMMIT \
    GAUNTLET_GH_BODY_BASE64 <<< "$observation"

  GAUNTLET_GH_URL="${GAUNTLET_GH_URL%/}"
  GAUNTLET_GH_HEAD_SHA="${GAUNTLET_GH_HEAD_SHA,,}"
  GAUNTLET_GH_BASE_SHA="${GAUNTLET_GH_BASE_SHA,,}"
  GAUNTLET_GH_MERGE_COMMIT="${GAUNTLET_GH_MERGE_COMMIT,,}"
  [[ -n "$GAUNTLET_GH_URL" && -n "$GAUNTLET_GH_HEAD_BRANCH" \
    && -n "$GAUNTLET_GH_HEAD_SHA" && -n "$GAUNTLET_GH_BASE_BRANCH" && -n "$GAUNTLET_GH_BASE_SHA" \
    && -n "$GAUNTLET_GH_IS_CROSS_REPOSITORY" && -n "$GAUNTLET_GH_HEAD_REPOSITORY" \
    && -n "$GAUNTLET_GH_STATE" && -n "$GAUNTLET_GH_IS_DRAFT" && -n "$GAUNTLET_GH_CREATED_AT" \
    && -n "$GAUNTLET_GH_CLOSED_AT" ]] || {
    gauntlet_fail "GitHub returned an incomplete pull-request observation: $pr_url"
    return 1
  }
  GAUNTLET_GH_BODY="$(gauntlet_decode_base64 "$GAUNTLET_GH_BODY_BASE64")" || return 1
  [[ "$GAUNTLET_GH_IS_CROSS_REPOSITORY" == 'false' \
    && "${GAUNTLET_GH_HEAD_REPOSITORY,,}" == "${expected_repo,,}" ]] || {
    gauntlet_fail "Gauntlet evidence requires a same-repository pull request from $expected_repo: $pr_url"
    return 1
  }
  [[ "$GAUNTLET_GH_CREATED_AT" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || {
    gauntlet_fail "GitHub PR lacks canonical createdAt evidence: $pr_url"
    return 1
  }

  repo_owner="${expected_repo%%/*}"
  repo_name="${expected_repo#*/}"
  pr_number="$(gauntlet_github_pr_number_from_url "$pr_url")"
  actor_query='query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){pullRequest(number:$number){mergedBy{__typename login} timelineItems(last:1,itemTypes:[AUTO_MERGE_ENABLED_EVENT,AUTO_REBASE_ENABLED_EVENT,AUTO_SQUASH_ENABLED_EVENT,ADDED_TO_MERGE_QUEUE_EVENT]){nodes{__typename}}}}}'
  actor_filter='[.data.repository.pullRequest.mergedBy.__typename // "none", .data.repository.pullRequest.mergedBy.login // "none", (if (.data.repository.pullRequest.timelineItems.nodes|length)==0 then "none" else .data.repository.pullRequest.timelineItems.nodes[0].__typename end)] | @tsv'
  actor_observation="$(gh api --hostname github.com graphql \
    -f query="$actor_query" \
    -f owner="$repo_owner" \
    -f name="$repo_name" \
    -F number="$pr_number" \
    --jq "$actor_filter" 2>/dev/null)" || {
    gauntlet_fail "Unable to query the live GitHub merge actor and automation history: $pr_url"
    return 1
  }
  IFS=$'\t' read -r GAUNTLET_GH_MERGED_BY_TYPE actor_login \
    GAUNTLET_GH_MERGE_AUTOMATION_EVENT <<< "$actor_observation"
  [[ "$GAUNTLET_GH_MERGE_AUTOMATION_EVENT" == 'none' ]] || {
    gauntlet_fail "Gauntlet PR must never enable auto-merge or enter a merge queue: $pr_url ($GAUNTLET_GH_MERGE_AUTOMATION_EVENT)"
    return 1
  }
  if [[ "$GAUNTLET_GH_STATE" == 'MERGED' ]]; then
    [[ "$GAUNTLET_GH_MERGED_BY_TYPE" == 'User' \
      && "$actor_login" == "$GAUNTLET_GH_MERGED_BY" ]] || {
      gauntlet_fail "Gauntlet progress PR must be merged by a GitHub User actor, not Bot/App/Mannequin/null: $pr_url"
      return 1
    }
  fi
}

gauntlet_assert_live_pr() {
  local pr_url="${1%/}"
  local expected_repo="$2"
  local expected_head="$3"
  local expected_sha="${4,,}"
  local expected_base="$5"
  local expected_state="$6"

  gauntlet_validate_github_pr_url "$pr_url" 'PR URL' || return 1
  gauntlet_validate_branch "$expected_head" 'Expected PR head branch' || return 1
  gauntlet_validate_branch "$expected_base" 'Expected PR base branch' || return 1
  gauntlet_assert_commit_object "$expected_sha" 'PR head SHA' || return 1
  gauntlet_observe_github_pr "$pr_url" "$expected_repo" || return 1

  [[ "$GAUNTLET_GH_URL" == "$pr_url" \
    && "$GAUNTLET_GH_HEAD_BRANCH" == "$expected_head" \
    && "$GAUNTLET_GH_HEAD_SHA" == "$expected_sha" \
    && "$GAUNTLET_GH_BASE_BRANCH" == "$expected_base" ]] || {
    gauntlet_fail "Live GitHub PR does not match the recorded URL, head branch, head SHA, and target branch: $pr_url"
    return 1
  }
  gauntlet_assert_commit_object "$GAUNTLET_GH_BASE_SHA" 'Observed PR target base SHA' || return 1
  [[ "$GAUNTLET_GH_IS_DRAFT" == 'false' ]] || {
    gauntlet_fail "Gauntlet evidence cannot be recorded against a draft pull request: $pr_url"
    return 1
  }

  case "$expected_state" in
    open)
      [[ "$GAUNTLET_GH_STATE" == 'OPEN' && "$GAUNTLET_GH_MERGED_AT" == 'none' \
        && "$GAUNTLET_GH_CLOSED_AT" == 'none' \
        && "$GAUNTLET_GH_MERGED_BY" == 'none' && "$GAUNTLET_GH_MERGED_BY_TYPE" == 'none' \
        && "$GAUNTLET_GH_MERGED_BY_BOT" == 'none' \
        && "$GAUNTLET_GH_MERGE_COMMIT" == 'none' ]] || {
        gauntlet_fail "Pull request must be live, open, and unmerged: $pr_url"
        return 1
      }
      ;;
    merged)
      [[ "$GAUNTLET_GH_STATE" == 'MERGED' \
        && "$GAUNTLET_GH_CLOSED_AT" != 'none' \
        && "$GAUNTLET_GH_MERGED_AT" != 'none' \
        && "$GAUNTLET_GH_MERGED_BY" != 'none' \
        && "$GAUNTLET_GH_MERGED_BY_TYPE" == 'User' \
        && "$GAUNTLET_GH_MERGED_BY_BOT" == 'false' \
        && "$GAUNTLET_GH_MERGE_COMMIT" != 'none' ]] || {
        gauntlet_fail "Pull request must be human-merged with durable GitHub merge metadata: $pr_url"
        return 1
      }
      [[ "$GAUNTLET_GH_MERGED_AT" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || {
        gauntlet_fail "GitHub merge timestamp is not canonical UTC evidence: $GAUNTLET_GH_MERGED_AT"
        return 1
      }
      [[ "$GAUNTLET_GH_CLOSED_AT" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || {
        gauntlet_fail "GitHub merged PR lacks canonical closedAt evidence: $GAUNTLET_GH_CLOSED_AT"
        return 1
      }
      ;;
    closed)
      [[ "$GAUNTLET_GH_STATE" == 'CLOSED' && "$GAUNTLET_GH_MERGED_AT" == 'none' \
        && "$GAUNTLET_GH_CLOSED_AT" != 'none' \
        && "$GAUNTLET_GH_MERGED_BY" == 'none' && "$GAUNTLET_GH_MERGED_BY_TYPE" == 'none' \
        && "$GAUNTLET_GH_MERGED_BY_BOT" == 'none' \
        && "$GAUNTLET_GH_MERGE_COMMIT" == 'none' ]] || {
        gauntlet_fail "Pull request must be closed without a merge: $pr_url"
        return 1
      }
      [[ "$GAUNTLET_GH_CLOSED_AT" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || {
        gauntlet_fail "GitHub closed PR lacks canonical closedAt evidence: $GAUNTLET_GH_CLOSED_AT"
        return 1
      }
      ;;
    *)
      gauntlet_fail "Unsupported expected GitHub PR state: $expected_state"
      return 1
      ;;
  esac
}

gauntlet_acquire_lock() {
  local gauntlet_dir="$1"
  local lock_dir="$gauntlet_dir/.opencaw-gauntlet.lock"

  gauntlet_assert_safe_ai_path "$gauntlet_dir" 'Gauntlet directory' || return 1
  if ! mkdir "$lock_dir" 2>/dev/null; then
    gauntlet_fail "Gauntlet is locked; if no recorder is active, inspect and remove the stale lock manually: $lock_dir"
    return 1
  fi
  GAUNTLET_LOCK_DIR="$lock_dir"
  if ! printf '%s\n' "pid=$$" "started=$(date -u '+%Y-%m-%dT%H:%M:%SZ')" > "$lock_dir/owner"; then
    rm -f "$lock_dir/owner"
    rmdir "$lock_dir" 2>/dev/null || true
    GAUNTLET_LOCK_DIR=''
    gauntlet_fail "Could not initialize Gauntlet lock ownership metadata: $lock_dir"
    return 1
  fi
}

gauntlet_release_lock() {
  if [[ -n "${GAUNTLET_LOCK_DIR:-}" && -d "$GAUNTLET_LOCK_DIR" ]]; then
    rm -f "$GAUNTLET_LOCK_DIR/owner"
    rmdir "$GAUNTLET_LOCK_DIR" 2>/dev/null || true
  fi
  GAUNTLET_LOCK_DIR=''
}

gauntlet_capture_source_hash() {
  local gauntlet_file="$1"
  GAUNTLET_SOURCE_FILE="$gauntlet_file"
  GAUNTLET_SOURCE_HASH="$(gauntlet_hash_file "$gauntlet_file")"
}

gauntlet_assert_source_hash() {
  local current_hash

  [[ -n "${GAUNTLET_SOURCE_FILE:-}" && -n "${GAUNTLET_SOURCE_HASH:-}" ]] || {
    gauntlet_fail 'Internal error: Gauntlet source CAS was not initialized.'
    return 1
  }
  current_hash="$(gauntlet_hash_file "$GAUNTLET_SOURCE_FILE")"
  [[ "$current_hash" == "$GAUNTLET_SOURCE_HASH" ]] || {
    gauntlet_fail "Gauntlet state changed during operation; no mutation was committed: $GAUNTLET_SOURCE_FILE"
    return 1
  }
}

gauntlet_install_no_clobber() {
  local staged="$1"
  local target="$2"

  [[ ! -e "$target" && ! -L "$target" ]] || {
    gauntlet_fail "Immutable Gauntlet evidence already exists: $target"
    return 1
  }
  if ! ln "$staged" "$target" 2>/dev/null; then
    gauntlet_fail "Could not install immutable evidence without clobbering an existing path: $target"
    return 1
  fi
  rm -f "$staged"
}

gauntlet_validate_substantive_single_line() {
  local value="$1"
  local label="$2"

  opencaw_validate_single_line "$value" "$label" || return 1
  [[ "$value" != *'|'* ]] || {
    gauntlet_fail "$label must not contain a pipe character."
    return 1
  }
  gauntlet_has_substance "$value" || {
    gauntlet_fail "$label must be substantive and contain no placeholders."
    return 1
  }
  if printf '%s\n' "$value" | grep -Eqi -- '^[[:space:]]*(none|n/?a|not applicable|retry|try again|same strategy)[.!]?[[:space:]]*$'; then
    gauntlet_fail "$label must be a concrete value."
    return 1
  fi
}

gauntlet_strategy_fingerprint() {
  local value="$1"
  local normalized

  normalized="$(printf '%s\n' "$value" \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/[[:space:]]+/ /g' \
    | tr '[:upper:]' '[:lower:]')"
  gauntlet_hash_text "$normalized"
}

gauntlet_latest_round_file() {
  local round_dir="$1"

  [[ -d "$round_dir" ]] || return 0
  find "$round_dir" -maxdepth 1 -type f -name 'round-*.md' -print \
    | awk '
        {
          name = $0
          sub(/^.*\/round-/, "", name)
          sub(/\.md$/, "", name)
          if (name ~ /^[0-9]+$/) print name "\t" $0
        }
      ' \
    | LC_ALL=C sort -n -k1,1 \
    | tail -n 1 \
    | cut -f2-
}

gauntlet_latest_round_file_for_pr() {
  local round_dir="$1"
  local pr_url="${2%/}"
  local candidate candidate_pr latest=''

  [[ -d "$round_dir" ]] || return 0
  while IFS=$'\t' read -r _round_number candidate; do
    [[ -n "$candidate" ]] || continue
    candidate_pr="$(gauntlet_section_field "$candidate" 'Round Metadata' 'Progress PR')"
    [[ "${candidate_pr%/}" == "$pr_url" ]] && latest="$candidate"
  done < <(find "$round_dir" -maxdepth 1 -type f -name 'round-*.md' -print \
    | awk '
        {
          name = $0
          sub(/^.*\/round-/, "", name)
          sub(/\.md$/, "", name)
          if (name ~ /^[0-9]+$/) print name "\t" $0
        }
      ' \
    | LC_ALL=C sort -n -k1,1)
  [[ -z "$latest" ]] || printf '%s\n' "$latest"
}

gauntlet_latest_pr_event_file() {
  local event_dir="$1"

  [[ -d "$event_dir" ]] || return 0
  find "$event_dir" -maxdepth 1 -type f -name 'event-*.md' -print \
    | awk '
        {
          name = $0
          sub(/^.*\/event-/, "", name)
          sub(/\.md$/, "", name)
          if (name ~ /^[0-9]+$/) print name "\t" $0
        }
      ' \
    | LC_ALL=C sort -n -k1,1 \
    | tail -n 1 \
    | cut -f2-
}

gauntlet_latest_promotion_event_file() {
  local event_dir="$1"

  [[ -d "$event_dir" ]] || return 0
  find "$event_dir" -maxdepth 1 -type f -name 'event-*.md' -print \
    | awk '
        {
          name = $0
          sub(/^.*\/event-/, "", name)
          sub(/\.md$/, "", name)
          if (name ~ /^[0-9]+$/) print name "\t" $0
        }
      ' \
    | LC_ALL=C sort -n -k1,1 \
    | tail -n 1 \
    | cut -f2-
}

gauntlet_latest_completion_event_file() {
  local event_dir="$1"

  [[ -d "$event_dir" ]] || return 0
  find "$event_dir" -maxdepth 1 -type f -name 'event-*.md' -print \
    | awk '
        {
          name = $0
          sub(/^.*\/event-/, "", name)
          sub(/\.md$/, "", name)
          if (name ~ /^[0-9]+$/) print name "\t" $0
        }
      ' \
    | LC_ALL=C sort -n -k1,1 \
    | tail -n 1 \
    | cut -f2-
}

gauntlet_trim() {
  local value="$1"
  value="${value%$'\r'}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s\n' "$value"
}

gauntlet_validate_branch() {
  local value="$1"
  local label="$2"

  opencaw_validate_single_line "$value" "$label" || return 1
  if [[ -z "$value" || "$value" == -* || "$value" == /* || "$value" == */ \
    || "$value" == *'..'* || "$value" == *'//'* || "$value" == *'@{'* \
    || "$value" == *'\'* || "$value" == *' '* || "$value" == *'~'* \
    || "$value" == *'^'* || "$value" == *':'* || "$value" == *'?'* \
    || "$value" == *'*'* || "$value" == *'['* || "$value" == *.lock \
    || ! "$value" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]]; then
    gauntlet_fail "$label is not a safe Git branch name: $value"
    return 1
  fi
}

gauntlet_validate_github_pr_url() {
  local value="$1"
  local label="$2"

  opencaw_validate_single_line "$value" "$label" || return 1
  if [[ ! "$value" =~ ^https://github\.com/[^/[:space:]]+/[^/[:space:]]+/pull/[0-9]+/?$ ]]; then
    gauntlet_fail "$label must be a GitHub pull-request URL: $value"
    return 1
  fi
}

gauntlet_validate_evidence_url() {
  local value="$1"
  local label="$2"

  opencaw_validate_single_line "$value" "$label" || return 1
  if [[ "$value" != 'none' && ! "$value" =~ ^https://[^[:space:]]+$ ]]; then
    gauntlet_fail "$label must be 'none' or an HTTPS URL: $value"
    return 1
  fi
}

gauntlet_validate_pr_evidence_url() {
  local value="$1"
  local pr_url="${2%/}"
  local allow_pr_url="${3:-no}"
  local comment_pr comment_id

  gauntlet_validate_github_pr_url "$pr_url" 'Evidence PR URL' || return 1
  opencaw_validate_single_line "$value" 'PR evidence URL' || return 1
  if [[ "$allow_pr_url" == 'yes' && "${value%/}" == "$pr_url" ]]; then
    return 0
  fi
  comment_pr="${value%%#issuecomment-*}"
  comment_id="${value#*#issuecomment-}"
  [[ "$value" == *'#issuecomment-'* \
    && "$comment_pr" == "$pr_url" \
    && "$comment_id" =~ ^[1-9][0-9]*$ ]] || {
    if [[ "$allow_pr_url" == 'yes' ]]; then
      gauntlet_fail "PR evidence must be an exact same-PR #issuecomment-N URL or the canonical PR URL: $value"
    else
      gauntlet_fail "PR evidence must be an exact same-PR #issuecomment-N URL: $value"
    fi
    return 1
  }
}

gauntlet_github_pr_number_from_url() {
  local value="${1%/}"
  printf '%s\n' "$value" | sed -nE 's#^https://github\.com/[^/[:space:]]+/[^/[:space:]]+/pull/([0-9]+)$#\1#p'
}

gauntlet_github_comment_id_from_url() {
  local value="$1"
  printf '%s\n' "$value" | sed -nE 's|^https://github\.com/[^/[:space:]]+/[^/[:space:]]+/pull/[0-9]+#issuecomment-([1-9][0-9]*)$|\1|p'
}

gauntlet_decode_base64() {
  local value="$1"

  if printf '%s' "$value" | base64 --decode 2>/dev/null; then
    return 0
  fi
  if printf '%s' "$value" | base64 -D 2>/dev/null; then
    return 0
  fi
  if command -v openssl >/dev/null 2>&1; then
    printf '%s' "$value" | openssl base64 -d -A 2>/dev/null && return 0
  fi
  gauntlet_fail 'Unable to decode GitHub QA comment body evidence.'
  return 1
}

gauntlet_assert_live_pr_comment() {
  local evidence_url="$1"
  local pr_url="${2%/}"
  local expected_repo="$3"
  local expected_verdict="$4"
  local expected_head_sha="${5,,}"
  local expected_source="$6"
  local source_recorded_at="$7"
  local expected_affected_units="${8:-none}"
  local trust_mode="${9:-record}"
  local pr_repo pr_number comment_id endpoint expected_issue_url observation identity
  local observed_html_url observed_issue_url observed_comment_id observed_body_base64
  local observed_author observed_author_type observed_author_association observed_created_at observed_updated_at observed_body
  local authenticated_login authenticated_type expected_source_file expected_source_hash expected_marker marker_count

  gauntlet_validate_pr_evidence_url "$evidence_url" "$pr_url" no || return 1
  pr_repo="$(gauntlet_github_repo_from_url "$pr_url")"
  pr_number="$(gauntlet_github_pr_number_from_url "$pr_url")"
  comment_id="$(gauntlet_github_comment_id_from_url "$evidence_url")"
  [[ -n "$pr_repo" && -n "$pr_number" && -n "$comment_id" \
    && "${pr_repo,,}" == "${expected_repo,,}" ]] || {
    gauntlet_fail "QA comment repository or pull-request identity does not match: $evidence_url"
    return 1
  }

  command -v gh >/dev/null 2>&1 || {
    gauntlet_fail 'The GitHub CLI (gh) is required to verify live QA comment evidence.'
    return 1
  }
  case "$trust_mode" in record|replay) ;; *) gauntlet_fail "Unsupported QA comment trust mode: $trust_mode"; return 1 ;; esac
  case "$expected_verdict" in pass|fail) ;; *) gauntlet_fail "Unsupported Gauntlet QA comment verdict: $expected_verdict"; return 1 ;; esac
  if [[ "$expected_affected_units" != 'none' ]]; then
    [[ "$expected_affected_units" =~ ^[a-z0-9]+(-[a-z0-9]+)*(,[a-z0-9]+(-[a-z0-9]+)*)*$ \
      && "$expected_affected_units" == "$(printf '%s' "$expected_affected_units" | tr ',' '\n' | LC_ALL=C sort -u | paste -sd, -)" ]] || {
      gauntlet_fail "Gauntlet QA affected-units marker is not canonical: $expected_affected_units"
      return 1
    }
  fi
  gauntlet_validate_head_sha "$expected_head_sha" 'QA comment reviewed Head SHA' || return 1
  [[ "$expected_source" =~ ^\.ai/gauntlets/[a-z0-9]+(-[a-z0-9]+)*/(rounds/[a-z0-9-]+/round-[0-9]{3,}|completion-events/event-[0-9]{3,})\.md$ ]] || {
    gauntlet_fail "QA comment source is not canonical immutable Gauntlet evidence: $expected_source"
    return 1
  }
  expected_source_file="$OPENCAW_PROJECT_ROOT_RESOLVED/$expected_source"
  gauntlet_assert_safe_ai_path "$expected_source_file" \
    'QA comment source evidence' || return 1
  [[ -f "$expected_source_file" && ! -L "$expected_source_file" ]] || {
    gauntlet_fail "QA comment source evidence is missing or unsafe: $expected_source"
    return 1
  }
  expected_source_hash="$(gauntlet_hash_file "$expected_source_file")" || return 1
  expected_marker="<!-- opencaw-gauntlet-qa:v1 verdict=$expected_verdict head-sha=$expected_head_sha source=$expected_source source-sha256=$expected_source_hash affected-units=$expected_affected_units -->"
  endpoint="repos/$expected_repo/issues/comments/$comment_id"
  observation="$(gh api --hostname github.com "$endpoint" \
    --jq '[.html_url, .issue_url, (.id | tostring), (.body // "" | @base64), (.user.login // "none"), (.user.type // "none"), (.author_association // "none"), (.created_at // "none"), (.updated_at // "none")] | @tsv' 2>/dev/null)" || {
    gauntlet_fail "Unable to query live GitHub QA comment evidence: $evidence_url"
    return 1
  }
  IFS=$'\t' read -r observed_html_url observed_issue_url observed_comment_id observed_body_base64 \
    observed_author observed_author_type observed_author_association observed_created_at observed_updated_at <<< "$observation"
  expected_issue_url="https://api.github.com/repos/$expected_repo/issues/$pr_number"
  [[ "$observed_html_url" == "$evidence_url" \
    && "${observed_issue_url,,}" == "${expected_issue_url,,}" \
    && "$observed_comment_id" == "$comment_id" ]] || {
    gauntlet_fail "Live GitHub comment does not belong exactly to the recorded repository and pull request: $evidence_url"
    return 1
  }
  observed_body="$(gauntlet_decode_base64 "$observed_body_base64")" || return 1
  marker_count="$(printf '%s\n' "$observed_body" | grep -Fxc -- "$expected_marker" || true)"
  [[ "$marker_count" -eq 1 \
    && "$(printf '%s\n' "$observed_body" | grep -Fc -- '<!-- opencaw-gauntlet-qa:' || true)" -eq 1 ]] || {
    gauntlet_fail "Live GitHub QA comment lacks exactly one matching Gauntlet verdict/source marker: $evidence_url"
    return 1
  }
  [[ "$observed_author" != 'none' && "$observed_author_type" == 'User' \
    && ( "$observed_author_association" == 'OWNER' \
      || "$observed_author_association" == 'MEMBER' \
      || "$observed_author_association" == 'COLLABORATOR' ) ]] || {
    gauntlet_fail "Gauntlet QA comment author is not a trusted human repository collaborator: $observed_author"
    return 1
  }
  [[ "$observed_created_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ \
    && "$observed_updated_at" == "$observed_created_at" \
    && ( "$source_recorded_at" < "$observed_created_at" || "$source_recorded_at" == "$observed_created_at" ) ]] || {
    gauntlet_fail "Gauntlet QA comment was edited, predates its immutable source, or lacks canonical timestamps: $evidence_url"
    return 1
  }
  if [[ "$trust_mode" == 'record' ]]; then
    identity="$(gh api --hostname github.com user \
      --jq '[.login, .type] | @tsv' 2>/dev/null)" || {
      gauntlet_fail 'Unable to query the authenticated GitHub identity for QA comment trust verification.'
      return 1
    }
    IFS=$'\t' read -r authenticated_login authenticated_type <<< "$identity"
    [[ "$authenticated_login" == "$observed_author" && "$authenticated_type" == "$observed_author_type" ]] || {
      gauntlet_fail "Gauntlet QA comment author does not match the currently authenticated GitHub user: $observed_author"
      return 1
    }
  fi
  GAUNTLET_COMMENT_AUTHOR="$observed_author"
  GAUNTLET_COMMENT_ID="$observed_comment_id"
  GAUNTLET_COMMENT_AUTHOR_TYPE="$observed_author_type"
  GAUNTLET_COMMENT_AUTHOR_ASSOCIATION="$observed_author_association"
  GAUNTLET_COMMENT_CREATED_AT="$observed_created_at"
  GAUNTLET_COMMENT_UPDATED_AT="$observed_updated_at"
  GAUNTLET_COMMENT_BODY_SHA256="$(gauntlet_hash_text "$observed_body")"
}

gauntlet_assert_unique_qa_comment() {
  local gauntlet_dir="$1"
  local evidence_url="$2"
  local event_file event_action recorded_evidence

  if [[ -d "$gauntlet_dir/pr-events" ]]; then
    while IFS= read -r event_file; do
      event_action="$(gauntlet_section_field "$event_file" 'PR Event Metadata' 'Event')"
      [[ "$event_action" == 'qa-pass' || "$event_action" == 'qa-fail' ]] || continue
      recorded_evidence="$(gauntlet_section_field "$event_file" 'PR Event Metadata' 'Evidence URL')"
      [[ "$recorded_evidence" != "$evidence_url" ]] || {
        gauntlet_fail "QA comment evidence has already been consumed by a progress event: $evidence_url"
        return 1
      }
    done < <(find "$gauntlet_dir/pr-events" -type f -name 'event-*.md' -print)
  fi

  if [[ -d "$gauntlet_dir/promotion-events" ]]; then
    while IFS= read -r event_file; do
      recorded_evidence="$(gauntlet_section_field "$event_file" 'Promotion QA Event Metadata' 'Evidence URL')"
      [[ "$recorded_evidence" != "$evidence_url" ]] || {
        gauntlet_fail "QA comment evidence has already been consumed by a promotion event: $evidence_url"
        return 1
      }
    done < <(find "$gauntlet_dir/promotion-events" -maxdepth 1 -type f -name 'event-*.md' -print)
  fi
}

gauntlet_github_repo_from_url() {
  local value="$1"
  printf '%s\n' "$value" | sed -nE 's#^https://github\.com/([^/]+/[^/]+)/(issues|pull)/[0-9]+.*$#\1#p'
}

gauntlet_github_issue_number() {
  local issue_url="$1"
  local issue_number

  issue_number="$(printf '%s\n' "$issue_url" \
    | sed -nE 's#^https://github\.com/[^/]+/[^/]+/issues/([1-9][0-9]*)/?$#\1#p')"
  [[ -n "$issue_number" ]] || {
    gauntlet_fail "Gauntlet parent issue URL does not contain a canonical issue number: $issue_url"
    return 1
  }
  printf '%s\n' "$issue_number"
}

gauntlet_github_closing_reference_count() {
  local body="$1"
  local issue_url="$2"
  local issue_number issue_repo

  issue_number="$(gauntlet_github_issue_number "$issue_url")" || return 1
  issue_repo="$(gauntlet_github_repo_from_url "$issue_url" | tr '[:upper:]' '[:lower:]')"
  [[ -n "$issue_repo" ]] || {
    gauntlet_fail "Gauntlet parent issue URL does not contain a canonical repository: $issue_url"
    return 1
  }
  printf '%s\n' "$body" | awk -v issue="$issue_number" -v repo="$issue_repo" '
    function normalized_number(value) {
      sub(/^0+/, "", value)
      return value == "" ? "0" : value
    }
    function number_matches_at(text, start, tail, digits) {
      tail = substr(text, start)
      if (!match(tail, /^[0-9]+/)) return 0
      digits = substr(tail, RSTART, RLENGTH)
      return normalized_number(digits) == normalized_number(issue)
    }
    function contains_target_reference(text, i, previous, repo_reference, url_prefix) {
      repo_reference = repo "#"
      url_prefix = "https://github.com/" repo "/issues/"
      for (i = 1; i <= length(text); i++) {
        previous = i == 1 ? "" : substr(text, i - 1, 1)
        if (substr(text, i, 1) == "#" \
          && (previous == "" || previous !~ /[a-z0-9_.\/-]/) \
          && number_matches_at(text, i + 1)) return 1
        if (substr(text, i, 3) == "gh-" \
          && (previous == "" || previous !~ /[a-z0-9_-]/) \
          && number_matches_at(text, i + 3)) return 1
        if (substr(text, i, length(repo_reference)) == repo_reference \
          && (previous == "" || previous !~ /[a-z0-9_-]/) \
          && number_matches_at(text, i + length(repo_reference))) return 1
        if (substr(text, i, length(url_prefix)) == url_prefix \
          && number_matches_at(text, i + length(url_prefix))) return 1
      }
      return 0
    }
    {
      search = tolower($0)
      while (match(search, /(^|[^a-z])(close|closes|closed|fix|fixes|fixed|resolve|resolves|resolved):?[[:space:]]+/)) {
        remainder = substr(search, RSTART + RLENGTH)
        clause = remainder
        if (match(clause, /(^|[^a-z])(close|closes|closed|fix|fixes|fixed|resolve|resolves|resolved):?[[:space:]]+/)) {
          clause = substr(clause, 1, RSTART - 1)
        }
        if (contains_target_reference(clause)) closings++
        search = remainder
      }
    }
    END { print closings + 0 }
  '
}

gauntlet_assert_progress_issue_link() {
  local body="$1"
  local issue_url="$2"
  local issue_number reference_count closing_count

  issue_number="$(gauntlet_github_issue_number "$issue_url")" || return 1
  reference_count="$(printf '%s\n' "$body" | awk -v issue="$issue_number" '
        {
          line = $0
          sub(/\r$/, "", line)
          if (line == "Refs #" issue) references++
          if (NR == 1 && line == "Refs #" issue) canonical_first=1
        }
        END { print (canonical_first && references == 1) ? 1 : 0 }
      ')"
  closing_count="$(gauntlet_github_closing_reference_count \
    "$body" "$issue_url")" || return 1
  [[ "$reference_count" -eq 1 ]] || {
    gauntlet_fail "Progress PR body requires this exact canonical first line exactly once: Refs #$issue_number"
    return 1
  }
  [[ "$closing_count" -eq 0 ]] || {
    gauntlet_fail "Progress PR body must not close the parent issue; reserve Closes #$issue_number for promotion."
    return 1
  }
}

gauntlet_assert_promotion_issue_link() {
  local body="$1"
  local issue_url="$2"
  local issue_number canonical_closing_count semantic_closing_count

  issue_number="$(gauntlet_github_issue_number "$issue_url")" || return 1
  canonical_closing_count="$(printf '%s\n' "$body" | awk -v issue="$issue_number" '
    {
      line = $0
      sub(/\r$/, "", line)
      if (line == "Closes #" issue) closings++
      if (NR == 1 && line == "Closes #" issue) canonical_first=1
    }
    END { print (canonical_first && closings == 1) ? 1 : 0 }
  ')"
  [[ "$canonical_closing_count" -eq 1 ]] || {
    gauntlet_fail "Promotion PR body requires this exact canonical first line exactly once: Closes #$issue_number"
    return 1
  }
  semantic_closing_count="$(gauntlet_github_closing_reference_count \
    "$body" "$issue_url")" || return 1
  [[ "$semantic_closing_count" -eq 1 ]] || {
    gauntlet_fail "Promotion PR body must contain exactly one parent-issue closing reference; use only: Closes #$issue_number"
    return 1
  }
}

gauntlet_hash_file() {
  local file="$1"

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$file" | awk '{print $NF}'
  else
    gauntlet_fail 'A SHA-256 implementation is required (sha256sum, shasum, or openssl).'
    return 1
  fi
}

gauntlet_hash_text() {
  local value="$1"
  local temporary digest

  temporary="$(mktemp "${TMPDIR:-/tmp}/opencaw-gauntlet-hash.XXXXXX")"
  printf '%s\n' "$value" > "$temporary"
  if ! digest="$(gauntlet_hash_file "$temporary")"; then
    rm -f "$temporary"
    return 1
  fi
  rm -f "$temporary"
  printf '%s\n' "$digest"
}

gauntlet_report_projection_hash() {
  local report_file="$1"
  local projection

  [[ -f "$report_file" && ! -L "$report_file" ]] || {
    gauntlet_fail "Gauntlet report projection requires a regular file: $report_file"
    return 1
  }
  projection="$(awk '
    { sub(/\r$/, "") }
    $0 == "## Immutable Completion Evidence" { skip = 1; next }
    /^## / && skip { skip = 0 }
    !skip { print }
  ' "$report_file")"
  gauntlet_hash_text "$projection"
}

gauntlet_extract_section() {
  local file="$1"
  local heading="$2"

  awk -v heading="$heading" '
    { sub(/\r$/, "") }
    $0 == "## " heading { in_section = 1; next }
    /^## / && in_section { exit }
    in_section { print }
  ' "$file"
}

gauntlet_extract_subsection() {
  local file="$1"
  local section="$2"
  local subsection="$3"

  awk -v section="$section" -v subsection="$subsection" '
    { sub(/\r$/, "") }
    $0 == "## " section { in_section = 1; next }
    /^## / && in_section { exit }
    in_section && $0 == "### " subsection { in_subsection = 1; next }
    in_section && in_subsection && /^### / { exit }
    in_section && in_subsection { print }
  ' "$file"
}

gauntlet_section_field() {
  local file="$1"
  local heading="$2"
  local key="$3"

  gauntlet_extract_section "$file" "$heading" \
    | awk -v prefix="- $key:" '
        index($0, prefix) == 1 {
          value = substr($0, length(prefix) + 1)
          sub(/^[[:space:]]+/, "", value)
          sub(/[[:space:]]+$/, "", value)
          print value
          exit
        }
      '
}

gauntlet_section_field_count() {
  local file="$1"
  local heading="$2"
  local key="$3"

  gauntlet_extract_section "$file" "$heading" \
    | awk -v prefix="- $key:" 'index($0, prefix) == 1 { count++ } END { print count + 0 }'
}

gauntlet_heading_count() {
  local file="$1"
  local heading="$2"
  awk -v target="## $heading" '{ sub(/\r$/, "") } $0 == target { count++ } END { print count + 0 }' "$file"
}

gauntlet_has_placeholder() {
  local value="$1"
  printf '%s\n' "$value" | grep -Eqi -- '(^|[^[:alnum:]])(todo|tbd|placeholder)([^[:alnum:]]|$)|<[^>]+>|describe an independently|define inspectable|define constraints|define allowed'
}

gauntlet_has_substance() {
  local value="$1"
  local stripped

  stripped="$(printf '%s\n' "$value" \
    | sed -E '/^[[:space:]]*$/d; /^<!--.*-->$/d; /^###[[:space:]]/d; s/^[[:space:]]*[-*][[:space:]]*//')"
  [[ -n "${stripped//[[:space:]]/}" ]] || return 1
  ! gauntlet_has_placeholder "$stripped"
}

gauntlet_quality_bar_fingerprint() {
  local gauntlet_file="$1"
  local content

  content="$(gauntlet_extract_section "$gauntlet_file" 'Approved Quality Bar')"
  gauntlet_hash_text "$content"
}

gauntlet_execution_contract_fingerprint() {
  local gauntlet_file="$1"
  local parent_task objective constraints_permissions key value material
  local delivery_fields=(
    'Base branch'
    'Base commit SHA'
    'Integration branch'
    'Progress PR publication'
    'Progress PR QA'
    'Progress PR merge'
    'Promotion PR readiness confirmation'
    'Promotion PR'
    'Post-promotion QA'
    'Auto-merge'
    'Merge approval'
  )

  parent_task="$(gauntlet_extract_section "$gauntlet_file" 'Parent Task')"
  objective="$(gauntlet_extract_section "$gauntlet_file" 'Objective')"
  constraints_permissions="$(gauntlet_extract_section "$gauntlet_file" 'Constraints and Permissions')"
  material="## Parent Task
$parent_task

## Objective
$objective

## Constraints and Permissions
$constraints_permissions

## Delivery"
  for key in "${delivery_fields[@]}"; do
    value="$(gauntlet_section_field "$gauntlet_file" 'Delivery' "$key")"
    material+=$'\n'"- $key: $value"
  done
  gauntlet_hash_text "$material"
}

gauntlet_assert_frozen_execution_contract() {
  local gauntlet_file="$1"
  local recorded computed

  recorded="$(gauntlet_section_field "$gauntlet_file" 'Current State' 'Execution contract fingerprint')"
  computed="$(gauntlet_execution_contract_fingerprint "$gauntlet_file")" || return 1
  [[ "$recorded" =~ ^[0-9a-fA-F]{64}$ ]] || {
    gauntlet_fail 'Gauntlet execution contract has not been frozen by an accepted opened progress-PR event.'
    return 1
  }
  [[ "${recorded,,}" == "${computed,,}" ]] || {
    gauntlet_fail 'Gauntlet execution contract changed after progress-PR publication was authorized.'
    return 1
  }
  printf '%s\n' "${computed,,}"
}

gauntlet_unit_scope_fingerprint() {
  local gauntlet_file="$1"
  local item_id="$2"
  local unit_line title scope

  unit_line="$(gauntlet_work_unit_lines "$gauntlet_file" | awk -v item="$item_id" '$0 ~ "^- \\[[ xX]\\] " item " \\|" { print; exit }')"
  [[ -n "$unit_line" && "$unit_line" == *' | title: '* && "$unit_line" == *' | scope: '* ]] || {
    gauntlet_fail "Cannot fingerprint missing or malformed work-unit scope: $item_id"
    return 1
  }
  title="${unit_line#* | title: }"
  title="${title%% | scope: *}"
  scope="${unit_line##* | scope: }"
  title="$(gauntlet_trim "$title")"
  scope="$(gauntlet_trim "$scope")"
  gauntlet_hash_text "title: $title
scope: $scope"
}

gauntlet_unit_ids_csv() {
  local gauntlet_file="$1"

  gauntlet_work_unit_lines "$gauntlet_file" \
    | sed -nE 's/^- \[[ xX]\] ([a-z0-9]+(-[a-z0-9]+)*) \|.*$/\1/p' \
    | LC_ALL=C sort -u \
    | paste -sd, -
}

gauntlet_unit_scope_fingerprint_at() {
  local gauntlet_file="$1"
  local item_id="$2"
  local cutoff="$3"
  local history_line revision_rows revision_at revision_from revision_to
  local active_scope='' last_revision_at=''

  [[ "$cutoff" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || {
    gauntlet_fail "Unit scope generation cutoff is not canonical UTC: $cutoff"
    return 1
  }
  revision_rows="$(
    while IFS= read -r history_line; do
      [[ "$history_line" =~ ^-[[:space:]]Unit[[:space:]]scope-title[[:space:]]revision:[[:space:]]([a-z0-9]+(-[a-z0-9]+)*)[[:space:]]\|[[:space:]]from:[[:space:]]([0-9a-f]{64})[[:space:]]\|[[:space:]]to:[[:space:]]([0-9a-f]{64})[[:space:]]\|.*\|[[:space:]]approved[[:space:]]at:[[:space:]]([^|]+)$ ]] || continue
      [[ "${BASH_REMATCH[1]}" == "$item_id" ]] || continue
      printf '%s\t%s\t%s\n' \
        "$(gauntlet_trim "${BASH_REMATCH[5]}")" \
        "${BASH_REMATCH[3]}" "${BASH_REMATCH[4]}"
    done < <(gauntlet_extract_subsection "$gauntlet_file" 'Work Units' 'Unit History')
  )"
  if [[ -z "$revision_rows" ]]; then
    gauntlet_unit_scope_fingerprint "$gauntlet_file" "$item_id"
    return
  fi

  while IFS=$'\t' read -r revision_at revision_from revision_to; do
    [[ -n "$revision_at" ]] || continue
    if [[ -z "$active_scope" ]]; then
      active_scope="$revision_from"
    fi
    [[ "$active_scope" == "$revision_from" \
      && ( -z "$last_revision_at" || "$last_revision_at" < "$revision_at" ) ]] || {
      gauntlet_fail "Unit scope revisions are not a unique chronological immediate-parent chain: $item_id"
      return 1
    }
    if [[ "$revision_at" < "$cutoff" || "$revision_at" == "$cutoff" ]]; then
      active_scope="$revision_to"
    fi
    last_revision_at="$revision_at"
  done < <(printf '%s\n' "$revision_rows" | LC_ALL=C sort -k1,1)
  printf '%s\n' "$active_scope"
}

gauntlet_unit_manifest_fingerprint_at() {
  local gauntlet_file="$1"
  local units_csv="$2"
  local cutoff="$3"
  local item_id unit_scope material='' history_line topology_material
  local superseded_item superseded_scope replacements approved_at

  while IFS= read -r item_id; do
    [[ -n "$item_id" ]] || continue
    unit_scope="$(gauntlet_unit_scope_fingerprint_at \
      "$gauntlet_file" "$item_id" "$cutoff")" || return 1
    [[ -z "$material" ]] || material+=$'\n'
    material+="id=$item_id"$'\n'"scope-fingerprint=$unit_scope"
  done < <(printf '%s' "$units_csv" | tr ',' '\n' | LC_ALL=C sort -u)
  [[ -n "$material" ]] || {
    gauntlet_fail 'Cannot fingerprint an empty retained unit manifest.'
    return 1
  }

  # Supersession topology becomes active in the exact approved generation that
  # contains its marker. Reconstructing every historical generation from this
  # normalized material prevents a later edge from being backdated silently.
  topology_material="$(
    while IFS= read -r history_line; do
      [[ "$history_line" =~ ^-[[:space:]]Unit[[:space:]]supersession:[[:space:]]([a-z0-9]+(-[a-z0-9]+)*)[[:space:]]\|[[:space:]]scope:[[:space:]]([0-9a-f]{64})[[:space:]]\|[[:space:]]replacements:[[:space:]]([a-z0-9,-]+)[[:space:]]\|.*\|[[:space:]]approved[[:space:]]at:[[:space:]]([^|]+)$ ]] || continue
      superseded_item="${BASH_REMATCH[1]}"
      superseded_scope="${BASH_REMATCH[3]}"
      replacements="${BASH_REMATCH[4]}"
      approved_at="$(gauntlet_trim "${BASH_REMATCH[5]}")"
      [[ "$approved_at" < "$cutoff" || "$approved_at" == "$cutoff" ]] || continue
      printf 'supersession=%s|scope=%s|replacements=%s\n' \
        "$superseded_item" "$superseded_scope" "$replacements"
    done < <(gauntlet_extract_subsection "$gauntlet_file" 'Work Units' 'Unit History')
  )"
  if [[ -n "$topology_material" ]]; then
    material+=$'\n'"$(printf '%s\n' "$topology_material" | LC_ALL=C sort)"
  fi
  gauntlet_hash_text "$material"
}

gauntlet_unit_manifest_fingerprint() {
  local gauntlet_file="$1"

  gauntlet_unit_manifest_fingerprint_at \
    "$gauntlet_file" "$(gauntlet_unit_ids_csv "$gauntlet_file")" '9999-12-31T23:59:59Z'
}

gauntlet_unit_manifest_approved_at() {
  local gauntlet_file="$1"
  local manifest_fingerprint
  local history_line generation_fingerprint approval_time latest_approval=''

  manifest_fingerprint="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
  while IFS= read -r history_line; do
    if [[ "$history_line" =~ ^-[[:space:]]Unit[[:space:]]manifest[[:space:]]approval:[[:space:]]([0-9a-fA-F]{64})[[:space:]]\|.*\|[[:space:]]approved[[:space:]]at:[[:space:]]([^|]+)$ ]]; then
      generation_fingerprint="$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')"
      approval_time="$(gauntlet_trim "${BASH_REMATCH[2]}")"
    elif [[ "$history_line" =~ ^-[[:space:]]Unit[[:space:]]manifest[[:space:]]revision:[[:space:]][a-z0-9]+(-[a-z0-9]+)*[[:space:]]\|.*\|[[:space:]]to:[[:space:]]([0-9a-fA-F]{64})[[:space:]]\|.*\|[[:space:]]approved[[:space:]]at:[[:space:]]([^|]+)$ ]]; then
      generation_fingerprint="$(printf '%s' "${BASH_REMATCH[2]}" | tr '[:upper:]' '[:lower:]')"
      approval_time="$(gauntlet_trim "${BASH_REMATCH[3]}")"
    else
      continue
    fi
    [[ "$generation_fingerprint" == "$manifest_fingerprint" ]] \
      && latest_approval="$approval_time"
  done < <(gauntlet_extract_subsection "$gauntlet_file" 'Work Units' 'Unit History')
  [[ -n "$latest_approval" ]] || {
    gauntlet_fail "Unit manifest approval timestamp cannot be resolved for generation: $manifest_fingerprint"
    return 1
  }
  printf '%s\n' "$latest_approval"
}

gauntlet_unit_status() {
  local gauntlet_file="$1"
  local item_id="$2"

  gauntlet_work_unit_lines "$gauntlet_file" \
    | sed -nE "s/^- \\[[ xX]\\] ${item_id} \\| status: ([^ |]+) \\|.*$/\\1/p" \
    | head -n 1
}

gauntlet_supersession_replacements() {
  local gauntlet_file="$1"
  local item_id="$2"
  local line count

  line="$(gauntlet_extract_subsection "$gauntlet_file" 'Work Units' 'Unit History' \
    | grep -E "^- Unit supersession: ${item_id} \\|" || true)"
  count="$(printf '%s\n' "$line" | sed '/^$/d' | wc -l | tr -d '[:space:]')"
  [[ "$count" -eq 1 ]] || return 1
  [[ "$line" =~ ^-[[:space:]]Unit[[:space:]]supersession:[[:space:]]${item_id}[[:space:]]\|[[:space:]]scope:[[:space:]][0-9a-f]{64}[[:space:]]\|[[:space:]]replacements:[[:space:]]([a-z0-9,-]+)[[:space:]]\| ]] || return 1
  printf '%s\n' "${BASH_REMATCH[1]}"
}

gauntlet_supersession_reaches() {
  local gauntlet_file="$1"
  local ancestor="$2"
  local target="$3"
  local visited_path="${4:-|}"
  local replacements replacement

  [[ "$ancestor" != "$target" ]] || return 0
  [[ "$visited_path" != *"|$ancestor|"* ]] || return 1
  visited_path+="$ancestor|"
  replacements="$(gauntlet_supersession_replacements "$gauntlet_file" "$ancestor" 2>/dev/null || true)"
  [[ -n "$replacements" ]] || return 1
  IFS=',' read -r -a GAUNTLET_SUPERSESSION_REPLACEMENTS <<< "$replacements"
  for replacement in "${GAUNTLET_SUPERSESSION_REPLACEMENTS[@]}"; do
    [[ "$replacement" == "$target" ]] && return 0
    gauntlet_supersession_reaches \
      "$gauntlet_file" "$replacement" "$target" "$visited_path" && return 0
  done
  return 1
}

gauntlet_supersession_reaches_at() {
  local gauntlet_file="$1"
  local ancestor="$2"
  local target="$3"
  local cutoff="$4"
  local visited_path="${5:-|}"
  local marker marker_count approved_at replacements replacement

  [[ "$ancestor" != "$target" ]] || return 0
  [[ "$visited_path" != *"|$ancestor|"* ]] || return 1
  [[ "$cutoff" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || return 1
  visited_path+="$ancestor|"

  marker="$(gauntlet_extract_subsection "$gauntlet_file" 'Work Units' 'Unit History' \
    | grep -E "^- Unit supersession: ${ancestor} \\|" || true)"
  marker_count="$(printf '%s\n' "$marker" | sed '/^$/d' | wc -l | tr -d '[:space:]')"
  [[ "$marker_count" -eq 1 \
    && "$marker" =~ \|[[:space:]]approved[[:space:]]at:[[:space:]]([^|]+)$ ]] || return 1
  approved_at="$(gauntlet_trim "${BASH_REMATCH[1]}")"
  [[ "$approved_at" < "$cutoff" || "$approved_at" == "$cutoff" ]] || return 1

  replacements="$(gauntlet_supersession_replacements "$gauntlet_file" "$ancestor" 2>/dev/null || true)"
  [[ -n "$replacements" ]] || return 1
  IFS=',' read -r -a GAUNTLET_SUPERSESSION_REPLACEMENTS_AT <<< "$replacements"
  for replacement in "${GAUNTLET_SUPERSESSION_REPLACEMENTS_AT[@]}"; do
    [[ "$replacement" == "$target" ]] && return 0
    gauntlet_supersession_reaches_at \
      "$gauntlet_file" "$replacement" "$target" "$cutoff" "$visited_path" \
      && return 0
  done
  return 1
}

gauntlet_failure_applies_to_unit() {
  local gauntlet_file="$1"
  local affected_csv="$2"
  local item_id="$3"
  local affected_item

  [[ "$affected_csv" != 'none' ]] || return 1
  IFS=',' read -r -a GAUNTLET_FAILURE_AFFECTED <<< "$affected_csv"
  for affected_item in "${GAUNTLET_FAILURE_AFFECTED[@]}"; do
    [[ "$affected_item" == "$item_id" ]] && return 0
    gauntlet_supersession_reaches "$gauntlet_file" "$affected_item" "$item_id" && return 0
  done
  return 1
}

gauntlet_failure_applies_to_unit_at() {
  local gauntlet_file="$1"
  local affected_csv="$2"
  local item_id="$3"
  local cutoff="$4"
  local affected_item

  [[ "$affected_csv" != 'none' ]] || return 1
  IFS=',' read -r -a GAUNTLET_FAILURE_AFFECTED_AT <<< "$affected_csv"
  for affected_item in "${GAUNTLET_FAILURE_AFFECTED_AT[@]}"; do
    [[ "$affected_item" == "$item_id" ]] && return 0
    gauntlet_supersession_reaches_at \
      "$gauntlet_file" "$affected_item" "$item_id" "$cutoff" && return 0
  done
  return 1
}

gauntlet_assert_frozen_unit_manifest() {
  local gauntlet_file="$1"
  local recorded computed

  recorded="$(gauntlet_section_field "$gauntlet_file" 'Current State' 'Unit manifest fingerprint')"
  computed="$(gauntlet_unit_manifest_fingerprint "$gauntlet_file")" || return 1
  [[ "$recorded" =~ ^[0-9a-f]{64}$ && "$recorded" == "$computed" ]] || {
    gauntlet_fail 'Gauntlet unit manifest has not been frozen by an accepted opened progress-PR event or has changed without an approved revision.'
    return 1
  }
  printf '%s\n' "$computed"
}

gauntlet_active_scope_fingerprint() {
  local gauntlet_file="$1"
  local unit_line item_id unit_scope material=''

  while IFS= read -r item_id; do
    [[ -n "$item_id" ]] || continue
    unit_scope="$(gauntlet_unit_scope_fingerprint "$gauntlet_file" "$item_id")" || return 1
    material+="$item_id:$unit_scope"$'\n'
  done < <(gauntlet_work_unit_lines "$gauntlet_file" \
    | awk '$0 !~ /\|[[:space:]]status:[[:space:]]superseded[[:space:]]\|/' \
    | sed -nE 's/^- \[[ xX]\] ([a-z0-9]+(-[a-z0-9]+)*) \|.*$/\1/p' \
    | LC_ALL=C sort)
  [[ -n "$material" ]] || {
    gauntlet_fail 'Cannot fingerprint an empty active integration scope.'
    return 1
  }
  gauntlet_hash_text "$material"
}

gauntlet_assert_safe_ai_path() {
  local path="$1"
  local label="$2"
  local project_root parent_canonical

  project_root="$(cd "$OPENCAW_PROJECT_ROOT_RESOLVED" && pwd -P)"
  [[ ! -L "$OPENCAW_PROJECT_AI_DIR" ]] || {
    gauntlet_fail "The project .ai directory must not be a symbolic link."
    return 1
  }
  [[ "$path" == "$OPENCAW_PROJECT_AI_DIR" || "$path" == "$OPENCAW_PROJECT_AI_DIR"/* ]] || {
    gauntlet_fail "$label is outside the resolved project .ai directory: $path"
    return 1
  }
  if [[ -L "$path" ]]; then
    gauntlet_fail "$label must not be a symbolic link: $path"
    return 1
  fi
  parent_canonical="$(cd "$(dirname "$path")" && pwd -P)"
  if [[ "$parent_canonical" != "$project_root/.ai" && "$parent_canonical" != "$project_root/.ai"/* ]]; then
    gauntlet_fail "$label resolves outside the project .ai directory: $path"
    return 1
  fi
}

gauntlet_resolve_file() {
  local ref="$1"
  local candidate gauntlets_root candidate_dir candidate_canonical project_root unit_dir_name

  [[ -d "$OPENCAW_GAUNTLETS_DIR" ]] || {
    gauntlet_fail "Gauntlet directory does not exist: $OPENCAW_GAUNTLETS_DIR"
    return 1
  }

  gauntlet_assert_safe_ai_path "$OPENCAW_GAUNTLETS_DIR" 'Gauntlet root' || return 1
  if [[ "$ref" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
    candidate="$OPENCAW_GAUNTLETS_DIR/$ref/GAUNTLET.md"
  elif [[ -d "$ref" ]]; then
    candidate="$ref/GAUNTLET.md"
  else
    candidate="$ref"
  fi

  [[ -f "$candidate" ]] || {
    gauntlet_fail "Gauntlet file not found for: $ref"
    return 1
  }
  [[ ! -L "$candidate" ]] || {
    gauntlet_fail "Gauntlet file must not be a symbolic link: $candidate"
    return 1
  }

  [[ ! -L "$(dirname "$candidate")" ]] || {
    gauntlet_fail "Gauntlet directory must not be a symbolic link: $(dirname "$candidate")"
    return 1
  }

  project_root="$(cd "$OPENCAW_PROJECT_ROOT_RESOLVED" && pwd -P)"
  gauntlets_root="$(cd "$OPENCAW_GAUNTLETS_DIR" && pwd -P)"
  [[ "$gauntlets_root" == "$project_root/.ai/gauntlets" ]] || {
    gauntlet_fail "Gauntlet root resolves outside the canonical project path: $OPENCAW_GAUNTLETS_DIR"
    return 1
  }
  candidate_dir="$(cd "$(dirname "$candidate")" && pwd -P)"
  candidate_canonical="$candidate_dir/$(basename "$candidate")"
  unit_dir_name="$(basename "$candidate_dir")"

  if [[ "$(dirname "$candidate_dir")" != "$gauntlets_root" ]] \
    || ! gauntlet_validate_name "$unit_dir_name" 'Gauntlet directory name' \
    || [[ "$candidate_canonical" != "$candidate_dir/GAUNTLET.md" ]]; then
    gauntlet_fail "Gauntlet references must resolve under $OPENCAW_GAUNTLETS_DIR: $ref"
    return 1
  fi

  printf '%s\n' "$candidate_canonical"
}

gauntlet_project_relative_artifact() {
  local value="$1"

  value="${value#\`}"
  value="${value%\`}"
  opencaw_validate_single_line "$value" 'Artifact path' || return 1
  if [[ -z "$value" || "$value" == /* || "$value" == . || "$value" == ./* \
    || "$value" == */. || "$value" == *'//'* || "$value" == .. \
    || "$value" == ../* || "$value" == */../* || "$value" == */.. ]]; then
    gauntlet_fail "Artifact paths must be project-relative and must not traverse parents: $value"
    return 1
  fi
  printf '%s\n' "$value"
}

gauntlet_validate_critic_report() {
  local report_file="$1"
  local expected_verdict="$2"
  local expected_head_sha="$3"
  local -a headings=(
    'Artifact Inspected'
    'Bar Comparison'
    'Guardrail Results'
    'Verdict'
    'Largest Remaining Gap'
    'Next Strategy'
  )
  local heading content artifact canonical_artifact artifact_count=0 report_head_sha='' head_sha_count=0 verdict_section verdict_count=0 verdict='' line
  local largest_gap normalized_gap next_strategy normalized_strategy
  local previous_line=0 current_line

  [[ -f "$report_file" && ! -L "$report_file" ]] || {
    gauntlet_fail "Critic report not found as a regular non-symlink file: $report_file"
    return 1
  }

  for heading in "${headings[@]}"; do
    if [[ "$(gauntlet_heading_count "$report_file" "$heading")" -ne 1 ]]; then
      gauntlet_fail "Critic report requires exactly one '## $heading' heading."
      return 1
    fi
    current_line="$(grep -nF -m 1 -- "## $heading" "$report_file" | cut -d: -f1)"
    if [[ $current_line -le $previous_line ]]; then
      gauntlet_fail "Critic report headings are out of order at: ## $heading"
      return 1
    fi
    previous_line="$current_line"
  done

  content="$(gauntlet_extract_section "$report_file" 'Artifact Inspected')"
  while IFS= read -r artifact; do
    artifact="${artifact#- Artifact:}"
    artifact="$(gauntlet_trim "$artifact")"
    canonical_artifact="$(gauntlet_project_relative_artifact "$artifact")" || return 1
    gauntlet_assert_artifact_at_commit "$expected_head_sha" "$canonical_artifact" || return 1
    artifact_count=$((artifact_count + 1))
  done < <(printf '%s\n' "$content" | grep -E '^- Artifact:[[:space:]]*[^[:space:]]' || true)
  if [[ $artifact_count -lt 1 ]]; then
    gauntlet_fail "Artifact Inspected must include at least one '- Artifact: <project-relative-file>' entry."
    return 1
  fi
  while IFS= read -r line; do
    line="$(gauntlet_trim "$line")"
    if [[ "$line" =~ ^-[[:space:]]Head[[:space:]]SHA:[[:space:]]([0-9a-fA-F]+)$ ]]; then
      report_head_sha="${BASH_REMATCH[1]}"
      head_sha_count=$((head_sha_count + 1))
    fi
  done <<< "$content"
  if [[ $head_sha_count -ne 1 ]]; then
    gauntlet_fail "Artifact Inspected must include exactly one '- Head SHA: <full-commit-sha>' entry."
    return 1
  fi
  gauntlet_validate_head_sha "$report_head_sha" 'Critic report Head SHA' || return 1
  if [[ "${report_head_sha,,}" != "${expected_head_sha,,}" ]]; then
    gauntlet_fail "Critic report Head SHA '$report_head_sha' does not match reviewed commit '$expected_head_sha'."
    return 1
  fi

  content="$(gauntlet_extract_section "$report_file" 'Bar Comparison')"
  gauntlet_has_substance "$content" || {
    gauntlet_fail 'Bar Comparison must contain substantive evidence.'
    return 1
  }
  content="$(gauntlet_extract_section "$report_file" 'Guardrail Results')"
  gauntlet_has_substance "$content" || {
    gauntlet_fail 'Guardrail Results must contain substantive evidence.'
    return 1
  }

  verdict_section="$(gauntlet_extract_section "$report_file" 'Verdict')"
  while IFS= read -r line; do
    line="$(gauntlet_trim "$line")"
    if [[ "$line" =~ ^-[[:space:]]+Verdict:[[:space:]]*(pass|fail|blocked)$ ]]; then
      verdict="${BASH_REMATCH[1]}"
      verdict_count=$((verdict_count + 1))
    elif [[ "$line" =~ ^(pass|fail|blocked)$ ]]; then
      verdict="${BASH_REMATCH[1]}"
      verdict_count=$((verdict_count + 1))
    fi
  done <<< "$verdict_section"
  if [[ $verdict_count -ne 1 ]]; then
    gauntlet_fail "Verdict must contain exactly one verdict: pass, fail, or blocked."
    return 1
  fi
  if [[ "$verdict" != "$expected_verdict" ]]; then
    gauntlet_fail "Critic report verdict '$verdict' does not match CLI verdict '$expected_verdict'."
    return 1
  fi

  largest_gap="$(gauntlet_extract_section "$report_file" 'Largest Remaining Gap')"
  gauntlet_has_substance "$largest_gap" || {
    gauntlet_fail 'Largest Remaining Gap must contain a substantive finding.'
    return 1
  }
  next_strategy="$(gauntlet_extract_section "$report_file" 'Next Strategy')"
  gauntlet_has_substance "$next_strategy" || {
    gauntlet_fail 'Next Strategy must contain substantive guidance.'
    return 1
  }

  if [[ "$expected_verdict" != 'pass' ]]; then
    normalized_gap="$(printf '%s\n' "$largest_gap" \
      | sed -E 's/^[[:space:]]*[-*][[:space:]]*//; s/^(Largest[[:space:]]+Remaining[[:space:]]+)?Gap:[[:space:]]*//I; /^[[:space:]]*$/d' \
      | tr '[:upper:]' '[:lower:]')"
    normalized_strategy="$(printf '%s\n' "$next_strategy" \
      | sed -E 's/^[[:space:]]*[-*][[:space:]]*//; s/^(Next[[:space:]]+)?Strategy:[[:space:]]*//I; /^[[:space:]]*$/d' \
      | tr '[:upper:]' '[:lower:]')"
    if printf '%s\n' "$normalized_gap" | grep -Eqi -- '^[[:space:]]*(none|n/?a|not applicable)[.!]?[[:space:]]*$'; then
      gauntlet_fail 'A failed or blocked verdict requires a concrete largest remaining gap.'
      return 1
    fi
    if printf '%s\n' "$normalized_strategy" | grep -Eqi -- '^[[:space:]]*(none|n/?a|not applicable|retry|try again)[.!]?[[:space:]]*$'; then
      gauntlet_fail 'A failed or blocked verdict requires a concrete changed strategy.'
      return 1
    fi
  fi

  normalized_strategy="$(printf '%s\n' "$next_strategy" \
    | sed -E 's/^[[:space:]]*[-*][[:space:]]*//; s/^(Next[[:space:]]+)?Strategy:[[:space:]]*//I; /^[[:space:]]*$/d; s/[[:space:]]+/ /g' \
    | tr '[:upper:]' '[:lower:]')"
  # Consumed by record-gauntlet-round.sh after this validator returns.
  # shellcheck disable=SC2034
  GAUNTLET_CRITIC_NEXT_STRATEGY_FINGERPRINT="$(gauntlet_hash_text "$normalized_strategy")"
}

gauntlet_work_unit_lines() {
  local file="$1"
  gauntlet_extract_section "$file" 'Work Units' | grep -E '^- \[[ xX]\] ' || true
}

gauntlet_set_section_field() {
  local file="$1"
  local heading="$2"
  local key="$3"
  local value="$4"
  local temporary

  temporary="$(mktemp "$(dirname "$file")/.gauntlet-field.XXXXXX")"
  if ! awk -v heading="$heading" -v prefix="- $key:" -v replacement="- $key: $value" '
      { sub(/\r$/, "") }
      $0 == "## " heading { in_section = 1 }
      /^## / && $0 != "## " heading && in_section { in_section = 0 }
      in_section && index($0, prefix) == 1 {
        print replacement
        replaced++
        next
      }
      { print }
      END { if (replaced != 1) exit 42 }
    ' "$file" > "$temporary"; then
    rm -f "$temporary"
    gauntlet_fail "Expected exactly one '$key' field in '$heading'."
    return 1
  fi
  mv "$temporary" "$file"
}

gauntlet_set_work_unit_status() {
  local file="$1"
  local item_id="$2"
  local status="$3"
  local checkbox=' '
  local temporary

  if [[ "$status" == 'passed' || "$status" == 'superseded' ]]; then
    checkbox='x'
  fi

  temporary="$(mktemp "$(dirname "$file")/.gauntlet-unit.XXXXXX")"
  if ! awk -v item="$item_id" -v status="$status" -v checkbox="$checkbox" '
      { sub(/\r$/, "") }
      $0 == "## Work Units" { in_section = 1 }
      /^## / && $0 != "## Work Units" && in_section { in_section = 0 }
      in_section && $0 ~ "^- \\[[ xX]\\] " item " \\| status: " {
        split($0, parts, " \\| title: ")
        if (length(parts[2]) == 0) exit 43
        print "- [" checkbox "] " item " | status: " status " | title: " parts[2]
        replaced++
        next
      }
      { print }
      END { if (replaced != 1) exit 42 }
    ' "$file" > "$temporary"; then
    rm -f "$temporary"
    gauntlet_fail "Expected exactly one work unit named: $item_id"
    return 1
  fi
  mv "$temporary" "$file"
}

gauntlet_reopen_active_units() {
  local file="$1"
  local temporary

  temporary="$(mktemp "$(dirname "$file")/.gauntlet-reopen.XXXXXX")"
  awk '
    { sub(/\r$/, "") }
    $0 == "## Work Units" { in_section = 1 }
    /^## / && $0 != "## Work Units" && in_section { in_section = 0 }
    in_section && $0 ~ /^- \[[ xX]\] [a-z0-9-]+ \| status: (pending|building|critic-failed|passed|blocked) \| title: / {
      line = $0
      sub(/^- \[[ xX]\]/, "- [ ]", line)
      sub(/\| status: (pending|building|critic-failed|passed|blocked) \|/, "| status: critic-failed |", line)
      print line
      next
    }
    { print }
  ' "$file" > "$temporary"
  mv "$temporary" "$file"
}

gauntlet_reopen_selected_units() {
  local file="$1"
  shift
  local item_id

  for item_id in "$@"; do
    gauntlet_set_work_unit_status "$file" "$item_id" 'critic-failed' || return 1
  done
}

gauntlet_reset_integration_review() {
  local file="$1"

  gauntlet_set_section_field "$file" 'Integration Review' 'Verdict' 'pending'
  gauntlet_set_section_field "$file" 'Integration Review' 'Critic ID' ''
  gauntlet_set_section_field "$file" 'Integration Review' 'Isolation' ''
  gauntlet_set_section_field "$file" 'Integration Review' 'Evidence' ''
  gauntlet_set_section_field "$file" 'Integration Review' 'Head SHA' ''
  gauntlet_set_section_field "$file" 'Integration Review' 'Scope fingerprint' 'pending'
  gauntlet_set_section_field "$file" 'Integration Review' 'Quality bar fingerprint' 'pending'
  gauntlet_set_section_field "$file" 'Integration Review' 'Unit manifest fingerprint' 'pending'
  gauntlet_set_section_field "$file" 'Integration Review' 'Execution contract fingerprint' 'pending'
  gauntlet_set_section_field "$file" 'Integration Review' 'Base commit SHA' 'pending'
}

gauntlet_append_round_ledger() {
  local file="$1"
  local entry="$2"
  local temporary

  temporary="$(mktemp "$(dirname "$file")/.gauntlet-ledger.XXXXXX")"
  if ! awk -v entry="$entry" '
      { sub(/\r$/, "") }
      $0 == "## Round Ledger" { in_section = 1; found = 1; print; next }
      /^## / && in_section {
        if (!inserted) print entry
        in_section = 0
        inserted = 1
      }
      in_section && $0 == "- No rounds recorded." { next }
      { print }
      END {
        if (in_section && !inserted) print entry
        if (!found) exit 42
      }
    ' "$file" > "$temporary"; then
    rm -f "$temporary"
    gauntlet_fail "Missing Round Ledger section."
    return 1
  fi
  mv "$temporary" "$file"
}

gauntlet_append_progress_pr_ledger() {
  local file="$1"
  local entry="$2"
  local temporary

  temporary="$(mktemp "$(dirname "$file")/.gauntlet-pr-ledger.XXXXXX")"
  if ! awk -v entry="$entry" '
      { sub(/\r$/, "") }
      $0 == "## Progress PR Ledger" { in_section = 1; found = 1; print; next }
      /^## / && in_section {
        if (!inserted) print entry
        in_section = 0
        inserted = 1
      }
      in_section && $0 == "- No progress PR events recorded." { next }
      { print }
      END {
        if (in_section && !inserted) print entry
        if (!found) exit 42
      }
    ' "$file" > "$temporary"; then
    rm -f "$temporary"
    gauntlet_fail "Missing Progress PR Ledger section."
    return 1
  fi
  mv "$temporary" "$file"
}

gauntlet_append_promotion_qa_ledger() {
  local file="$1"
  local entry="$2"
  local temporary

  temporary="$(mktemp "$(dirname "$file")/.gauntlet-promotion-ledger.XXXXXX")"
  if ! awk -v entry="$entry" '
      { sub(/\r$/, "") }
      $0 == "## Promotion QA Ledger" { in_section = 1; found = 1; print; next }
      /^## / && in_section {
        if (!inserted) print entry
        in_section = 0
        inserted = 1
      }
      in_section && $0 == "- No promotion QA events recorded." { next }
      { print }
      END {
        if (in_section && !inserted) print entry
        if (!found) exit 42
      }
    ' "$file" > "$temporary"; then
    rm -f "$temporary"
    gauntlet_fail "Missing Promotion QA Ledger section."
    return 1
  fi
  mv "$temporary" "$file"
}

gauntlet_append_completion_ledger() {
  local file="$1"
  local entry="$2"
  local temporary

  temporary="$(mktemp "$(dirname "$file")/.gauntlet-completion-ledger.XXXXXX")"
  if ! awk -v entry="$entry" '
      { sub(/\r$/, "") }
      $0 == "## Completion Ledger" { in_section = 1; found = 1; print; next }
      /^## / && in_section {
        if (!inserted) print entry
        in_section = 0
        inserted = 1
      }
      in_section && $0 == "- No completion events recorded." { next }
      { print }
      END {
        if (in_section && !inserted) print entry
        if (!found) exit 42
      }
    ' "$file" > "$temporary"; then
    rm -f "$temporary"
    gauntlet_fail 'Missing Completion Ledger section.'
    return 1
  fi
  mv "$temporary" "$file"
}

gauntlet_comma_list_contains() {
  local csv="$1"
  local expected="$2"
  local value

  IFS=',' read -r -a GAUNTLET_CSV_VALUES <<< "$csv"
  for value in "${GAUNTLET_CSV_VALUES[@]}"; do
    [[ "$value" == "$expected" ]] && return 0
  done
  return 1
}

gauntlet_latest_quality_revision_id() {
  local gauntlet_file="$1"
  gauntlet_extract_subsection "$gauntlet_file" 'Work Units' 'Unit History' \
    | sed -nE 's/^- Quality bar revision: ([a-z0-9]+(-[a-z0-9]+)*) \|.*$/\1/p' \
    | tail -n 1
}

gauntlet_progress_pr_ledger_position() {
  local gauntlet_file="$1"
  local evidence_path="$2"
  local ledger_line ledger_path position=0 matched_position='' matches=0

  while IFS= read -r ledger_line; do
    [[ "$ledger_line" == '- '*" | record: "*" | sha256: "* ]] || continue
    position=$((position + 1))
    ledger_path="${ledger_line##* | record: }"
    ledger_path="${ledger_path%% | sha256: *}"
    [[ "$ledger_path" == "$evidence_path" ]] || continue
    matched_position="$position"
    matches=$((matches + 1))
  done < <(gauntlet_extract_section "$gauntlet_file" 'Progress PR Ledger')

  [[ "$matches" -eq 1 ]] || {
    gauntlet_fail "Progress PR evidence must resolve exactly once in append order: $evidence_path"
    return 1
  }
  printf '%s\n' "$matched_position"
}

gauntlet_progress_pr_event_precedes() {
  local gauntlet_file="$1"
  local earlier_path="$2"
  local later_path="$3"
  local earlier_position later_position

  earlier_position="$(gauntlet_progress_pr_ledger_position "$gauntlet_file" "$earlier_path")" || return 1
  later_position="$(gauntlet_progress_pr_ledger_position "$gauntlet_file" "$later_path")" || return 1
  [[ "$earlier_position" -lt "$later_position" ]]
}

gauntlet_round_ledger_position() {
  local gauntlet_file="$1"
  local evidence_path="$2"
  local ledger_line ledger_path position=0 matched_position='' matches=0

  while IFS= read -r ledger_line; do
    [[ "$ledger_line" == '- '*" | evidence: "*" | sha256: "* ]] || continue
    position=$((position + 1))
    ledger_path="${ledger_line##* | evidence: }"
    ledger_path="${ledger_path%% | sha256: *}"
    [[ "$ledger_path" == "$evidence_path" ]] || continue
    matched_position="$position"
    matches=$((matches + 1))
  done < <(gauntlet_extract_section "$gauntlet_file" 'Round Ledger')

  [[ "$matches" -eq 1 ]] || {
    gauntlet_fail "Round evidence must resolve exactly once in append order: $evidence_path"
    return 1
  }
  printf '%s\n' "$matched_position"
}

gauntlet_round_event_precedes() {
  local gauntlet_file="$1"
  local earlier_path="$2"
  local later_path="$3"
  local earlier_position later_position

  earlier_position="$(gauntlet_round_ledger_position "$gauntlet_file" "$earlier_path")" || return 1
  later_position="$(gauntlet_round_ledger_position "$gauntlet_file" "$later_path")" || return 1
  [[ "$earlier_position" -lt "$later_position" ]]
}

# Establishes order only from a durable same-ledger append position or an
# explicit cross-ledger evidence edge. It intentionally provides no arbitrary
# lexical/type order for unrelated records created in the same UTC second.
gauntlet_equal_time_failure_precedes() {
  local gauntlet_file="$1"
  local earlier_path="$2"
  local later_path="$3"
  local earlier_file later_file later_round earlier_round later_root

  [[ "$earlier_path" != "$later_path" ]] || return 1
  earlier_file="$OPENCAW_PROJECT_ROOT_RESOLVED/$earlier_path"
  later_file="$OPENCAW_PROJECT_ROOT_RESOLVED/$later_path"

  if [[ "$earlier_path" == .ai/gauntlets/*/pr-events/*/event-*.md \
    && "$later_path" == .ai/gauntlets/*/pr-events/*/event-*.md ]]; then
    gauntlet_progress_pr_event_precedes "$gauntlet_file" "$earlier_path" "$later_path"
    return
  fi
  if [[ "$earlier_path" == .ai/gauntlets/*/rounds/*/round-*.md \
    && "$later_path" == .ai/gauntlets/*/rounds/*/round-*.md ]]; then
    gauntlet_round_event_precedes "$gauntlet_file" "$earlier_path" "$later_path"
    return
  fi

  if [[ "$later_path" == .ai/gauntlets/*/rounds/*/round-*.md ]]; then
    later_root="$(gauntlet_section_field "$later_file" 'Round Metadata' 'Remediation root')"
    [[ "$later_root" == "$earlier_path" ]]
    return
  fi
  if [[ "$later_path" == .ai/gauntlets/*/pr-events/*/event-*.md \
    && "$earlier_path" == .ai/gauntlets/*/rounds/*/round-*.md ]]; then
    later_round="$(gauntlet_section_field "$later_file" 'PR Event Metadata' 'Critic round')"
    [[ "$later_round" == "$earlier_path" ]] && return 0
    if [[ "$later_round" == .ai/gauntlets/*/rounds/*/round-*.md ]]; then
      gauntlet_round_event_precedes "$gauntlet_file" "$earlier_path" "$later_round"
      return
    fi
  fi

  # A QA failure explicitly consumes its critic round. This reverse lookup is
  # useful when the failure candidates happen to be visited in the other order.
  if [[ "$earlier_path" == .ai/gauntlets/*/pr-events/*/event-*.md \
    && "$later_path" == .ai/gauntlets/*/rounds/*/round-*.md ]]; then
    earlier_round="$(gauntlet_section_field "$earlier_file" 'PR Event Metadata' 'Critic round')"
    [[ "$earlier_round" == "$later_path" ]] && return 1
  fi
  return 1
}

gauntlet_opened_event_for_pr() {
  local gauntlet_dir="$1"
  local item_id="$2"
  local pr_url="${3%/}"
  local candidate candidate_pr matched='' count=0

  [[ -d "$gauntlet_dir/pr-events/$item_id" ]] || return 1
  while IFS= read -r candidate; do
    [[ "$(gauntlet_section_field "$candidate" 'PR Event Metadata' 'Event')" == 'opened' ]] || continue
    candidate_pr="$(gauntlet_section_field "$candidate" 'PR Event Metadata' 'PR URL')"
    [[ "${candidate_pr%/}" == "$pr_url" ]] || continue
    matched="$candidate"
    count=$((count + 1))
  done < <(find "$gauntlet_dir/pr-events/$item_id" -maxdepth 1 -type f -name 'event-*.md' -print | LC_ALL=C sort)
  [[ "$count" -eq 1 ]] || {
    gauntlet_fail "Progress PR must map to exactly one immutable opened event: $pr_url"
    return 1
  }
  printf '%s\n' "$matched"
}

gauntlet_parse_publication_checkpoint_marker() {
  local body="$1"
  local marker marker_count publication_count

  marker="$(printf '%s\n' "$body" | grep -Eo '<!-- opencaw-gauntlet-publication:v1 checkpoint=\.ai/gauntlets/[a-z0-9]+(-[a-z0-9]+)*/publication-checkpoints/[a-z0-9]+(-[a-z0-9]+)*/checkpoint-[0-9]{3,}\.md checkpoint-sha256=[0-9a-f]{64} -->' || true)"
  marker_count="$(printf '%s\n' "$marker" | sed '/^$/d' | wc -l | tr -d '[:space:]')"
  publication_count="$(printf '%s\n' "$body" | grep -Fo '<!-- opencaw-gauntlet-publication:' | wc -l | tr -d '[:space:]')"
  [[ "$marker_count" -eq 1 && "$publication_count" -eq 1 ]] || {
    gauntlet_fail 'Progress PR body requires exactly one canonical OpenCaw Gauntlet publication checkpoint marker.'
    return 1
  }
  GAUNTLET_PUBLICATION_CHECKPOINT="$(printf '%s\n' "$marker" | sed -E 's/^.* checkpoint=([^ ]+) checkpoint-sha256=.*$/\1/')"
  GAUNTLET_PUBLICATION_CHECKPOINT_SHA256="$(printf '%s\n' "$marker" | sed -E 's/^.* checkpoint-sha256=([0-9a-f]{64}) -->$/\1/')"
}

gauntlet_assert_progress_publication_body() {
  local body="$1"
  local issue_url="$2"
  local opened_event_file="$3"
  local expected_checkpoint expected_checkpoint_hash checkpoint_file

  [[ -f "$opened_event_file" && ! -L "$opened_event_file" ]] || {
    gauntlet_fail "Opened progress-PR evidence is missing or unsafe: $opened_event_file"
    return 1
  }
  gauntlet_assert_safe_ai_path "$opened_event_file" \
    'Opened progress-PR evidence' || return 1
  [[ "$(gauntlet_section_field_count \
      "$opened_event_file" 'PR Event Metadata' 'Publication checkpoint')" -eq 1 \
    && "$(gauntlet_section_field_count \
      "$opened_event_file" 'PR Event Metadata' 'Publication checkpoint sha256')" -eq 1 ]] || {
    gauntlet_fail 'Opened progress-PR evidence requires one publication checkpoint and hash.'
    return 1
  }

  gauntlet_assert_progress_issue_link "$body" "$issue_url" || return 1
  gauntlet_parse_publication_checkpoint_marker "$body" || return 1
  expected_checkpoint="$(gauntlet_section_field \
    "$opened_event_file" 'PR Event Metadata' 'Publication checkpoint')"
  expected_checkpoint_hash="$(gauntlet_section_field \
    "$opened_event_file" 'PR Event Metadata' 'Publication checkpoint sha256')"
  [[ "$GAUNTLET_PUBLICATION_CHECKPOINT" == "$expected_checkpoint" \
    && "$GAUNTLET_PUBLICATION_CHECKPOINT_SHA256" == "$expected_checkpoint_hash" ]] || {
    gauntlet_fail 'Live progress PR body changed its immutable publication checkpoint marker.'
    return 1
  }

  checkpoint_file="$OPENCAW_PROJECT_ROOT_RESOLVED/$expected_checkpoint"
  gauntlet_assert_safe_ai_path "$checkpoint_file" \
    'Progress PR publication checkpoint' || return 1
  [[ -f "$checkpoint_file" && ! -L "$checkpoint_file" \
    && "$expected_checkpoint_hash" == "$(gauntlet_hash_file "$checkpoint_file")" ]] || {
    gauntlet_fail 'Live progress PR body no longer binds intact immutable checkpoint evidence.'
    return 1
  }
}

gauntlet_resolve_remediation_trigger_file() {
  local gauntlet_file="$1"
  local trigger="$2"
  local gauntlet_dir gauntlet_name trigger_file

  gauntlet_dir="$(cd "$(dirname "$gauntlet_file")" && pwd -P)" || {
    gauntlet_fail "Unable to resolve the Gauntlet directory for remediation trigger: $trigger"
    return 1
  }
  gauntlet_name="$(basename "$gauntlet_dir")"
  [[ "$gauntlet_name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ \
    && ( "$trigger" =~ ^\.ai/gauntlets/${gauntlet_name}/rounds/[a-z0-9]+(-[a-z0-9]+)*/round-[0-9]{3,}\.md$ \
      || "$trigger" =~ ^\.ai/gauntlets/${gauntlet_name}/promotion-events/event-[0-9]{3,}\.md$ \
      || "$trigger" =~ ^\.ai/gauntlets/${gauntlet_name}/pr-events/[a-z0-9]+(-[a-z0-9]+)*/event-[0-9]{3,}\.md$ ) ]] || {
    gauntlet_fail "Remediation trigger is not canonical immutable evidence for $gauntlet_name: $trigger"
    return 1
  }
  trigger_file="$OPENCAW_PROJECT_ROOT_RESOLVED/$trigger"
  gauntlet_assert_safe_ai_path "$trigger_file" 'Remediation trigger evidence' || return 1
  [[ -f "$trigger_file" && ! -L "$trigger_file" ]] || {
    gauntlet_fail "Remediation trigger evidence is missing or unsafe: $trigger"
    return 1
  }
  printf '%s\n' "$trigger_file"
}

gauntlet_quality_revision_trigger_line() {
  local gauntlet_file="$1"
  local trigger="$2"
  local revision_id revision_line count

  [[ "$trigger" =~ ^quality-revision:([a-z0-9]+(-[a-z0-9]+)*)$ ]] || {
    gauntlet_fail "Quality revision trigger is not canonical: $trigger"
    return 1
  }
  revision_id="${BASH_REMATCH[1]}"
  revision_line="$(gauntlet_extract_subsection "$gauntlet_file" 'Work Units' 'Unit History' \
    | awk -v prefix="- Quality bar revision: $revision_id |" \
      'index($0, prefix) == 1 { print }')"
  count="$(printf '%s\n' "$revision_line" | sed '/^$/d' | wc -l | tr -d '[:space:]')"
  [[ "$count" -eq 1 ]] || {
    gauntlet_fail "Quality revision trigger does not resolve exactly once: $trigger"
    return 1
  }
  printf '%s\n' "$revision_line"
}

gauntlet_remediation_trigger_hash() {
  local gauntlet_file="$1"
  local trigger="$2"
  local trigger_file revision_id revision_line count

  case "$trigger" in
    none)
      printf 'none\n'
      return 0
      ;;
    quality-revision:*)
      revision_line="$(gauntlet_quality_revision_trigger_line \
        "$gauntlet_file" "$trigger")" || return 1
      gauntlet_hash_text "$revision_line"
      return 0
      ;;
  esac
  trigger_file="$(gauntlet_resolve_remediation_trigger_file \
    "$gauntlet_file" "$trigger")" || return 1
  gauntlet_hash_file "$trigger_file"
}

gauntlet_remediation_root_for_trigger() {
  local gauntlet_file="$1"
  local item_id="$2"
  local trigger="$3"
  local consumer_cutoff="${4:-}"
  local gauntlet_dir gauntlet_name trigger_file trigger_event trigger_item trigger_time affected applicable=0
  local revision_id revision_line revision_time failure_time failure_relative latest_failure='none' latest_failure_time=''

  gauntlet_dir="$(cd "$(dirname "$gauntlet_file")" && pwd -P)"
  gauntlet_name="$(basename "$gauntlet_dir")"
  if [[ -n "$consumer_cutoff" \
    && ! "$consumer_cutoff" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
    gauntlet_fail "Remediation consumer cutoff is not a canonical UTC timestamp: $consumer_cutoff"
    return 1
  fi
  case "$trigger" in
    none) printf 'none\n'; return 0 ;;
    quality-revision:*)
      revision_line="$(gauntlet_quality_revision_trigger_line \
        "$gauntlet_file" "$trigger")" || return 1
      revision_id="${trigger#quality-revision:}"
      [[ "$(printf '%s\n' "$revision_line" | sed '/^$/d' | wc -l | tr -d '[:space:]')" -eq 1 \
        && "$revision_line" =~ \|[[:space:]]approved[[:space:]]at:[[:space:]]([^|]+)[[:space:]]\| ]] || {
        gauntlet_fail "Quality revision remediation root cannot resolve its approval: $trigger"
        return 1
      }
      revision_time="$(gauntlet_trim "${BASH_REMATCH[1]}")"
      if [[ -n "$consumer_cutoff" \
        && ( ! "$revision_time" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ \
          || "$consumer_cutoff" < "$revision_time" ) ]]; then
        gauntlet_fail "Publication checkpoint remediation trigger was not active at its Recorded at timestamp: $trigger"
        return 1
      fi
      while IFS=$'\t' read -r failure_time failure_relative; do
        [[ -n "$failure_relative" ]] || continue
        # A quality revision does not cite a failure record, so an equal-second
        # failure has no durable edge proving that it existed before approval.
        [[ "$failure_time" < "$revision_time" ]] || continue
        if [[ -z "$latest_failure_time" || "$latest_failure_time" < "$failure_time" ]]; then
          latest_failure_time="$failure_time"
          latest_failure="$failure_relative"
        elif [[ "$latest_failure_time" == "$failure_time" ]]; then
          if gauntlet_equal_time_failure_precedes \
            "$gauntlet_file" "$latest_failure" "$failure_relative"; then
            latest_failure="$failure_relative"
          elif ! gauntlet_equal_time_failure_precedes \
            "$gauntlet_file" "$failure_relative" "$latest_failure"; then
            gauntlet_fail "Quality revision has causally unordered latest failure roots at $failure_time: $latest_failure and $failure_relative"
            return 1
          fi
        fi
      done < <(gauntlet_applicable_failures \
        "$gauntlet_file" "$item_id" "$revision_time" | LC_ALL=C sort -k1,1 -k2,2)
      printf '%s\n' "$latest_failure"
      return 0
      ;;
  esac
  trigger_file="$(gauntlet_resolve_remediation_trigger_file \
    "$gauntlet_file" "$trigger")" || return 1
  if [[ "$trigger" =~ ^\.ai/gauntlets/${gauntlet_name}/rounds/([a-z0-9]+(-[a-z0-9]+)*)/round-[0-9]{3,}\.md$ ]]; then
    trigger_item="$(gauntlet_section_field "$trigger_file" 'Round Metadata' 'Item')"
    trigger_event="$(gauntlet_section_field "$trigger_file" 'Round Metadata' 'Verdict')"
    trigger_time="$(gauntlet_section_field "$trigger_file" 'Round Metadata' 'Recorded at')"
    if [[ -n "$consumer_cutoff" \
      && ( ! "$trigger_time" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ \
        || "$consumer_cutoff" < "$trigger_time" ) ]]; then
      gauntlet_fail "Publication checkpoint remediation trigger was not active at its Recorded at timestamp: $trigger"
      return 1
    fi
    if [[ "$trigger_item" == 'integration' || "$trigger_item" == "$item_id" ]]; then
      applicable=1
    elif [[ -n "$consumer_cutoff" ]]; then
      if gauntlet_supersession_reaches_at \
        "$gauntlet_file" "$trigger_item" "$item_id" "$consumer_cutoff"; then
        applicable=1
      elif gauntlet_supersession_reaches "$gauntlet_file" "$trigger_item" "$item_id"; then
        gauntlet_fail "Publication checkpoint Unit supersession path was not active at its Recorded at timestamp: $trigger_item -> $item_id"
        return 1
      fi
    elif gauntlet_supersession_reaches "$gauntlet_file" "$trigger_item" "$item_id"; then
      applicable=1
    fi
    [[ ( "$trigger_event" == 'fail' || "$trigger_event" == 'blocked' ) \
      && "$applicable" -eq 1 ]] || {
      gauntlet_fail "Round remediation trigger is not an applicable failure for $item_id: $trigger"
      return 1
    }
    printf '%s\n' "$trigger"
    return 0
  fi
  if [[ "$trigger" =~ ^\.ai/gauntlets/${gauntlet_name}/promotion-events/event-[0-9]{3,}\.md$ ]]; then
    affected="$(gauntlet_section_field "$trigger_file" 'Promotion QA Event Metadata' 'Affected units')"
    trigger_time="$(gauntlet_section_field "$trigger_file" 'Promotion QA Event Metadata' 'Recorded at')"
    if [[ -n "$consumer_cutoff" \
      && ( ! "$trigger_time" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ \
        || "$consumer_cutoff" < "$trigger_time" ) ]]; then
      gauntlet_fail "Publication checkpoint remediation trigger was not active at its Recorded at timestamp: $trigger"
      return 1
    fi
    applicable=0
    if [[ -n "$consumer_cutoff" ]]; then
      if gauntlet_failure_applies_to_unit_at \
        "$gauntlet_file" "$affected" "$item_id" "$consumer_cutoff"; then
        applicable=1
      elif gauntlet_failure_applies_to_unit "$gauntlet_file" "$affected" "$item_id"; then
        gauntlet_fail "Publication checkpoint Unit supersession path was not active at its Recorded at timestamp for $item_id"
        return 1
      fi
    else
      gauntlet_failure_applies_to_unit "$gauntlet_file" "$affected" "$item_id" && applicable=1
    fi
    [[ "$(gauntlet_section_field "$trigger_file" 'Promotion QA Event Metadata' 'Verdict')" == 'fail' \
      && "$applicable" -eq 1 ]] || {
      gauntlet_fail "Promotion remediation trigger is not an applicable failure for $item_id: $trigger"
      return 1
    }
    printf '%s\n' "$trigger"
    return 0
  fi
  [[ "$trigger" =~ ^\.ai/gauntlets/${gauntlet_name}/pr-events/([a-z0-9]+(-[a-z0-9]+)*)/event-[0-9]{3,}\.md$ ]] || {
    gauntlet_fail "Remediation trigger cannot resolve a canonical root: $trigger"
    return 1
  }
  trigger_item="${BASH_REMATCH[1]}"
  trigger_event="$(gauntlet_section_field "$trigger_file" 'PR Event Metadata' 'Event')"
  trigger_time="$(gauntlet_section_field "$trigger_file" 'PR Event Metadata' 'Recorded at')"
  if [[ -n "$consumer_cutoff" \
    && ( ! "$trigger_time" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ \
      || "$consumer_cutoff" < "$trigger_time" ) ]]; then
    gauntlet_fail "Publication checkpoint remediation trigger was not active at its Recorded at timestamp: $trigger"
    return 1
  fi
  applicable=0
  if [[ "$trigger_item" == "$item_id" ]]; then
    applicable=1
  elif [[ -n "$consumer_cutoff" ]]; then
    if gauntlet_supersession_reaches_at \
      "$gauntlet_file" "$trigger_item" "$item_id" "$consumer_cutoff"; then
      applicable=1
    elif gauntlet_supersession_reaches "$gauntlet_file" "$trigger_item" "$item_id"; then
      gauntlet_fail "Publication checkpoint Unit supersession path was not active at its Recorded at timestamp: $trigger_item -> $item_id"
      return 1
    fi
  elif gauntlet_supersession_reaches "$gauntlet_file" "$trigger_item" "$item_id"; then
    applicable=1
  fi
  [[ ( "$trigger_event" == 'qa-fail' || "$trigger_event" == 'closed' ) \
    && "$(gauntlet_section_field "$trigger_file" 'PR Event Metadata' 'Item')" == "$trigger_item" \
    && "$applicable" -eq 1 ]] || {
    gauntlet_fail "PR-event remediation trigger is not an applicable failure for $item_id: $trigger"
    return 1
  }
  printf '%s\n' "$trigger"
}

gauntlet_resolve_remediation_root() {
  local gauntlet_file="$1"
  local item_id="$2"
  local opened_file="$3"
  local gauntlet_dir gauntlet_name trigger checkpoint checkpoint_file checkpoint_cutoff
  local checkpoint_root checkpoint_root_hash resolved_root root_file

  gauntlet_dir="$(cd "$(dirname "$gauntlet_file")" && pwd -P)"
  gauntlet_name="$(basename "$gauntlet_dir")"
  trigger="$(gauntlet_section_field "$opened_file" 'PR Event Metadata' 'Remediation trigger')"
  checkpoint="$(gauntlet_section_field "$opened_file" 'PR Event Metadata' 'Publication checkpoint')"
  checkpoint_file="$OPENCAW_PROJECT_ROOT_RESOLVED/$checkpoint"
  [[ "$checkpoint" =~ ^\.ai/gauntlets/${gauntlet_name}/publication-checkpoints/${item_id}/checkpoint-[0-9]{3,}\.md$ ]] || {
    gauntlet_fail "Opened remediation evidence lacks a safe publication checkpoint cutoff: ${opened_file#"$OPENCAW_PROJECT_ROOT_RESOLVED"/}"
    return 1
  }
  gauntlet_assert_safe_ai_path "$checkpoint_file" \
    'Opened remediation publication checkpoint' || return 1
  [[ -f "$checkpoint_file" && ! -L "$checkpoint_file" ]] || {
    gauntlet_fail "Opened remediation evidence lacks a safe publication checkpoint cutoff: ${opened_file#"$OPENCAW_PROJECT_ROOT_RESOLVED"/}"
    return 1
  }
  [[ "$(gauntlet_section_field_count \
      "$checkpoint_file" 'Publication Checkpoint Metadata' 'Remediation root')" -eq 1 \
    && "$(gauntlet_section_field_count \
      "$checkpoint_file" 'Publication Checkpoint Metadata' 'Remediation root sha256')" -eq 1 ]] || {
    gauntlet_fail "Opened remediation publication checkpoint requires one frozen root and hash: $checkpoint"
    return 1
  }
  checkpoint_cutoff="$(gauntlet_section_field "$checkpoint_file" 'Publication Checkpoint Metadata' 'Recorded at')"
  checkpoint_root="$(gauntlet_section_field \
    "$checkpoint_file" 'Publication Checkpoint Metadata' 'Remediation root')"
  checkpoint_root_hash="$(gauntlet_section_field \
    "$checkpoint_file" 'Publication Checkpoint Metadata' 'Remediation root sha256')"
  resolved_root="$(gauntlet_remediation_root_for_trigger \
    "$gauntlet_file" "$item_id" "$trigger" "$checkpoint_cutoff")" || return 1
  [[ "$resolved_root" == "$checkpoint_root" ]] || {
    gauntlet_fail "Opened remediation root no longer matches its immutable publication checkpoint: $checkpoint"
    return 1
  }
  if [[ "$checkpoint_root" == 'none' ]]; then
    [[ "$checkpoint_root_hash" == 'none' ]] || {
      gauntlet_fail "Opened remediation publication checkpoint has a stale none-root hash: $checkpoint"
      return 1
    }
  else
    root_file="$(gauntlet_resolve_remediation_trigger_file \
      "$gauntlet_file" "$checkpoint_root")" || return 1
    [[ "$checkpoint_root_hash" == "$(gauntlet_hash_file "$root_file")" ]] || {
      gauntlet_fail "Opened remediation root hash no longer matches its immutable publication checkpoint: $checkpoint_root"
      return 1
    }
  fi
  printf '%s\n' "$checkpoint_root"
}

gauntlet_applicable_failures() {
  local gauntlet_file="$1"
  local item_id="$2"
  local consumer_cutoff="${3:-}"
  local gauntlet_dir candidate verdict affected recorded_at relative candidate_item event

  gauntlet_dir="$(cd "$(dirname "$gauntlet_file")" && pwd -P)"
  if [[ -n "$consumer_cutoff" \
    && ! "$consumer_cutoff" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
    gauntlet_fail "Failure consumer cutoff is not a canonical UTC timestamp: $consumer_cutoff"
    return 1
  fi
  if [[ -d "$gauntlet_dir/rounds" ]]; then
    while IFS= read -r candidate; do
      candidate_item="$(gauntlet_section_field "$candidate" 'Round Metadata' 'Item')"
      [[ "$candidate_item" != 'integration' ]] || continue
      verdict="$(gauntlet_section_field "$candidate" 'Round Metadata' 'Verdict')"
      [[ "$verdict" == 'fail' || "$verdict" == 'blocked' ]] || continue
      recorded_at="$(gauntlet_section_field "$candidate" 'Round Metadata' 'Recorded at')"
      if [[ -n "$consumer_cutoff" \
        && ( ! "$recorded_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ \
          || "$consumer_cutoff" < "$recorded_at" ) ]]; then
        continue
      fi
      if [[ -n "$consumer_cutoff" ]]; then
        gauntlet_failure_applies_to_unit_at \
          "$gauntlet_file" "$candidate_item" "$item_id" "$consumer_cutoff" || continue
      else
        gauntlet_failure_applies_to_unit "$gauntlet_file" "$candidate_item" "$item_id" || continue
      fi
      relative="${candidate#"$OPENCAW_PROJECT_ROOT_RESOLVED"/}"
      printf '%s\t%s\n' "$recorded_at" "$relative"
    done < <(find "$gauntlet_dir/rounds" -mindepth 2 -maxdepth 2 -type f -name 'round-*.md' -print | LC_ALL=C sort)
  fi
  if [[ -d "$gauntlet_dir/rounds/integration" ]]; then
    while IFS= read -r candidate; do
      verdict="$(gauntlet_section_field "$candidate" 'Round Metadata' 'Verdict')"
      [[ "$verdict" == 'fail' || "$verdict" == 'blocked' ]] || continue
      affected="$(gauntlet_section_field "$candidate" 'Round Metadata' 'Affected units')"
      recorded_at="$(gauntlet_section_field "$candidate" 'Round Metadata' 'Recorded at')"
      if [[ -n "$consumer_cutoff" \
        && ( ! "$recorded_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ \
          || "$consumer_cutoff" < "$recorded_at" ) ]]; then
        continue
      fi
      if [[ -n "$consumer_cutoff" ]]; then
        gauntlet_failure_applies_to_unit_at \
          "$gauntlet_file" "$affected" "$item_id" "$consumer_cutoff" || continue
      else
        gauntlet_failure_applies_to_unit "$gauntlet_file" "$affected" "$item_id" || continue
      fi
      relative="${candidate#"$OPENCAW_PROJECT_ROOT_RESOLVED"/}"
      printf '%s\t%s\n' "$recorded_at" "$relative"
    done < <(find "$gauntlet_dir/rounds/integration" -maxdepth 1 -type f -name 'round-*.md' -print | LC_ALL=C sort)
  fi
  if [[ -d "$gauntlet_dir/promotion-events" ]]; then
    while IFS= read -r candidate; do
      [[ "$(gauntlet_section_field "$candidate" 'Promotion QA Event Metadata' 'Verdict')" == 'fail' ]] || continue
      affected="$(gauntlet_section_field "$candidate" 'Promotion QA Event Metadata' 'Affected units')"
      recorded_at="$(gauntlet_section_field "$candidate" 'Promotion QA Event Metadata' 'Recorded at')"
      if [[ -n "$consumer_cutoff" \
        && ( ! "$recorded_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ \
          || "$consumer_cutoff" < "$recorded_at" ) ]]; then
        continue
      fi
      if [[ -n "$consumer_cutoff" ]]; then
        gauntlet_failure_applies_to_unit_at \
          "$gauntlet_file" "$affected" "$item_id" "$consumer_cutoff" || continue
      else
        gauntlet_failure_applies_to_unit "$gauntlet_file" "$affected" "$item_id" || continue
      fi
      relative="${candidate#"$OPENCAW_PROJECT_ROOT_RESOLVED"/}"
      printf '%s\t%s\n' "$recorded_at" "$relative"
    done < <(find "$gauntlet_dir/promotion-events" -maxdepth 1 -type f -name 'event-*.md' -print | LC_ALL=C sort)
  fi
  if [[ -d "$gauntlet_dir/pr-events" ]]; then
    while IFS= read -r candidate; do
      event="$(gauntlet_section_field "$candidate" 'PR Event Metadata' 'Event')"
      [[ "$event" == 'qa-fail' || "$event" == 'closed' ]] || continue
      candidate_item="$(gauntlet_section_field "$candidate" 'PR Event Metadata' 'Item')"
      recorded_at="$(gauntlet_section_field "$candidate" 'PR Event Metadata' 'Recorded at')"
      if [[ -n "$consumer_cutoff" \
        && ( ! "$recorded_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ \
          || "$consumer_cutoff" < "$recorded_at" ) ]]; then
        continue
      fi
      if [[ -n "$consumer_cutoff" ]]; then
        gauntlet_failure_applies_to_unit_at \
          "$gauntlet_file" "$candidate_item" "$item_id" "$consumer_cutoff" || continue
      else
        gauntlet_failure_applies_to_unit "$gauntlet_file" "$candidate_item" "$item_id" || continue
      fi
      relative="${candidate#"$OPENCAW_PROJECT_ROOT_RESOLVED"/}"
      printf '%s\t%s\n' "$recorded_at" "$relative"
    done < <(find "$gauntlet_dir/pr-events" -mindepth 2 -maxdepth 2 -type f -name 'event-*.md' -print | LC_ALL=C sort)
  fi
}

gauntlet_closed_cycle_contains_failure() {
  local gauntlet_file="$1"
  local item_id="$2"
  local closed_relative="$3"
  local failure_relative="$4"
  local gauntlet_dir gauntlet_name closed_file closed_pr opened_file opened_relative opened_pr
  local round_failure=0 round_relative='' round_file round_pr round_verdict round_opened round_opened_hash
  local qa_file='' qa_relative='' qa_round qa_pr qa_count=0 candidate candidate_pr

  gauntlet_dir="$(cd "$(dirname "$gauntlet_file")" && pwd -P)"
  gauntlet_name="$(basename "$gauntlet_dir")"
  [[ "$closed_relative" =~ ^\.ai/gauntlets/${gauntlet_name}/pr-events/${item_id}/event-[0-9]{3,}\.md$ ]] || return 1
  closed_file="$OPENCAW_PROJECT_ROOT_RESOLVED/$closed_relative"
  [[ -f "$closed_file" && ! -L "$closed_file" \
    && "$(gauntlet_section_field "$closed_file" 'PR Event Metadata' 'Event')" == 'closed' \
    && "$(gauntlet_section_field "$closed_file" 'PR Event Metadata' 'Item')" == "$item_id" ]] || return 1
  closed_pr="$(gauntlet_section_field "$closed_file" 'PR Event Metadata' 'PR URL')"
  closed_pr="${closed_pr%/}"
  [[ -n "$closed_pr" ]] || return 1

  opened_file="$(gauntlet_opened_event_for_pr "$gauntlet_dir" "$item_id" "$closed_pr")" || return 1
  opened_relative="${opened_file#"$OPENCAW_PROJECT_ROOT_RESOLVED"/}"
  [[ "$opened_relative" =~ ^\.ai/gauntlets/${gauntlet_name}/pr-events/${item_id}/event-[0-9]{3,}\.md$ \
    && -f "$opened_file" && ! -L "$opened_file" \
    && "$(gauntlet_section_field "$opened_file" 'PR Event Metadata' 'Event')" == 'opened' \
    && "$(gauntlet_section_field "$opened_file" 'PR Event Metadata' 'Item')" == "$item_id" ]] || return 1
  opened_pr="$(gauntlet_section_field "$opened_file" 'PR Event Metadata' 'PR URL')"
  opened_pr="${opened_pr%/}"
  [[ "$opened_pr" == "$closed_pr" ]] || return 1
  gauntlet_progress_pr_event_precedes \
    "$gauntlet_file" "$opened_relative" "$closed_relative" || return 1

  if [[ "$failure_relative" =~ ^\.ai/gauntlets/${gauntlet_name}/rounds/${item_id}/round-[0-9]{3,}\.md$ ]]; then
    round_failure=1
    round_relative="$failure_relative"
  elif [[ "$failure_relative" =~ ^\.ai/gauntlets/${gauntlet_name}/pr-events/${item_id}/event-[0-9]{3,}\.md$ ]]; then
    qa_relative="$failure_relative"
    qa_file="$OPENCAW_PROJECT_ROOT_RESOLVED/$qa_relative"
  else
    return 1
  fi

  if [[ "$round_failure" -eq 1 ]]; then
    while IFS= read -r candidate; do
      [[ "$(gauntlet_section_field "$candidate" 'PR Event Metadata' 'Event')" == 'qa-fail' \
        && "$(gauntlet_section_field "$candidate" 'PR Event Metadata' 'Item')" == "$item_id" \
        && "$(gauntlet_section_field "$candidate" 'PR Event Metadata' 'Critic round')" == "$round_relative" ]] || continue
      candidate_pr="$(gauntlet_section_field "$candidate" 'PR Event Metadata' 'PR URL')"
      candidate_pr="${candidate_pr%/}"
      [[ "$candidate_pr" == "$closed_pr" ]] || continue
      qa_count=$((qa_count + 1))
      qa_file="$candidate"
      qa_relative="${candidate#"$OPENCAW_PROJECT_ROOT_RESOLVED"/}"
    done < <(find "$gauntlet_dir/pr-events/$item_id" -maxdepth 1 -type f -name 'event-*.md' -print | LC_ALL=C sort)
    [[ "$qa_count" -eq 1 ]] || return 1
  fi

  [[ "$qa_relative" =~ ^\.ai/gauntlets/${gauntlet_name}/pr-events/${item_id}/event-[0-9]{3,}\.md$ \
    && -f "$qa_file" && ! -L "$qa_file" \
    && "$(gauntlet_section_field "$qa_file" 'PR Event Metadata' 'Event')" == 'qa-fail' \
    && "$(gauntlet_section_field "$qa_file" 'PR Event Metadata' 'Item')" == "$item_id" ]] || return 1
  qa_pr="$(gauntlet_section_field "$qa_file" 'PR Event Metadata' 'PR URL')"
  qa_pr="${qa_pr%/}"
  [[ "$qa_pr" == "$closed_pr" ]] || return 1
  qa_round="$(gauntlet_section_field "$qa_file" 'PR Event Metadata' 'Critic round')"
  if [[ "$round_failure" -eq 1 ]]; then
    [[ "$qa_round" == "$round_relative" ]] || return 1
  else
    round_relative="$qa_round"
  fi

  [[ "$round_relative" =~ ^\.ai/gauntlets/${gauntlet_name}/rounds/${item_id}/round-[0-9]{3,}\.md$ ]] || return 1
  round_file="$OPENCAW_PROJECT_ROOT_RESOLVED/$round_relative"
  [[ -f "$round_file" && ! -L "$round_file" \
    && "$(gauntlet_section_field "$round_file" 'Round Metadata' 'Item')" == "$item_id" ]] || return 1
  round_pr="$(gauntlet_section_field "$round_file" 'Round Metadata' 'Progress PR')"
  round_pr="${round_pr%/}"
  round_verdict="$(gauntlet_section_field "$round_file" 'Round Metadata' 'Verdict')"
  round_opened="$(gauntlet_section_field "$round_file" 'Round Metadata' 'Opened event')"
  round_opened_hash="$(gauntlet_section_field "$round_file" 'Round Metadata' 'Opened event sha256')"
  [[ "$round_pr" == "$closed_pr" \
    && "$round_opened" == "$opened_relative" \
    && "$round_opened_hash" == "$(gauntlet_hash_file "$opened_file")" \
    && "$(gauntlet_section_field "$qa_file" 'PR Event Metadata' 'Critic verdict')" == "$round_verdict" ]] || return 1
  if [[ "$round_failure" -eq 1 ]]; then
    [[ "$round_verdict" == 'fail' || "$round_verdict" == 'blocked' ]] || return 1
  else
    case "$round_verdict" in pass|fail|blocked) ;; *) return 1 ;; esac
  fi

  gauntlet_progress_pr_event_precedes \
    "$gauntlet_file" "$opened_relative" "$qa_relative" || return 1
  gauntlet_progress_pr_event_precedes \
    "$gauntlet_file" "$qa_relative" "$closed_relative"
}

gauntlet_trace_remediation_trigger() {
  local gauntlet_file="$1"
  local item_id="$2"
  local opened_file="$3"
  local expected_failure="$4"
  local gauntlet_dir trigger trace_record trigger_file trigger_event trigger_item trigger_pr
  local prior_opened prior_opened_relative seen resolved_root

  gauntlet_dir="$(cd "$(dirname "$gauntlet_file")" && pwd -P)"
  seen='|'
  while :; do
    resolved_root="$(gauntlet_resolve_remediation_root \
      "$gauntlet_file" "$item_id" "$opened_file")" || return 1
    [[ "$resolved_root" != "$expected_failure" ]] || return 0
    trigger="$(gauntlet_section_field "$opened_file" 'PR Event Metadata' 'Remediation trigger')"
    trace_record="$resolved_root"
    [[ "$trace_record" =~ ^\.ai/gauntlets/[^/]+/pr-events/${item_id}/event-[0-9]{3,}\.md$ \
      && "$seen" != *"|$trace_record|"* ]] || {
      gauntlet_fail "Remediation trigger chain does not reach the latest applicable failure for $item_id: $trigger (resolved root: $trace_record)"
      return 1
    }
    seen+="$trace_record|"
    trigger_file="$OPENCAW_PROJECT_ROOT_RESOLVED/$trace_record"
    [[ -f "$trigger_file" && ! -L "$trigger_file" ]] || {
      gauntlet_fail "Remediation trigger chain references missing evidence: $trace_record"
      return 1
    }
    trigger_event="$(gauntlet_section_field "$trigger_file" 'PR Event Metadata' 'Event')"
    trigger_item="$(gauntlet_section_field "$trigger_file" 'PR Event Metadata' 'Item')"
    [[ "$trigger_event" == 'closed' && "$trigger_item" == "$item_id" ]] || {
      gauntlet_fail "Remediation trigger chain may traverse only same-unit closed events: $trace_record"
      return 1
    }
    if gauntlet_closed_cycle_contains_failure \
      "$gauntlet_file" "$item_id" "$trace_record" "$expected_failure"; then
      return 0
    fi
    trigger_pr="$(gauntlet_section_field "$trigger_file" 'PR Event Metadata' 'PR URL')"
    prior_opened="$(gauntlet_opened_event_for_pr \
      "$gauntlet_dir" "$item_id" "$trigger_pr")" || {
        gauntlet_fail "Closed remediation cycle does not resolve exactly one opened event: $trace_record"
        return 1
      }
    prior_opened_relative="${prior_opened#"$OPENCAW_PROJECT_ROOT_RESOLVED"/}"
    gauntlet_progress_pr_event_precedes \
      "$gauntlet_file" "$prior_opened_relative" "$trace_record" || {
      gauntlet_fail "Closed remediation cycle does not follow its opened event in the immutable PR ledger: $trace_record"
      return 1
    }
    opened_file="$prior_opened"
  done
}

gauntlet_failure_has_merged_remediation() {
  local gauntlet_file="$1"
  local item_id="$2"
  local failure_time="$3"
  local failure_relative="$4"
  local gauntlet_dir merged_file merge_relative merge_time latest_pr opened_file opened_relative opened_time
  local critic_round round_file round_time qa_file qa_relative qa_time candidate opened_root
  local failure_file failure_pr='none' failure_item='none' failure_heading failure_event same_pr_failure
  local failure_critic_round failure_precedes_round failure_precedes_opened

  gauntlet_dir="$(cd "$(dirname "$gauntlet_file")" && pwd -P)"
  failure_file="$OPENCAW_PROJECT_ROOT_RESOLVED/$failure_relative"
  if [[ "$failure_relative" == .ai/gauntlets/*/rounds/*/round-*.md ]]; then
    failure_heading='Round Metadata'
    failure_item="$(gauntlet_section_field "$failure_file" "$failure_heading" 'Item')"
    [[ "$failure_item" == 'integration' ]] || failure_pr="$(gauntlet_section_field "$failure_file" "$failure_heading" 'Progress PR')"
  elif [[ "$failure_relative" == .ai/gauntlets/*/pr-events/*/event-*.md ]]; then
    failure_heading='PR Event Metadata'
    failure_item="$(gauntlet_section_field "$failure_file" "$failure_heading" 'Item')"
    failure_event="$(gauntlet_section_field "$failure_file" "$failure_heading" 'Event')"
    [[ "$failure_event" == 'qa-fail' ]] && failure_pr="$(gauntlet_section_field "$failure_file" "$failure_heading" 'PR URL')"
  fi
  failure_pr="${failure_pr%/}"
  [[ -d "$gauntlet_dir/pr-events/$item_id" ]] || return 1
  while IFS= read -r merged_file; do
    [[ "$(gauntlet_section_field "$merged_file" 'PR Event Metadata' 'Event')" == 'merged' ]] || continue
    merge_relative="${merged_file#"$OPENCAW_PROJECT_ROOT_RESOLVED"/}"
    merge_time="$(gauntlet_section_field "$merged_file" 'PR Event Metadata' 'Recorded at')"
    latest_pr="$(gauntlet_section_field "$merged_file" 'PR Event Metadata' 'PR URL')"
    opened_file=''
    while IFS= read -r candidate; do
      if [[ "$(gauntlet_section_field "$candidate" 'PR Event Metadata' 'Event')" == 'opened' \
        && "$(gauntlet_section_field "$candidate" 'PR Event Metadata' 'PR URL')" == "$latest_pr" ]]; then
        opened_file="$candidate"
      fi
    done < <(find "$gauntlet_dir/pr-events/$item_id" -maxdepth 1 -type f -name 'event-*.md' -print | LC_ALL=C sort)
    [[ -n "$opened_file" ]] || continue
    opened_relative="${opened_file#"$OPENCAW_PROJECT_ROOT_RESOLVED"/}"
    same_pr_failure=0
    if [[ "$failure_pr" != 'none' && "$failure_item" == "$item_id" \
      && "${latest_pr%/}" == "$failure_pr" ]]; then
      same_pr_failure=1
    else
      if ! opened_root="$(gauntlet_resolve_remediation_root \
        "$gauntlet_file" "$item_id" "$opened_file" 2>/dev/null)"; then
        continue
      fi
      if [[ "$opened_root" != "$failure_relative" ]]; then
        gauntlet_trace_remediation_trigger "$gauntlet_file" "$item_id" "$opened_file" "$failure_relative" >/dev/null 2>&1 || continue
      fi
    fi
    opened_time="$(gauntlet_section_field "$opened_file" 'PR Event Metadata' 'Recorded at')"
    critic_round="$(gauntlet_section_field "$merged_file" 'PR Event Metadata' 'Critic round')"
    round_file="$OPENCAW_PROJECT_ROOT_RESOLVED/$critic_round"
    [[ -f "$round_file" && ! -L "$round_file" ]] || continue
    round_time="$(gauntlet_section_field "$round_file" 'Round Metadata' 'Recorded at')"
    qa_file=''
    while IFS= read -r candidate; do
      if [[ "$(gauntlet_section_field "$candidate" 'PR Event Metadata' 'Event')" == 'qa-pass' \
        && "$(gauntlet_section_field "$candidate" 'PR Event Metadata' 'PR URL')" == "$latest_pr" \
        && "$(gauntlet_section_field "$candidate" 'PR Event Metadata' 'Critic round')" == "$critic_round" ]]; then
        qa_file="$candidate"
      fi
    done < <(find "$gauntlet_dir/pr-events/$item_id" -maxdepth 1 -type f -name 'event-*.md' -print | LC_ALL=C sort)
    [[ -n "$qa_file" ]] || continue
    qa_relative="${qa_file#"$OPENCAW_PROJECT_ROOT_RESOLVED"/}"
    qa_time="$(gauntlet_section_field "$qa_file" 'PR Event Metadata' 'Recorded at')"

    [[ ( "$opened_time" < "$round_time" || "$opened_time" == "$round_time" ) \
      && ( "$round_time" < "$qa_time" || "$round_time" == "$qa_time" ) \
      && ( "$qa_time" < "$merge_time" || "$qa_time" == "$merge_time" ) ]] || continue
    gauntlet_progress_pr_event_precedes \
      "$gauntlet_file" "$opened_relative" "$qa_relative" || continue
    gauntlet_progress_pr_event_precedes \
      "$gauntlet_file" "$qa_relative" "$merge_relative" || continue

    if [[ "$same_pr_failure" -eq 1 ]]; then
      failure_precedes_round=0
      if [[ "$failure_time" < "$round_time" ]]; then
        failure_precedes_round=1
      elif [[ "$failure_time" == "$round_time" ]]; then
        if [[ "$failure_relative" == .ai/gauntlets/*/rounds/*/round-*.md ]]; then
          gauntlet_round_event_precedes \
            "$gauntlet_file" "$failure_relative" "$critic_round" \
            && failure_precedes_round=1
        elif [[ "$failure_relative" == .ai/gauntlets/*/pr-events/*/event-*.md ]]; then
          failure_critic_round="$(gauntlet_section_field "$failure_file" 'PR Event Metadata' 'Critic round')"
          if [[ "$failure_critic_round" == .ai/gauntlets/*/rounds/*/round-*.md ]] \
            && gauntlet_round_event_precedes \
              "$gauntlet_file" "$failure_critic_round" "$critic_round" \
            && gauntlet_progress_pr_event_precedes \
              "$gauntlet_file" "$failure_relative" "$qa_relative"; then
            failure_precedes_round=1
          fi
        fi
      fi
      if [[ "$failure_precedes_round" -eq 1 ]]; then
        return 0
      fi
    else
      failure_precedes_opened=0
      if [[ "$failure_time" < "$opened_time" ]]; then
        failure_precedes_opened=1
      elif [[ "$failure_time" == "$opened_time" ]]; then
        if [[ "$failure_relative" == .ai/gauntlets/*/pr-events/*/event-*.md ]]; then
          gauntlet_progress_pr_event_precedes \
            "$gauntlet_file" "$failure_relative" "$opened_relative" \
            && failure_precedes_opened=1
        else
          # The exact remediation-root/trigger chain checked above is the only
          # supported equal-second ordering edge across distinct ledgers.
          failure_precedes_opened=1
        fi
      fi
      [[ "$failure_precedes_opened" -eq 1 ]] && return 0
    fi
  done < <(find "$gauntlet_dir/pr-events/$item_id" -maxdepth 1 -type f -name 'event-*.md' -print | LC_ALL=C sort)
  return 1
}

gauntlet_assert_unit_remediation_causality() {
  local gauntlet_file="$1"
  local item_id="$2"
  local failure_time failure_relative

  while IFS=$'\t' read -r failure_time failure_relative; do
    [[ -n "$failure_relative" ]] || continue
    gauntlet_failure_has_merged_remediation \
      "$gauntlet_file" "$item_id" "$failure_time" "$failure_relative" || {
      gauntlet_fail "Applicable Gauntlet failure lacks a later causally linked merged remediation for $item_id: $failure_relative"
      return 1
    }
  done < <(gauntlet_applicable_failures "$gauntlet_file" "$item_id" | LC_ALL=C sort -k2,2)
}

gauntlet_latest_unresolved_failure() {
  local gauntlet_file="$1"
  local item_id="$2"
  local failure_time failure_relative latest='' latest_time=''

  while IFS=$'\t' read -r failure_time failure_relative; do
    [[ -n "$failure_relative" ]] || continue
    if ! gauntlet_failure_has_merged_remediation \
      "$gauntlet_file" "$item_id" "$failure_time" "$failure_relative"; then
      if [[ -z "$latest_time" || "$latest_time" < "$failure_time" ]]; then
        latest_time="$failure_time"
        latest="$failure_relative"
      elif [[ "$latest_time" == "$failure_time" ]]; then
        if gauntlet_equal_time_failure_precedes \
          "$gauntlet_file" "$latest" "$failure_relative"; then
          latest="$failure_relative"
        elif ! gauntlet_equal_time_failure_precedes \
          "$gauntlet_file" "$failure_relative" "$latest"; then
          gauntlet_fail "Cannot choose a latest unresolved failure without a durable same-second causal edge: $latest and $failure_relative"
          return 1
        fi
      fi
    fi
  done < <(gauntlet_applicable_failures "$gauntlet_file" "$item_id" | LC_ALL=C sort -k1,1 -k2,2)
  [[ -n "$latest" ]] || return 1
  printf '%s\n' "$latest"
}

gauntlet_progress_merge_chain_tip() {
  local gauntlet_file="$1"
  local gauntlet_dir base_sha rows consumed seen_tips event_file target_sha merge_sha relative total count match tip consumed_count

  gauntlet_dir="$(cd "$(dirname "$gauntlet_file")" && pwd -P)"
  base_sha="$(gauntlet_section_field "$gauntlet_file" 'Delivery' 'Base commit SHA')"
  base_sha="${base_sha,,}"
  gauntlet_validate_head_sha "$base_sha" 'Gauntlet base commit SHA' || return 1
  rows="$(mktemp "${TMPDIR:-/tmp}/opencaw-gauntlet-merge-chain.XXXXXX")"
  consumed="$(mktemp "${TMPDIR:-/tmp}/opencaw-gauntlet-merge-consumed.XXXXXX")"
  seen_tips="$(mktemp "${TMPDIR:-/tmp}/opencaw-gauntlet-merge-tips.XXXXXX")"
  : > "$rows"
  : > "$consumed"
  : > "$seen_tips"
  if [[ -d "$gauntlet_dir/pr-events" ]]; then
    while IFS= read -r event_file; do
      [[ "$(gauntlet_section_field "$event_file" 'PR Event Metadata' 'Event')" == 'merged' ]] || continue
      target_sha="$(gauntlet_section_field "$event_file" 'PR Event Metadata' 'Target base SHA' | tr '[:upper:]' '[:lower:]')"
      merge_sha="$(gauntlet_section_field "$event_file" 'PR Event Metadata' 'Merge commit' | tr '[:upper:]' '[:lower:]')"
      relative="${event_file#"$OPENCAW_PROJECT_ROOT_RESOLVED"/}"
      gauntlet_validate_head_sha "$target_sha" "Merged PR target base SHA ($relative)" || { rm -f "$rows" "$consumed" "$seen_tips"; return 1; }
      gauntlet_validate_head_sha "$merge_sha" "Merged PR merge commit ($relative)" || { rm -f "$rows" "$consumed" "$seen_tips"; return 1; }
      gauntlet_assert_commit_ancestor "$target_sha" "$merge_sha" "Merged PR segment ($relative)" || { rm -f "$rows" "$consumed" "$seen_tips"; return 1; }
      printf '%s\t%s\t%s\n' "$target_sha" "$merge_sha" "$relative" >> "$rows"
    done < <(find "$gauntlet_dir/pr-events" -type f -name 'event-*.md' -print | LC_ALL=C sort)
  fi
  total="$(wc -l < "$rows" | tr -d '[:space:]')"
  tip="$base_sha"
  consumed_count=0
  while :; do
    if grep -Fqx -- "$tip" "$seen_tips"; then
      rm -f "$rows" "$consumed" "$seen_tips"
      gauntlet_fail "Gauntlet merge chain contains a cycle at $tip"
      return 1
    fi
    printf '%s\n' "$tip" >> "$seen_tips"
    match="$(awk -F '\t' -v target="$tip" '$1 == target { print }' "$rows")"
    count="$(printf '%s\n' "$match" | sed '/^$/d' | wc -l | tr -d '[:space:]')"
    [[ "$count" -le 1 ]] || {
      rm -f "$rows" "$consumed" "$seen_tips"
      gauntlet_fail "Gauntlet merge chain branches from target base SHA: $tip"
      return 1
    }
    [[ "$count" -eq 1 ]] || break
    relative="$(printf '%s\n' "$match" | cut -f3)"
    if grep -Fqx -- "$relative" "$consumed"; then
      rm -f "$rows" "$consumed" "$seen_tips"
      gauntlet_fail "Gauntlet merge chain reuses an immutable merge event: $relative"
      return 1
    fi
    printf '%s\n' "$relative" >> "$consumed"
    tip="$(printf '%s\n' "$match" | cut -f2)"
    consumed_count=$((consumed_count + 1))
  done
  if [[ "$consumed_count" -ne "$total" ]]; then
    rm -f "$rows" "$consumed" "$seen_tips"
    gauntlet_fail 'Gauntlet merge evidence does not form one gapless, nonbranching chain from the frozen base commit.'
    return 1
  fi
  rm -f "$rows" "$consumed" "$seen_tips"
  printf '%s\n' "$tip"
}

gauntlet_remediation_trigger() {
  local gauntlet_file="$1"
  local item_id="$2"
  local previous_event_file="$3"
  local gauntlet_dir previous_event failure_time failure_relative revision_id

  gauntlet_dir="$(cd "$(dirname "$gauntlet_file")" && pwd -P)"
  if [[ "$(gauntlet_section_field "$gauntlet_file" 'Current State' 'Quality bar fingerprint')" == 'pending' ]]; then
    revision_id="$(gauntlet_latest_quality_revision_id "$gauntlet_file")"
    if [[ -n "$revision_id" ]]; then
      printf '%s\n' "quality-revision:$revision_id"
      return 0
    fi
  fi
  if [[ -z "$previous_event_file" ]]; then
    gauntlet_latest_unresolved_failure "$gauntlet_file" "$item_id"
    return
  fi
  previous_event="$(gauntlet_section_field "$previous_event_file" 'PR Event Metadata' 'Event')"
  if [[ "$previous_event" == 'closed' ]]; then
    printf '%s\n' "${previous_event_file#"$OPENCAW_PROJECT_ROOT_RESOLVED"/}"
    return 0
  fi
  [[ "$previous_event" == 'merged' ]] || return 1

  if failure_relative="$(gauntlet_latest_unresolved_failure "$gauntlet_file" "$item_id")"; then
    printf '%s\n' "$failure_relative"
    return 0
  fi

  return 1
}

gauntlet_load_latest_progress_pr() {
  local gauntlet_dir="$1"
  local item_id="$2"

  GAUNTLET_PROGRESS_EVENT_FILE="$(gauntlet_latest_pr_event_file "$gauntlet_dir/pr-events/$item_id")"
  GAUNTLET_PROGRESS_EVENT=''
  GAUNTLET_PROGRESS_PR_URL=''
  GAUNTLET_PROGRESS_HEAD_BRANCH=''
  GAUNTLET_PROGRESS_TARGET_BRANCH=''
  GAUNTLET_PROGRESS_HEAD_SHA=''
  GAUNTLET_PROGRESS_SCOPE_FINGERPRINT=''
  GAUNTLET_PROGRESS_UNIT_MANIFEST_FINGERPRINT=''
  GAUNTLET_PROGRESS_QUALITY_FINGERPRINT=''
  GAUNTLET_PROGRESS_EXECUTION_FINGERPRINT=''
  GAUNTLET_PROGRESS_CRITIC_ROUND='none'
  GAUNTLET_PROGRESS_CRITIC_VERDICT='none'
  GAUNTLET_PROGRESS_MERGE_COMMIT='none'
  [[ -n "$GAUNTLET_PROGRESS_EVENT_FILE" ]] || return 0

  GAUNTLET_PROGRESS_EVENT="$(gauntlet_section_field "$GAUNTLET_PROGRESS_EVENT_FILE" 'PR Event Metadata' 'Event')"
  GAUNTLET_PROGRESS_PR_URL="$(gauntlet_section_field "$GAUNTLET_PROGRESS_EVENT_FILE" 'PR Event Metadata' 'PR URL')"
  GAUNTLET_PROGRESS_PR_URL="${GAUNTLET_PROGRESS_PR_URL%/}"
  GAUNTLET_PROGRESS_HEAD_BRANCH="$(gauntlet_section_field "$GAUNTLET_PROGRESS_EVENT_FILE" 'PR Event Metadata' 'Head branch')"
  GAUNTLET_PROGRESS_TARGET_BRANCH="$(gauntlet_section_field "$GAUNTLET_PROGRESS_EVENT_FILE" 'PR Event Metadata' 'Target branch')"
  GAUNTLET_PROGRESS_HEAD_SHA="$(gauntlet_section_field "$GAUNTLET_PROGRESS_EVENT_FILE" 'PR Event Metadata' 'Head SHA')"
  GAUNTLET_PROGRESS_SCOPE_FINGERPRINT="$(gauntlet_section_field "$GAUNTLET_PROGRESS_EVENT_FILE" 'PR Event Metadata' 'Scope fingerprint')"
  GAUNTLET_PROGRESS_UNIT_MANIFEST_FINGERPRINT="$(gauntlet_section_field "$GAUNTLET_PROGRESS_EVENT_FILE" 'PR Event Metadata' 'Unit manifest fingerprint')"
  GAUNTLET_PROGRESS_QUALITY_FINGERPRINT="$(gauntlet_section_field "$GAUNTLET_PROGRESS_EVENT_FILE" 'PR Event Metadata' 'Quality bar fingerprint')"
  GAUNTLET_PROGRESS_EXECUTION_FINGERPRINT="$(gauntlet_section_field "$GAUNTLET_PROGRESS_EVENT_FILE" 'PR Event Metadata' 'Execution contract fingerprint')"
  GAUNTLET_PROGRESS_CRITIC_ROUND="$(gauntlet_section_field "$GAUNTLET_PROGRESS_EVENT_FILE" 'PR Event Metadata' 'Critic round')"
  GAUNTLET_PROGRESS_CRITIC_VERDICT="$(gauntlet_section_field "$GAUNTLET_PROGRESS_EVENT_FILE" 'PR Event Metadata' 'Critic verdict')"
  GAUNTLET_PROGRESS_MERGE_COMMIT="$(gauntlet_section_field "$GAUNTLET_PROGRESS_EVENT_FILE" 'PR Event Metadata' 'Merge commit')"
}

gauntlet_has_progress_pr_event() {
  local gauntlet_dir="$1"
  local item_id="$2"
  local expected_event="$3"
  local expected_pr="$4"
  local expected_round="$5"
  local expected_head_sha="$6"
  local expected_scope="$7"
  local event_file event_pr

  [[ -d "$gauntlet_dir/pr-events/$item_id" ]] || return 1
  while IFS= read -r event_file; do
    event_pr="$(gauntlet_section_field "$event_file" 'PR Event Metadata' 'PR URL')"
    event_pr="${event_pr%/}"
    if [[ "$(gauntlet_section_field "$event_file" 'PR Event Metadata' 'Event')" == "$expected_event" \
      && "$event_pr" == "${expected_pr%/}" \
      && "$(gauntlet_section_field "$event_file" 'PR Event Metadata' 'Critic round')" == "$expected_round" \
      && "${expected_head_sha,,}" == "$(gauntlet_section_field "$event_file" 'PR Event Metadata' 'Head SHA' | tr '[:upper:]' '[:lower:]')" \
      && "$expected_scope" == "$(gauntlet_section_field "$event_file" 'PR Event Metadata' 'Scope fingerprint')" ]]; then
      return 0
    fi
  done < <(find "$gauntlet_dir/pr-events/$item_id" -maxdepth 1 -type f -name 'event-*.md' -print | LC_ALL=C sort)
  return 1
}

gauntlet_round_has_retained_failure() {
  local gauntlet_file="$1"
  local round_file="$2"
  local gauntlet_dir relative_round item_id verdict event_file

  verdict="$(gauntlet_section_field "$round_file" 'Round Metadata' 'Verdict')"
  [[ "$verdict" == 'fail' || "$verdict" == 'blocked' ]] && return 0
  item_id="$(gauntlet_section_field "$round_file" 'Round Metadata' 'Item')"
  [[ "$item_id" != 'integration' ]] || return 1
  gauntlet_dir="$(cd "$(dirname "$gauntlet_file")" && pwd -P)"
  relative_round="${round_file#"$OPENCAW_PROJECT_ROOT_RESOLVED"/}"
  [[ -d "$gauntlet_dir/pr-events/$item_id" ]] || return 1
  while IFS= read -r event_file; do
    [[ "$(gauntlet_section_field "$event_file" 'PR Event Metadata' 'Event')" == 'qa-fail' \
      && "$(gauntlet_section_field "$event_file" 'PR Event Metadata' 'Critic round')" == "$relative_round" ]] && return 0
  done < <(find "$gauntlet_dir/pr-events/$item_id" -maxdepth 1 -type f -name 'event-*.md' -print | LC_ALL=C sort)
  return 1
}

gauntlet_assert_unit_progress_integrated() {
  local gauntlet_file="$1"
  local item_id="$2"
  local quality_fingerprint="$3"
  local integration_head_sha="$4"
  local gauntlet_dir latest_round latest_round_relative round_pr round_head round_head_sha round_scope current_scope integration_branch execution_fingerprint base_commit_sha chain_tip

  gauntlet_dir="$(cd "$(dirname "$gauntlet_file")" && pwd -P)"
  execution_fingerprint="$(gauntlet_assert_frozen_execution_contract "$gauntlet_file")" || return 1
  base_commit_sha="$(gauntlet_section_field "$gauntlet_file" 'Delivery' 'Base commit SHA' | tr '[:upper:]' '[:lower:]')"
  latest_round="$(gauntlet_latest_round_file "$gauntlet_dir/rounds/$item_id")"
  [[ -n "$latest_round" \
    && "$(gauntlet_section_field "$latest_round" 'Round Metadata' 'Verdict')" == 'pass' \
    && "$(gauntlet_section_field "$latest_round" 'Round Metadata' 'Quality bar fingerprint')" == "$quality_fingerprint" \
    && "$(gauntlet_section_field "$latest_round" 'Round Metadata' 'Execution contract fingerprint')" == "$execution_fingerprint" \
    && "$(gauntlet_section_field "$latest_round" 'Round Metadata' 'Base commit SHA' | tr '[:upper:]' '[:lower:]')" == "$base_commit_sha" ]] || {
    gauntlet_fail "Work unit lacks a latest passing critic round on the current quality bar: $item_id"
    return 1
  }

  gauntlet_load_latest_progress_pr "$gauntlet_dir" "$item_id"
  [[ -n "$GAUNTLET_PROGRESS_EVENT_FILE" && "$GAUNTLET_PROGRESS_EVENT" == 'merged' ]] || {
    gauntlet_fail "Work unit requires a latest human-merged progress PR: $item_id"
    return 1
  }
  latest_round_relative="${latest_round#"$OPENCAW_PROJECT_ROOT_RESOLVED"/}"
  round_pr="$(gauntlet_section_field "$latest_round" 'Round Metadata' 'Progress PR')"
  round_pr="${round_pr%/}"
  round_head="$(gauntlet_section_field "$latest_round" 'Round Metadata' 'Head branch')"
  round_head_sha="$(gauntlet_section_field "$latest_round" 'Round Metadata' 'Head SHA')"
  round_scope="$(gauntlet_section_field "$latest_round" 'Round Metadata' 'Scope fingerprint')"
  current_scope="$(gauntlet_unit_scope_fingerprint "$gauntlet_file" "$item_id")" || return 1
  integration_branch="$(gauntlet_section_field "$gauntlet_file" 'Delivery' 'Integration branch')"
  [[ "$GAUNTLET_PROGRESS_CRITIC_ROUND" == "$latest_round_relative" \
    && "$GAUNTLET_PROGRESS_CRITIC_VERDICT" == 'pass' \
    && "$GAUNTLET_PROGRESS_PR_URL" == "$round_pr" \
    && "$GAUNTLET_PROGRESS_HEAD_BRANCH" == "$round_head" \
    && "${GAUNTLET_PROGRESS_HEAD_SHA,,}" == "${round_head_sha,,}" \
    && "$GAUNTLET_PROGRESS_SCOPE_FINGERPRINT" == "$round_scope" \
    && "$round_scope" == "$current_scope" \
    && "$GAUNTLET_PROGRESS_QUALITY_FINGERPRINT" == "$quality_fingerprint" \
    && "$GAUNTLET_PROGRESS_EXECUTION_FINGERPRINT" == "$execution_fingerprint" \
    && "$GAUNTLET_PROGRESS_TARGET_BRANCH" == "$integration_branch" \
    && "$GAUNTLET_PROGRESS_MERGE_COMMIT" =~ ^[0-9a-fA-F]{40}([0-9a-fA-F]{24})?$ ]] || {
    gauntlet_fail "Work unit's latest progress PR is not QA-passed and human-merged for its latest critic round: $item_id"
    return 1
  }
  gauntlet_assert_local_branch_at_sha \
    "$integration_branch" \
    "$integration_head_sha" \
    'Gauntlet integration branch' || return 1
  chain_tip="$(gauntlet_progress_merge_chain_tip "$gauntlet_file")" || return 1
  [[ "$chain_tip" == "${integration_head_sha,,}" ]] || {
    gauntlet_fail "Integration head contains unrecorded changes outside the continuous progress-PR merge chain: $integration_head_sha"
    return 1
  }
  gauntlet_assert_commit_ancestor \
    "$GAUNTLET_PROGRESS_MERGE_COMMIT" \
    "$integration_head_sha" \
    "Work-unit merge commit for $item_id in the integration branch" || return 1
  gauntlet_assert_unit_remediation_causality "$gauntlet_file" "$item_id" || return 1
}
