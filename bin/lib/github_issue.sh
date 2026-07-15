# bin/lib/github_issue.sh
# GitHub-only orchestration extracted from process_issue in bin/grkr.
# First slice: test checkpoint (ensure_test_checkpoint + write_test_checkpoint_file).
# Purpose: GitHub-specific test checkpoint runner/writer (gh comment, "Issue #N: title" header,
# resume from gh comments, worktree exec of verification commands, progress stages.test).
# Later slices will extract publish, research/plan checkpoints, completion to same lib.
# Mirrors bin/lib/linear_issue.sh thin-delegate pattern.
# Functions assume ambient helpers (build_command_list, cleanup_test_result_logs,
# write_test_checkpoint_with_header, run_test_stage_hook, fetch_issue_comments_json,
# checkpoint_comment_*_from_json, update_task_progress_stage, mark_task_progress_failed,
# etc.) are already defined in the sourcing shell (bin/grkr defines/sources them before/around
# dispatch to process_issue; bash resolves names at call time). Do not duplicate shared logic.
# GitHub remains default GRKR_ISSUE_PROVIDER. No changes to Linear paths or linear_issue.sh.

write_test_checkpoint_file() {
  local checkpoint_file=$1
  local issue=$2
  local title=$3
  local task_slug=$4
  local commands_file=$5
  local results_file=$6
  local recommendation=$7
  local overall_result=$8
  local total_commands=$9
  local passed_commands=${10}
  local failed_commands=${11}
  local header_line

  header_line=$(printf 'Issue #%s: %s' "$issue" "$title")
  write_test_checkpoint_with_header \
    "$checkpoint_file" \
    "$header_line" \
    "$task_slug" \
    "$commands_file" \
    "$results_file" \
    "$recommendation" \
    "$overall_result" \
    "$total_commands" \
    "$passed_commands" \
    "$failed_commands"
}

ensure_test_checkpoint() {
  local issue=$1
  local issue_json=$2
  local task_slug=$3
  local task_dir=$4
  local title=$5
  local progress_file=$6
  local checkpoint_file
  local comment_id
  local comment_body
  local refreshed_comments_json
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

  checkpoint_file="$task_dir/test.md"
  comment_id=$(checkpoint_comment_id_from_json "$issue_json" test "$task_slug")

  if [ -f "$checkpoint_file" ] && [ -n "$comment_id" ]; then
    echo "♻️ Reusing test checkpoint for issue #$issue from comment $comment_id."
    update_task_progress_stage "$progress_file" test "done" "$comment_id"
    return 0
  fi

  if [ -n "$comment_id" ] && [ ! -f "$checkpoint_file" ]; then
    comment_body=$(checkpoint_comment_body_from_json "$issue_json" test "$task_slug")
    if [ -n "$comment_body" ]; then
      printf '%s\n' "$comment_body" > "$checkpoint_file"
      echo "♻️ Restored test checkpoint for issue #$issue from comment $comment_id."
      update_task_progress_stage "$progress_file" test "done" "$comment_id"
      return 0
    fi
  fi

  # Wire test stage hook (Gleam) per spec/26 + t_d87d2215 / #18 spec item 9.
  # Thin hook only (pure message); heavy verification + test.md + gh post stay in this shell per slice pattern.
  # Mirrors generate_implement_commit_message wiring for implement stage.
  run_test_stage_hook

  command_list_file=$(mktemp "${TMPDIR:-/tmp}/grkr-test-commands.XXXXXX")
  results_file=$(mktemp "${TMPDIR:-/tmp}/grkr-test-results.XXXXXX")
  build_command_list > "$command_list_file"

  while IFS= read -r command; do
    [ -n "$command" ] || continue
    total_commands=$((total_commands + 1))
    log_file=$(mktemp "${TMPDIR:-/tmp}/grkr-test-output.XXXXXX")
    echo "🧪 Running verification command for issue #$issue: $command"
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

  write_test_checkpoint_file \
    "$checkpoint_file" \
    "$issue" \
    "$title" \
    "$task_slug" \
    "$command_list_file" \
    "$results_file" \
    "$recommendation" \
    "$overall_result" \
    "$total_commands" \
    "$passed_commands" \
    "$failed_commands"

  echo "📝 Posting test checkpoint for issue #$issue..."
  gh issue comment "$issue" --body-file "$checkpoint_file" >/dev/null
  refreshed_comments_json=$(fetch_issue_comments_json "$issue")
  comment_id=$(checkpoint_comment_id_from_json "$refreshed_comments_json" test "$task_slug")

  if [ "$failed_commands" -gt 0 ]; then
    update_task_progress_stage "$progress_file" test "failed" "$comment_id"
    cleanup_test_result_logs "$results_file"
    rm -f "$command_list_file" "$results_file"
    mark_task_progress_failed "$progress_file" test
    return 1
  fi

  update_task_progress_stage "$progress_file" test "done" "$comment_id"
  cleanup_test_result_logs "$results_file"
  rm -f "$command_list_file" "$results_file"
}
