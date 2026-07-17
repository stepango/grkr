# bin/lib/linear_issue_stages.sh
# Slice 1: ensure_linear_test_checkpoint extracted from linear_issue.sh (first vertical
# Linear-only stage body per docs/design-linear-issue-thinning.md §9).
#
# Ambient deps resolved at call time from sourcing context (bin/grkr or direct test
# sourcing of linear_issue.sh after its prerequisites):
#   build_command_list, run_test_stage_hook, write_test_checkpoint_with_header,
#   run_progress_cli, checkpoint_marker (via progress), cleanup_test_result_logs,
#   mark_task_progress_failed, update_task_progress_stage, maybe_apply_linear_mutation
#   (from linear_mutate.sh, which must be sourced first), CURRENT_ISSUE_WORKTREE,
#   LINEAR_STATE_TEST_ID, etc.
#
# Mirrors github_issue.sh vertical extract pattern for Linear:
#   - github_issue.sh owns GitHub-specific ensure_* / publish_* bodies.
#   - linear_issue.sh stays thin sequencer + load/meta + remaining ensure_*.
#   - stages sibling owns extracted Linear stage bodies (start with test checkpoint).
#   - process_linear_issue call sites unchanged; external --linear-issue contract identical.
#   - Shared helpers (write_test_checkpoint_with_header, build_*, run_*_hook, task_progress
#     marks, run_progress_cli, maybe_apply) stay shared / provider-agnostic.
#
# Future slices (per design): extract publish_complete, refusal_checkpoint, etc. into
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
