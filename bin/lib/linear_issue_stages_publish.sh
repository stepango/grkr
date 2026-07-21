# bin/lib/linear_issue_stages_publish.sh
# Stages-split slice 3 (docs/design-linear-issue-stages-split.md §4–§5 / §8 / §10):
# ensure_linear_publish_complete extracted from linear_issue_stages.sh into this
# sibling module. linear_issue_stages.sh is the facade that sources this file.
# linear_issue.sh still sources only the stages facade after linear_mutate.sh.
#
# Ambient deps resolved at call time (from bin/grkr or tests sourcing linear_issue.sh):
#   ensure_publishable_file_sizes, check_file_line_limit (issue_shared.sh),
#   stage_relevant_issue_files, git_in_issue_context,
#   generate_linear_implement_commit_message, extract_linear_codex_pr_body,
#   mark_task_progress_complete, run_progress_cli,
#   maybe_apply_linear_mutation (from linear_mutate.sh, which must be sourced first).
#   Globals: CURRENT_ISSUE_WORKTREE, REPO, MAIN_BRANCH, LINEAR_STATE_DONE_ID,
#   BRANCH_URL, PR_URL (set inside fn).
# No GitHub label edits / gh issue comment on Linear path. GRKR_LINEAR_MUTATE default OFF.
# Zero behavior change. Stable function name ensure_linear_publish_complete.

# ensure_linear_publish_complete wires the publish + complete dry-run for Linear after test success.
# Reuses shared (issue_shared.sh): ensure_publishable_file_sizes (with remediation), check_file_line_limit,
#   stage_relevant, git_in_*, 
# generate_linear_implement_commit_message, extract_linear_codex_pr_body (no Fixes footer),
# mark_task_progress_complete, run_progress_cli (for pr_summary/Done + comment).
# GitHub label edits and gh issue comment are NEVER performed on Linear path.
# On no-changes: still mark complete + plan Linear Done/comment (BRANCH/PR urls may be empty).
# On publish hard failure: return 1 without mark or complete.*.txt dumps.
ensure_linear_publish_complete() {
  local identifier=$1
  local mutation_issue_id=$2
  local task_slug=$3
  local task_dir=$4
  local title=$5
  local issue_url=$6
  local body=$7
  local codex_output_file=$8
  local branch=$9
  local progress_file=${10:-}
  local prompt_file=${11:-}

  if [ -z "$identifier" ] || [ -z "$task_slug" ] || [ -z "$progress_file" ]; then
    echo "❌ ensure_linear_publish_complete requires identifier, task_slug, progress_file" >&2
    return 1
  fi

  # 1. Ensure sizes (may run remediation codex using prompt + codex_output; stages relevant internally)
  ensure_publishable_file_sizes "$identifier" "$title" "$task_slug" "$prompt_file" "$codex_output_file" || return 1

  # 2. Publish (mirror structure of publish_issue_changes but Linear-specific; no labels)
  echo "🔄 Auto-committing, pushing and creating PR..."
  stage_relevant_issue_files
  if git_in_issue_context diff --cached --quiet; then
    echo "No changes for $identifier"
    # fall through: still mark + plan Linear complete (urls may remain unset)
  else
    if ! check_file_line_limit; then
      echo "❌ Commit aborted due to file size limit."
      return 1
    fi

    local commit_msg
    commit_msg=$(generate_linear_implement_commit_message "$identifier" "$title")
    git_in_issue_context commit -m "$commit_msg" || {
      echo "❌ git commit failed for $identifier"
      return 1
    }
    git_in_issue_context push -u origin "$branch" || {
      echo "❌ git push failed for $identifier"
      return 1
    }
    BRANCH_URL="https://github.com/$REPO/tree/$branch"

    local PR_BODY_FILE
    PR_BODY_FILE=$(mktemp "${TMPDIR:-/tmp}/grkr-pr-body.XXXXXX")
    extract_linear_codex_pr_body "$codex_output_file" "$PR_BODY_FILE" "$body" "$title" "$identifier" "$issue_url"

    local pr_list_json
    local pr_number
    local pr_create_output
    pr_list_json=$(gh pr list --head "$branch" --json number,url 2>/dev/null || true)
    pr_number=$(printf '%s' "$pr_list_json" | jq -r '.[0].number // empty')
    if [ -n "$pr_number" ]; then
      gh pr edit "$pr_number" --title "$title" --body-file "$PR_BODY_FILE" >/dev/null
      PR_URL=$(printf '%s' "$pr_list_json" | jq -r '.[0].url // empty')
      echo "✅ PR updated: $PR_URL"
    else
      pr_create_output=$(gh pr create --base "${MAIN_BRANCH:-main}" --head "$branch" --title "$title" --body-file "$PR_BODY_FILE" 2>&1) || {
        echo "$pr_create_output"
        rm -f "$PR_BODY_FILE"
        return 1
      }
      PR_URL=$(printf '%s\n' "$pr_create_output" | awk '/^https?:\/\// {url=$0} END {print url}')
      if [ -z "$PR_URL" ]; then
        echo "$pr_create_output"
        rm -f "$PR_BODY_FILE"
        return 1
      fi
      echo "✅ PR created: $PR_URL"
    fi
    rm -f "$PR_BODY_FILE"
  fi

  # 3. Mark progress complete (provider-agnostic; records urls even if partial/empty)
  mark_task_progress_complete "$progress_file" "${BRANCH_URL:-}" "${PR_URL:-}"

  # 4. Plan completion comment FIRST (per design: comment before Done state), then apply.
  local mutation_out
  local comment_body
  comment_body=$(cat <<'CMT'
## Completion summary

Linear issue __IDENT__: __TITLE__

- Recommendation: ready
- Branch: __BRANCH__
- PR: __PR__
CMT
)
  # substitute safely
  comment_body=${comment_body//__IDENT__/$identifier}
  comment_body=${comment_body//__TITLE__/$title}
  comment_body=${comment_body//__BRANCH__/${BRANCH_URL:-}}
  comment_body=${comment_body//__PR__/${PR_URL:-}}

  echo "📝 Planning Linear completion comment for $identifier..."
  mutation_out=$(run_progress_cli linear-comment-mutation \
    "$mutation_issue_id" \
    "$comment_body" \
    pr_summary \
    "$task_slug" 2>/dev/null) || mutation_out=""

  local complete_mutation_file="$task_dir/complete.linear-mutation.txt"
  if [ -n "$mutation_out" ]; then
    local idempotency_key
    idempotency_key=$(printf '%s\n' "$mutation_out" | tail -n1)
    printf '%s\n' "$mutation_out" > "$complete_mutation_file"
    maybe_apply_linear_mutation "$complete_mutation_file"
    echo "🔑 complete comment idempotency_key=${idempotency_key}"
  else
    echo "⚠️ progress CLI linear-comment-mutation planning failed for complete; local summary kept."
    # write a fallback local body for test visibility
    printf '%s\n' "$comment_body" > "$complete_mutation_file"
    maybe_apply_linear_mutation "$complete_mutation_file"
  fi

  # 5. Plan Linear Done state mutation AFTER comment (design order).
  local target_state
  target_state=$(run_progress_cli linear-state pr_summary 2>/dev/null || echo "Done")
  local state_mutation_file="$task_dir/complete.linear-state-mutation.txt"

  echo "📝 Planning Linear complete / Done state mutation for $identifier (target=$target_state)..."
  if [ -n "${LINEAR_STATE_DONE_ID:-}" ]; then
    local state_mut
    state_mut=$(run_progress_cli linear-state-mutation "$mutation_issue_id" "${LINEAR_STATE_DONE_ID}" complete 2>/dev/null) || state_mut=""
    if [ -n "$state_mut" ]; then
      printf '%s\n' "$state_mut" > "$state_mutation_file"
      maybe_apply_linear_mutation "$state_mutation_file"
      echo "🔑 complete state mutation idempotency_key=$(printf '%s\n' "$state_mut" | tail -n1)"
    else
      {
        printf 'TARGET_STATE=%s\n' "$target_state"
        printf 'STATE_MUTATION_PLANNED=0\n'
      } > "$state_mutation_file"
      maybe_apply_linear_mutation "$state_mutation_file"
    fi
  else
    {
      printf 'TARGET_STATE=%s\n' "$target_state"
      printf 'STATE_MUTATION_PLANNED=0\n'
    } > "$state_mutation_file"
    maybe_apply_linear_mutation "$state_mutation_file"
    echo "🔑 complete state target=$target_state (no LINEAR_STATE_DONE_ID; set GRKR_LINEAR_MUTATE=1 when live apply lands)"
  fi

  echo "✅ Linear publish + complete planned for $identifier"
  return 0
}
