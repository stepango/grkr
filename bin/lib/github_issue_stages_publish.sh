# bin/lib/github_issue_stages_publish.sh
# Stages-split slice 3 (docs/design-github-issue-stages-split.md §4–§6 / §8 / §10):
# publish_issue_changes + publish_github_issue_changes alias + ensure_pr_body_limit +
# extract_codex_pr_body + post_completion_comment + post_github_completion_comment alias
# extracted from github_issue.sh into this sibling module. github_issue.sh is the facade
# that sources this file after github_issue_stages_research_plan.sh then
# github_issue_stages_test.sh. bin/grkr still sources only github_issue.sh.
#
# Ambient deps resolved at call time (from bin/grkr or tests sourcing github_issue.sh):
#   stage_relevant_issue_files, git_in_issue_context, check_file_line_limit,
#   generate_implement_commit_message, task_log_is_sharded, emit_task_log_stream,
#   select_codex_pr_section, ensure_github_pr_body, write_default_pr_body
#   (templates / issue_shared / implement_stage), render_github_completion_summary,
#   REPO, MAIN_BRANCH, MAX_PR_BODY_CHARS, BRANCH_URL, PR_URL (set inside publish),
#   gh, jq, awk.
# finalize_github_issue_complete (still in facade until slice 4) calls
# post_completion_comment ambiently (facade sources publish before process_issue runs).
# Zero behavior change. Stable function names. No Linear / issue_shared dump.
# No new flags. No checkpoint-json Gleam extract.

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
