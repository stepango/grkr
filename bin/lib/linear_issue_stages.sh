# bin/lib/linear_issue_stages.sh
# Slice 1: ensure_linear_test_checkpoint extracted from linear_issue.sh (first vertical
# Linear-only stage body per docs/design-linear-issue-thinning.md §9).
# Slice 2: ensure_linear_publish_complete (publish + complete) extracted from
# linear_issue.sh (second vertical per design §8/§10). PR from linear-* + mark complete
# + complete comment planned FIRST then Done state (no GitHub labels, no gh issue edits).
#
# Ambient deps resolved at call time from sourcing context (bin/grkr or direct test
# sourcing of linear_issue.sh after its prerequisites):
#
# For Slice 1 (test checkpoint):
#   build_command_list, run_test_stage_hook, write_test_checkpoint_with_header,
#   run_progress_cli, checkpoint_marker (via progress), cleanup_test_result_logs,
#   mark_task_progress_failed, update_task_progress_stage, maybe_apply_linear_mutation
#   (from linear_mutate.sh, which must be sourced first), CURRENT_ISSUE_WORKTREE,
#   LINEAR_STATE_TEST_ID, etc.
#
# For Slice 2 (publish+complete):
#   ensure_publishable_file_sizes, stage_relevant_issue_files, git_in_issue_context,
#   check_file_line_limit, generate_linear_implement_commit_message,
#   extract_linear_codex_pr_body, mark_task_progress_complete, run_progress_cli,
#   maybe_apply_linear_mutation (from linear_mutate.sh sourced first).
#   Globals used: CURRENT_ISSUE_WORKTREE, REPO, MAIN_BRANCH, LINEAR_STATE_DONE_ID,
#   BRANCH_URL, PR_URL (set inside fn).
#
# Mirrors github_issue.sh vertical extract pattern for Linear:
#   - github_issue.sh owns GitHub-specific ensure_* / publish_* bodies.
#   - linear_issue.sh stays thin sequencer + load/meta + remaining ensure_*.
#   - stages sibling owns extracted Linear stage bodies (Slice 1 test; Slice 2 publish+complete).
#   - process_linear_issue call sites unchanged; external --linear-issue contract identical.
#   - Shared helpers (ensure_publishable_file_sizes, stage_*, git_in_*, marks, run_progress_cli,
#     maybe_apply, etc.) stay shared / provider-agnostic.
#
# Future slices (per design): extract refusal_checkpoint, research/plan, etc. into
# this sibling to keep linear_issue.sh well under 1000 LOC.
#
# No behavior change. GitHub untouched. GRKR_ISSUE_PROVIDER default unchanged.
# linear_mutate.sh must be sourced before this file so maybe_apply_linear_mutation exists.

# Wire Linear test stage after successful implement (spec/26 parity).
# Reuses shared build_command_list, run_test_stage_hook, cleanup_test_result_logs,
# write_test_checkpoint_with_header (Linear header), checkpoint_marker, run_progress_cli.
# Executes BUILD/TEST (or npm test) inside CURRENT_ISSUE_WORKTREE.
# Writes test.md (marker + "Linear issue ID: title" + sections).
# Plans test.linear-mutation.txt (comment) + test.linear-state-mutation.txt ("In Review").
# Updates stages.test done|failed; leaves worktree on success; no gh, no publish, no complete.
# Resume: local test.md + progress done (no remote lookup).
# GRKR_LINEAR_MUTATE=1 applies after dumps (soft).
ensure_linear_test_checkpoint() {
  local identifier=$1
  local mutation_issue_id=$2
  local task_slug=$3
  local task_dir=$4
  local title=$5
  local progress_file=$6
  local checkpoint_file
  local command_list_file
  local results_file
  local command
  local log_file
  local status
  local recommendation="ready"
  local overall_result="PASS"
  local total_commands=0
  local passed_commands=0
  local failed_commands=0
  local worktree_shell_path
  local body
  local mutation_out
  local idempotency_key
  local target_state
  local state_mutation_file

  if [ -z "$identifier" ] || [ -z "$task_slug" ] || [ -z "$progress_file" ]; then
    echo "❌ ensure_linear_test_checkpoint requires identifier, task_slug, progress_file" >&2
    return 1
  fi

  checkpoint_file="$task_dir/test.md"

  if [ -f "$checkpoint_file" ]; then
    if jq -e '.stages.test.status == "done"' "$progress_file" >/dev/null 2>&1; then
      echo "♻️ Reusing local test checkpoint for Linear $identifier."
      return 0
    fi
  fi

  # Thin hook (provider-agnostic; heavy exec stays in shell).
  run_test_stage_hook

  command_list_file=$(mktemp "${TMPDIR:-/tmp}/grkr-test-commands.XXXXXX")
  results_file=$(mktemp "${TMPDIR:-/tmp}/grkr-test-results.XXXXXX")
  build_command_list > "$command_list_file"

  while IFS= read -r command; do
    [ -n "$command" ] || continue
    total_commands=$((total_commands + 1))
    log_file=$(mktemp "${TMPDIR:-/tmp}/grkr-test-output.XXXXXX")
    echo "🧪 Running verification command for Linear $identifier: $command"
    if [ -n "${CURRENT_ISSUE_WORKTREE:-}" ]; then
      worktree_shell_path=$(printf '%q' "$CURRENT_ISSUE_WORKTREE")
      if bash -lc "cd $worktree_shell_path && $command" > "$log_file" 2>&1; then
        status="PASS"
        passed_commands=$((passed_commands + 1))
      else
        status="FAIL"
        failed_commands=$((failed_commands + 1))
        overall_result="FAIL"
        recommendation="needs follow-up"
      fi
    elif bash -lc "$command" > "$log_file" 2>&1; then
      status="PASS"
      passed_commands=$((passed_commands + 1))
    else
      status="FAIL"
      failed_commands=$((failed_commands + 1))
      overall_result="FAIL"
      recommendation="needs follow-up"
    fi
    printf '%s\t%s\t%s\n' "$status" "$command" "$log_file" >> "$results_file"
  done < "$command_list_file"

  # Write using shared writer with Linear header (no # on identifier).
  local header_line
  header_line=$(printf 'Linear issue %s: %s' "$identifier" "$title")
  write_test_checkpoint_with_header \
    "$checkpoint_file" \
    "$header_line" \
    "$task_slug" \
    "$command_list_file" \
    "$results_file" \
    "$recommendation" \
    "$overall_result" \
    "$total_commands" \
    "$passed_commands" \
    "$failed_commands"

  # Plan Linear comment mutation (dry-run).
  echo "📝 Planning Linear test checkpoint mutation for $identifier..."
  body=$(cat "$checkpoint_file")
  mutation_out=$(run_progress_cli linear-comment-mutation \
    "$mutation_issue_id" \
    "$body" \
    test \
    "$task_slug" 2>/dev/null) || mutation_out=""

  if [ -n "$mutation_out" ]; then
    idempotency_key=$(printf '%s\n' "$mutation_out" | tail -n1)
    printf '%s\n' "$mutation_out" > "$task_dir/test.linear-mutation.txt"
    maybe_apply_linear_mutation "$task_dir/test.linear-mutation.txt"
    echo "🔑 test mutation idempotency_key=${idempotency_key} (set GRKR_LINEAR_MUTATE=1 to apply)"
  else
    echo "⚠️ progress CLI linear-comment-mutation planning failed for test; local checkpoint kept."
  fi

  # Plan Linear state mutation to test_state (default "In Review").
  target_state=$(run_progress_cli linear-state test 2>/dev/null || echo "In Review")
  state_mutation_file="$task_dir/test.linear-state-mutation.txt"

  echo "📝 Planning Linear test state mutation for $identifier (target=$target_state)..."
  if [ -n "${LINEAR_STATE_TEST_ID:-}" ]; then
    local state_mut
    state_mut=$(run_progress_cli linear-state-mutation "$mutation_issue_id" "${LINEAR_STATE_TEST_ID}" test 2>/dev/null) || state_mut=""
    if [ -n "$state_mut" ]; then
      printf '%s\n' "$state_mut" > "$state_mutation_file"
      maybe_apply_linear_mutation "$state_mutation_file"
      echo "🔑 test state mutation idempotency_key=$(printf '%s\n' "$state_mut" | tail -n1)"
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
    echo "🔑 test state target=$target_state (no LINEAR_STATE_TEST_ID; set GRKR_LINEAR_MUTATE=1 when live apply lands)"
  fi

  if [ "$failed_commands" -gt 0 ]; then
    update_task_progress_stage "$progress_file" test "failed" "${idempotency_key:-}"
    cleanup_test_result_logs "$results_file"
    rm -f "$command_list_file" "$results_file"
    mark_task_progress_failed "$progress_file" test
    CURRENT_ISSUE_WORKTREE=""
    return 1
  fi

  update_task_progress_stage "$progress_file" test "done" "${idempotency_key:-}"
  cleanup_test_result_logs "$results_file"
  rm -f "$command_list_file" "$results_file"

  echo "✅ Linear test stage complete for $identifier (commands executed in worktree; test.md + dry-run mutations written)."
  return 0
}

# ensure_linear_publish_complete wires the publish + complete dry-run for Linear after test success.
# Reuses shared: ensure_publishable_file_sizes (with remediation), stage_relevant, git_in_*, check_file_line_limit,
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
