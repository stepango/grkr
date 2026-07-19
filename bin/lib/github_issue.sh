# bin/lib/github_issue.sh
# GitHub-only orchestration extracted from process_issue in bin/grkr.
# Slice 1 (landed PR #112): test checkpoint (ensure_test_checkpoint + write_test_checkpoint_file).
# Slice 3 (landed PR #115): publish helpers (publish_issue_changes + extract_codex_pr_body + ensure_pr_body_limit).
# Slice 4: research/plan ensure_checkpoint_stage + gh comment helpers (fetch_issue_comments_json, checkpoint_comment_id_from_json, checkpoint_comment_body_from_json).
# Slice 5 (t_d328b158): completion surface (post_completion_comment).
# Slice 6 (t_3619188b): thin process_issue orchestration. Bootstrap, decision stage, implement stage, decision-refuse cleanup, and finalize complete extracted here. process_issue in bin/grkr is now a clear thin sequencer of ensure_*/run_* + shared calls.
# Slice 7 (this): PR body helpers thinned (ensure_pr_body_limit + extract_codex_pr_body) to Gleam progress/templates + cli; thin delegates via grkr-templates.sh. External signatures + behavior identical. github_issue.sh net thinner.
# Slice 8: completion summary render (post_completion_comment body) moved to Gleam progress/templates + cli + thin delegate; post_completion_comment is now thin shell wrapper (gh comment preserved, exact body via render). External contract identical.
# Purpose: GitHub-specific publish (stage/commit via Gleam hook/push, PR create-or-edit,
# "Fixes #N" footer via append, label "implemented"/remove "todo", PR body from codex log or default).
# Mirrors bin/lib/linear_issue.sh thin-delegate pattern (Linear uses its own extract_linear_* / ensure_linear_*).
# Functions assume ambient helpers (stage_relevant_issue_files, git_in_issue_context,
# check_file_line_limit, generate_implement_commit_message, emit_task_log_stream,
# task_log_is_sharded, write_default_pr_body, write_compact_pr_body, append_issue_footer,
# REPO, MAIN_BRANCH, MAX_PR_BODY_CHARS, BRANCH_URL, PR_URL globals, etc.) are already defined
# in the sourcing shell (bin/grkr defines/sources them; bash resolves at call time).
# Shared helpers: test-write cluster (write_test_checkpoint_with_header + build_command_list + cleanup_test_result_logs)
# + line-limit helpers (collect_file_line_limit_violations, check_file_line_limit,
# ensure_publishable_file_sizes) + run_codex_prompt (codex/exec + persist bridge)
# + progress bridge (run_progress_cli + checkpoint_marker) now live in
# bin/lib/issue_shared.sh (sourced by grkr before provider libs).
# attach_issue_logs now lives in issue_shared.sh (Slice 5).
# Remaining launcher-only in bin/grkr: process_issue surface (thin sequencer) + cleanup/trap.
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
  # url accepted for sig compat (unused by footer render, per prior).
  # Write via temp file so trailing newlines from Gleam are not stripped by $(...).
  local tmp_out
  tmp_out=$(mktemp "${TMPDIR:-/tmp}/grkr-pr-ensure.XXXXXX")
  ensure_github_pr_body "$pr_body_file" "$body" "$title" "$issue" "${MAX_PR_BODY_CHARS:-60000}" > "$tmp_out"
  mv "$tmp_out" "$pr_body_file"
}

extract_codex_pr_body() {
  local codex_output_file=$1
  local pr_body_file=$2
  local body=$3
  local title=$4
  local issue=$5
  local url=$6

  # task_log_is_sharded + emit_task_log_stream delegate to Gleam (unchanged); select + ensure now Gleam too (path I/O)
  if [ -s "$codex_output_file" ] || task_log_is_sharded "$codex_output_file"; then
    local tmp_log
    tmp_log=$(mktemp "${TMPDIR:-/tmp}/grkr-codex-pr-body.XXXXXX")
    emit_task_log_stream "$codex_output_file" > "$tmp_log"
    select_codex_pr_section "$tmp_log" > "$pr_body_file"
    rm -f "$tmp_log"
    if [ -s "$pr_body_file" ]; then
      ensure_pr_body_limit "$pr_body_file" "$body" "$title" "$issue" "$url"
      return 0
    fi
  fi

  write_default_pr_body "$pr_body_file" "$body" "$title"
  ensure_pr_body_limit "$pr_body_file" "$body" "$title" "$issue" "$url"
}

# GitHub completion helper (slice 5). Moved from bin/grkr for thinning.
# Posts gh issue completion summary body with branch + PR URLs.
# Slice 8: pure summary render moved to Gleam (render_github_completion_summary);
# this shell function is now a thin delegate (preserves exact signature/contract).
# Alias provided for design naming parity (post_github_completion_comment like publish_*).
# Call site in process_issue remains `post_completion_comment` (zero churn).
post_completion_comment() {
  local issue=$1
  local title=$2
  local branch_url=$3
  local pr_url=$4
  local summary_file

  # Use temp file to preserve trailing newline from Gleam render (matches original heredoc).
  summary_file=$(mktemp "${TMPDIR:-/tmp}/grkr-completion.XXXXXX")
  render_github_completion_summary "$issue" "$title" "$branch_url" "$pr_url" > "$summary_file"
  gh issue comment "$issue" --body-file "$summary_file" >/dev/null
  rm -f "$summary_file"
}

post_github_completion_comment() {
  post_completion_comment "$@"
}

# --- Slice 6: process_issue thinning (orchestrator moved to thin launcher in bin/grkr) ---

# Bootstrap: validation, gh fetch, globals (TITLE/BODY/URL etc), TASK_DIR/PROGRESS/BRANCH,
# meta/context/progress writes. Returns 1 on validation fail or not-found.
# Sets same globals process_issue used to set so downstream stages (checkpoints, decision, etc)
# and shared code continue to work identically. Exact body moved from process_issue.
bootstrap_github_issue_task() {
  local ISSUE=$1
  if [ "$VALIDATION_OK" -ne 1 ]; then
    echo "⚠️ Validation failed; skipping issue #$ISSUE."
    return 1
  fi
  echo "📋 Fetching issue #$ISSUE..."
  ISSUE_JSON=$(gh issue view "$ISSUE" --comments --json title,body,url,number,projectItems,comments 2>&1)
  if echo "$ISSUE_JSON" | grep -q "Could not resolve"; then
    echo "❌ Issue #$ISSUE not found."
    return 1
  fi
  TITLE=$(echo "$ISSUE_JSON" | jq -r '.title')
  BODY=$(echo "$ISSUE_JSON" | jq -r '.body // "No description provided."')
  URL=$(echo "$ISSUE_JSON" | jq -r '.url')
  TASKS_DIR="$GRKR_ROOT/.grkr/tasks"
  TASK_SLUG=$(task_slug_for_issue "$ISSUE" "$TITLE")
  TASK_DIR="$TASKS_DIR/$TASK_SLUG"
  PROGRESS_FILE="$TASK_DIR/progress.json"
  echo "📝 Issue: $TITLE"
  echo "🔗 $URL"
  BRANCH="issue-$ISSUE"
  CURRENT_ISSUE="$ISSUE"
  ATTACH_ISSUE_LOGS=1
  PROJECT_ITEM_ID=$(issue_project_item_id "$ISSUE" "$ISSUE_JSON")
  mkdir -p "$TASK_DIR"
  write_task_meta_env "$TASK_DIR" "$ISSUE" "$TASK_SLUG" "$BRANCH" "$URL" "$PROJECT_ITEM_ID"
  write_issue_context_file "$TASK_DIR" "$ISSUE_JSON"
  ensure_task_progress_file "$PROGRESS_FILE" "$ISSUE" "$PROJECT_ITEM_ID" "$TASK_SLUG" "$BRANCH"
}

# Decision stage (prepare worktree + codex decision + gate). Exact body moved.
# Sets ISSUE_WORKTREE_DIR and IMPLEMENTATION_DECISION.
# Returns 0 and prints decision value for logging context; 1 on invalid gate result (after cleanup).
# Temps cleaned in all paths. Side effects for refuse are inside run_decision_gate (Gleam).
run_github_decision_stage() {
  local decision_prompt_file
  local decision_output_file
  local decision

  ISSUE_WORKTREE_DIR=$(prepare_issue_worktree "$BRANCH" "$TASK_SLUG") || return 1
  decision_prompt_file=$(mktemp "${TMPDIR:-/tmp}/grkr-decision-prompt.XXXXXX")
  decision_output_file=$(mktemp "${TMPDIR:-/tmp}/grkr-decision-output.XXXXXX")
  write_decision_prompt_file "$decision_prompt_file" "$ISSUE" "$TITLE" "$URL" "$BODY" "$TASK_SLUG" "$ISSUE_WORKTREE_DIR"
  # Wired to Gleam decision_gate (spec/22 implement-or-refuse + t_4e22c63f): thin shell runs codex to output file (orchestration); gate does extract, progress update, refuse path (calls refusal/flow for checkpoint/backlog/comment), prints "proceed"/"refuse" on stdout.
  # Replaces prior inlined run_implementation_decision_gate + extract/update/handle_decision_refusal (now dupe removed; gate reuses Gleam decision + refusal/flow).
  run_codex_prompt "$decision_prompt_file" "$decision_output_file" "decide whether to implement the issue" replace "$ISSUE_WORKTREE_DIR"
  decision=$(run_decision_gate "$ISSUE" "$decision_output_file" "$PROGRESS_FILE" "$TASK_SLUG" "$ISSUE_WORKTREE_DIR" "$decision_prompt_file" || echo "")
  decision=$(printf '%s' "$decision" | tr -d '\r\n' | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  rm -f "$decision_prompt_file" "$decision_output_file"
  case "$decision" in
    proceed|refuse)
      IMPLEMENTATION_DECISION=$decision
      ;;
    *)
      echo "❌ Decision gate for issue #$ISSUE returned an invalid result."
      return 1
      ;;
  esac
}

# Refuse cleanup when decision was refuse (worktree + globals + attach logs).
# Exact messages and side effects from original process_issue refuse tail.
# (Decision gate already performed checkpoint/backlog/progress/comment side effects.)
handle_github_decision_refuse() {
  if [ -n "${ISSUE_WORKTREE_DIR:-}" ]; then
    cleanup_issue_worktree "$ISSUE_WORKTREE_DIR"
    echo "🧹 Removed issue worktree: $ISSUE_WORKTREE_DIR"
  fi
  CURRENT_ISSUE_WORKTREE=""
  ATTACH_ISSUE_LOGS=0
  attach_issue_logs
}

# Implement stage (move in progress + codex implement + detect impl-refusal conversion path).
# On impl-refusal: full conversion (handle + mark refused + cleanup + attach + messages), sets flag, returns 0 (terminal).
# On real error: clears state and returns 1.
# On success (no refusal): leaves worktree/prompt/codex_output in place via globals for sizes/test/publish; returns 0 to continue.
# Uses CURRENT_PROMPT_FILE and $TASK_DIR/implementation.log for downstream (no local leakage).
run_github_implement_stage() {
  local prompt_file
  local codex_output_file
  local implementation_refusal
  local implementation_refusal_class
  local implementation_refusal_reasoning
  local refusal_result
  local refusal_class
  local refusal_comment_id

  move_issue_to_in_progress "$ISSUE" "$ISSUE_JSON" || return 1
  CURRENT_ISSUE_WORKTREE="$ISSUE_WORKTREE_DIR"
  prompt_file=$(mktemp "${TMPDIR:-/tmp}/grkr-prompt.XXXXXX")
  CURRENT_PROMPT_FILE="$prompt_file"
  write_issue_prompt_file "$prompt_file" "$ISSUE" "$TITLE" "$URL" "$BODY" "$TASK_SLUG" "$ISSUE_WORKTREE_DIR"
  codex_output_file="$TASK_DIR/implementation.log"
  run_codex_prompt "$prompt_file" "$codex_output_file" "implement the issue" replace "$ISSUE_WORKTREE_DIR"
  implementation_refusal=$(detect_implementation_refusal "$codex_output_file")
  if [ -n "$implementation_refusal" ]; then
    echo "⚠️ Implementation discovered blockers that require refusal."
    echo "🔄 Converting implementation attempt to refusal for issue #$ISSUE."
    implementation_refusal_class=$(normalize_refusal_class "$implementation_refusal")
    implementation_refusal_reasoning=$(extract_refusal_reasoning "$implementation_refusal" "Implementation discovered that the issue is not ready for safe autonomous completion.")
    mkdir -p "$TASK_DIR/codex"
    cp "$codex_output_file" "$TASK_DIR/codex/implementation-before-refusal.log"
    refusal_result=$(handle_implementation_refusal "$ISSUE" "$PROGRESS_FILE" "$implementation_refusal_class" "$implementation_refusal_reasoning") || {
      CURRENT_ISSUE_WORKTREE=""
      rm -f "$prompt_file"
      CURRENT_PROMPT_FILE=""
      return 1
    }
    refusal_class=$(printf '%s\n' "$refusal_result" | tail -n2 | head -n1)
    refusal_comment_id=$(printf '%s\n' "$refusal_result" | tail -n1)
    mark_task_progress_refused "$PROGRESS_FILE" "$refusal_class" "$refusal_comment_id"
    if [ -n "${ISSUE_WORKTREE_DIR:-}" ]; then
      cleanup_issue_worktree "$ISSUE_WORKTREE_DIR"
      echo "🧹 Removed issue worktree: $ISSUE_WORKTREE_DIR"
    fi
    CURRENT_ISSUE_WORKTREE=""
    rm -f "$prompt_file"
    CURRENT_PROMPT_FILE=""
    echo "⏸️ Refused implementation for issue #$ISSUE (converted during implementation)."
    ATTACH_ISSUE_LOGS=0
    attach_issue_logs
    GITHUB_IMPL_REFUSED=1
    return 0
  fi
  # success path: worktree + CURRENT_PROMPT_FILE + $TASK_DIR/implementation.log left for caller stages
  return 0
}

# Finalize tail for happy complete path (exact). Clears worktree/prompt, marks, moves to Done, posts comment, attaches logs.
# Keeps process_issue thin without hiding the move warn (warn is still emitted).
finalize_github_issue_complete() {
  CURRENT_ISSUE_WORKTREE=""
  mark_task_progress_complete "$PROGRESS_FILE" "$BRANCH_URL" "$PR_URL"
  if ! move_issue_to_done "$ISSUE" "$ISSUE_JSON"; then
    echo "⚠️ Issue #$ISSUE implementation succeeded, but the project status could not be moved to ${DONE_VALUE:-Done}."
  fi
  post_completion_comment "$ISSUE" "$TITLE" "$BRANCH_URL" "$PR_URL"
  rm -f "$CURRENT_PROMPT_FILE"
  CURRENT_PROMPT_FILE=""
  ATTACH_ISSUE_LOGS=0
  attach_issue_logs
}
