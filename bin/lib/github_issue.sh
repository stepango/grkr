# bin/lib/github_issue.sh
# GitHub-only orchestration extracted from process_issue in bin/grkr.
# Slice 1 (landed PR #112): test checkpoint (ensure_test_checkpoint + write_test_checkpoint_file).
# Slice 3 (landed PR #115): publish helpers (publish_issue_changes + extract_codex_pr_body + ensure_pr_body_limit).
# Slice 4: research/plan ensure_checkpoint_stage + gh comment helpers (fetch_issue_comments_json, checkpoint_comment_id_from_json, checkpoint_comment_body_from_json).
# Purpose: GitHub-specific publish (stage/commit via Gleam hook/push, PR create-or-edit,
# "Fixes #N" footer via append, label "implemented"/remove "todo", PR body from codex log or default).
# Mirrors bin/lib/linear_issue.sh thin-delegate pattern (Linear uses its own extract_linear_* / ensure_linear_*).
# Functions assume ambient helpers (stage_relevant_issue_files, git_in_issue_context,
# check_file_line_limit, generate_implement_commit_message, emit_task_log_stream,
# task_log_is_sharded, write_default_pr_body, write_compact_pr_body, append_issue_footer,
# REPO, MAIN_BRANCH, MAX_PR_BODY_CHARS, BRANCH_URL, PR_URL globals, etc.) are already defined
# in the sourcing shell (bin/grkr defines/sources them; bash resolves at call time).
# Shared helpers (e.g. ensure_publishable_file_sizes) stay in bin/grkr.
# GitHub remains default GRKR_ISSUE_PROVIDER. No changes to Linear paths or linear_issue.sh.

# GitHub comment helpers for checkpoint reuse/restore/post (research/plan/test).
# These are gh-specific (not used by Linear path). Moved here for thinning.
# Resolved at call time from sourcing context (checkpoint_marker, update_task_progress_stage ambient).
fetch_issue_comments_json() {
  local issue=$1
  local comments_json

  comments_json=$(gh issue view "$issue" --comments --json comments 2>/dev/null || true)
  [ -n "$comments_json" ] || comments_json='{"comments":[]}'
  printf '%s\n' "$comments_json"
}

checkpoint_comment_id_from_json() {
  local issue_json=$1
  local stage=$2
  local task_slug=$3
  local marker

  marker=$(checkpoint_marker "$stage" "$task_slug")
  printf '%s' "$issue_json" | jq -r --arg marker "$marker" '
    ((.comments // []) | if type == "array" then . else [] end
      | map(select((.body // "") | contains($marker)))
      | last
      | .id) // empty
  '
}

checkpoint_comment_body_from_json() {
  local issue_json=$1
  local stage=$2
  local task_slug=$3
  local marker

  marker=$(checkpoint_marker "$stage" "$task_slug")
  printf '%s' "$issue_json" | jq -r --arg marker "$marker" '
    ((.comments // []) | if type == "array" then . else [] end
      | map(select((.body // "") | contains($marker)))
      | last
      | .body) // empty
  '
}

ensure_checkpoint_stage() {
  local stage=$1
  local issue=$2
  local issue_json=$3
  local task_slug=$4
  local task_dir=$5
  local title=$6
  local body=$7
  local url=$8
  local progress_file=$9
  local checkpoint_file
  local comment_id
  local comment_body
  local refreshed_comments_json

  checkpoint_file="$task_dir/$stage.md"
  comment_id=$(checkpoint_comment_id_from_json "$issue_json" "$stage" "$task_slug")

  if [ -f "$checkpoint_file" ] && [ -n "$comment_id" ]; then
    echo "♻️ Reusing $stage checkpoint for issue #$issue from comment $comment_id."
    update_task_progress_stage "$progress_file" "$stage" "done" "$comment_id"
    return 0
  fi

  if [ -n "$comment_id" ] && [ ! -f "$checkpoint_file" ]; then
    comment_body=$(checkpoint_comment_body_from_json "$issue_json" "$stage" "$task_slug")
    if [ -n "$comment_body" ]; then
      printf '%s\n' "$comment_body" > "$checkpoint_file"
      echo "♻️ Restored $stage checkpoint for issue #$issue from comment $comment_id."
      update_task_progress_stage "$progress_file" "$stage" "done" "$comment_id"
      return 0
    fi
  fi

  case "$stage" in
    research)
      write_research_checkpoint_file "$checkpoint_file" "$issue" "$title" "$body" "$url" "$task_slug"
      ;;
    plan)
      write_plan_checkpoint_file "$checkpoint_file" "$issue" "$title" "$task_slug"
      ;;
    *)
      echo "❌ Unsupported checkpoint stage: $stage"
      return 1
      ;;
  esac

  echo "📝 Posting $stage checkpoint for issue #$issue..."
  gh issue comment "$issue" --body-file "$checkpoint_file" >/dev/null
  refreshed_comments_json=$(fetch_issue_comments_json "$issue")
  comment_id=$(checkpoint_comment_id_from_json "$refreshed_comments_json" "$stage" "$task_slug")
  update_task_progress_stage "$progress_file" "$stage" "done" "$comment_id"
}

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

# GitHub publish helpers (slice 3). Exact bodies moved from bin/grkr for thinning.
# publish_issue_changes kept (call site in process_issue uses it for zero churn).
# publish_github_issue_changes alias provided for design naming parity with linear_*.
# External contract: stage, line-limit guard, Gleam commit msg, push, PR create/edit,
# Fixes #N footer (via append_issue_footer on default/compact body), labels, exit codes.
# Reuses shared (from grkr context): stage_relevant_issue_files, git_in_issue_context,
# check_file_line_limit, generate_implement_commit_message, task log emit helpers,
# PR body writers from grkr-templates.sh, gh CLI.
publish_issue_changes() {
  local ISSUE=$1
  local TITLE=$2
  local URL=$3
  local BODY=$4
  local CODEX_OUTPUT_FILE=$5
  local BRANCH=$6
  local PR_BODY_FILE
  local pr_list_json
  local pr_number
  local pr_create_output

  echo "🔄 Auto-committing, pushing and creating PR..."
  stage_relevant_issue_files
  if git_in_issue_context diff --cached --quiet; then
    echo "No changes for #$ISSUE"
    return 0
  fi

  if ! check_file_line_limit; then
    echo "❌ Commit aborted due to file size limit."
    return 1
  fi

  # Use Gleam hook for conventional msg (per implement_stage + spec/25 + t_39ab1e08)
  local commit_msg
  commit_msg=$(generate_implement_commit_message "$ISSUE" "$TITLE")
  git_in_issue_context commit -m "$commit_msg" 
  git_in_issue_context push -u origin "$BRANCH"
  BRANCH_URL="https://github.com/$REPO/tree/$BRANCH"
  PR_BODY_FILE=$(mktemp "${TMPDIR:-/tmp}/grkr-pr-body.XXXXXX")
  extract_codex_pr_body "$CODEX_OUTPUT_FILE" "$PR_BODY_FILE" "$BODY" "$TITLE" "$ISSUE" "$URL"
  pr_list_json=$(gh pr list --head "$BRANCH" --json number,url 2>/dev/null || true)
  pr_number=$(printf '%s' "$pr_list_json" | jq -r '.[0].number // empty')
  if [ -n "$pr_number" ]; then
    gh pr edit "$pr_number" --title "$TITLE" --body-file "$PR_BODY_FILE" >/dev/null
    PR_URL=$(printf '%s' "$pr_list_json" | jq -r '.[0].url // empty')
    echo "✅ PR updated: $PR_URL"
  else
    pr_create_output=$(gh pr create --base "${MAIN_BRANCH:-main}" --head "$BRANCH" --title "$TITLE" --body-file "$PR_BODY_FILE" 2>&1) || {
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
  gh issue edit "$ISSUE" --add-label "implemented" || true
  gh issue edit "$ISSUE" --remove-label "todo" || true
  rm -f "$PR_BODY_FILE"
}

publish_github_issue_changes() {
  publish_issue_changes "$@"
}

ensure_pr_body_limit() {
  local pr_body_file=$1
  local body=$2
  local title=$3
  local issue=$4
  local url=$5
  local body_length

  body_length=$(wc -m < "$pr_body_file" | tr -d '[:space:]')
  if [ "$body_length" -gt "$MAX_PR_BODY_CHARS" ]; then
    write_compact_pr_body "$pr_body_file" "$body" "$title"
  fi

  if ! grep -Fq "Fixes #$issue" "$pr_body_file"; then
    append_issue_footer "$pr_body_file" "$issue" "$url"
  fi
}

extract_codex_pr_body() {
  local codex_output_file=$1
  local pr_body_file=$2
  local body=$3
  local title=$4
  local issue=$5
  local url=$6

  # task_log_is_sharded + emit_task_log_stream now delegate to Gleam (t_ef6b855f wiring; persist already was)
  if [ -s "$codex_output_file" ] || task_log_is_sharded "$codex_output_file"; then
    emit_task_log_stream "$codex_output_file" | awk '
      /^## / {found=1}
      found {print}
    ' > "$pr_body_file"
    if [ -s "$pr_body_file" ]; then
      ensure_pr_body_limit "$pr_body_file" "$body" "$title" "$issue" "$url"
      return 0
    fi
  fi

  write_default_pr_body "$pr_body_file" "$body" "$title"
  ensure_pr_body_limit "$pr_body_file" "$body" "$title" "$issue" "$url"
}
