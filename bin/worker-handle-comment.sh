#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$SCRIPT_DIR/doctor.sh"
. "$SCRIPT_DIR/grkr-issue-workflow.sh"
. "$SCRIPT_DIR/grkr-comment-workflow.sh"

doctor_init

if [ -f "$GRKR_CONFIG_FILE" ]; then
  . "$GRKR_CONFIG_FILE"
fi

comment_id=${1:-}
if [ -z "$comment_id" ]; then
  echo "Usage: worker-handle-comment.sh <comment_id>" >&2
  exit 1
fi

job_log_file=$(comment_job_log_file "$comment_id")
mkdir -p "$(dirname "$job_log_file")"
exec >>"$job_log_file" 2>&1

eyes_reaction_id=""
eyes_reaction_removed=0
rocket_reaction_id=""

cleanup() {
  if [ -n "$eyes_reaction_id" ] && [ "$eyes_reaction_removed" -ne 1 ]; then
    comment_remove_reaction "$comment_id" "$eyes_reaction_id"
    eyes_reaction_removed=1
  fi
}

trap cleanup EXIT

comment_json=$(comment_fetch_json "$comment_id")
comment_body=$(printf '%s' "$comment_json" | jq -r '.body // ""')
if ! comment_is_actionable_body "$comment_body"; then
  echo "♻️ Skipping non-actionable comment #$comment_id."
  exit 0
fi

comment_updated_at=$(printf '%s' "$comment_json" | jq -r '.updated_at // empty')
comment_body_sha=$(comment_body_sha "$comment_body")
if [ -n "$comment_updated_at" ] && comment_state_entry_matches "$comment_id" "$comment_updated_at" "$comment_body_sha"; then
  echo "♻️ Reusing processed comment #$comment_id."
  exit 0
fi

issue_url=$(printf '%s' "$comment_json" | jq -r '.issue_url // empty')
if [ -z "$issue_url" ]; then
  echo "❌ Comment #$comment_id is missing issue context."
  exit 1
fi

issue_json=$(comment_fetch_parent_json "$issue_url")
issue_comments_json=$(comment_fetch_parent_comments_json "$issue_url")
issue_number=$(comment_issue_number_from_url "$issue_url")
issue_title=$(printf '%s' "$issue_json" | jq -r '.title // empty')
issue_body=$(printf '%s' "$issue_json" | jq -r '.body // ""')
issue_branch_base=$(comment_worktree_base_ref "$issue_json")
branch_name=$(comment_branch_name "$comment_id")
worktree_slug=$(comment_worktree_slug "$comment_id")
worktree_dir=$(prepare_issue_worktree "$branch_name" "$worktree_slug" "$issue_branch_base")
comment_context=$(printf '%s' "$issue_json" | jq -r 'if .pull_request? then "pull request comment" else "issue comment" end')
command_text=$(comment_command_text "$comment_body")
recent_comments_summary=$(comment_recent_comments_summary "$issue_comments_json")
prompt_file=$(mktemp "${TMPDIR:-/tmp}/grkr-comment-prompt.XXXXXX")
output_file=$(mktemp "${TMPDIR:-/tmp}/grkr-comment-output.XXXXXX")
response_file=$(mktemp "${TMPDIR:-/tmp}/grkr-comment-response.XXXXXX")
result_line=""
outcome=""
response=""
commit_message=""
if ! eyes_reaction_id=$(comment_add_reaction "$comment_id" eyes); then
  echo "⚠️ Unable to add eyes reaction for comment #$comment_id."
  eyes_reaction_id=""
fi

CURRENT_ISSUE_WORKTREE="$worktree_dir"
comment_write_prompt_file \
  "$prompt_file" \
  "$comment_id" \
  "$comment_context" \
  "$command_text" \
  "$issue_number" \
  "$issue_title" \
  "$issue_body" \
  "$issue_url" \
  "$recent_comments_summary" \
  "$worktree_dir" \
  "$issue_branch_base"

run_codex_prompt "$prompt_file" "$output_file" "process comment #$comment_id" replace "$worktree_dir"
result_line=$(comment_first_json_line "$output_file")
if [ -z "$result_line" ]; then
  echo "❌ Comment #$comment_id returned no structured result."
  exit 1
fi

outcome=$(printf '%s' "$result_line" | jq -r '.outcome // empty')
response=$(printf '%s' "$result_line" | jq -r '.response // empty')
commit_message=$(printf '%s' "$result_line" | jq -r '.commit_message // empty')

case "$outcome" in
  answer-only|code-change|triage|refuse)
    ;;
  *)
    echo "❌ Comment #$comment_id returned an unsupported outcome: $outcome"
    exit 1
    ;;
esac

if [ -z "$response" ]; then
  response=$(comment_default_response "$outcome")
fi
printf '%s\n' "$response" > "$response_file"

echo "📝 Posting response for comment #$comment_id..."
gh issue comment "$issue_number" --body-file "$response_file" >/dev/null

case "$outcome" in
  code-change|triage)
    stage_relevant_issue_files
    if ! git_in_issue_context diff --cached --quiet; then
      if [ -z "$commit_message" ]; then
        commit_message=$(comment_default_commit_message "$comment_id")
      fi
      git_in_issue_context commit -m "$commit_message" >/dev/null
      echo "✅ Committed comment changes for #$comment_id."
    else
      echo "ℹ️ No repository changes were produced for comment #$comment_id."
    fi
    ;;
esac

if [ -n "$eyes_reaction_id" ]; then
  comment_remove_reaction "$comment_id" "$eyes_reaction_id"
  eyes_reaction_removed=1
  eyes_reaction_id=""
fi

if ! rocket_reaction_id=$(comment_add_reaction "$comment_id" rocket); then
  echo "⚠️ Unable to add rocket reaction for comment #$comment_id."
  exit 1
fi

comment_state_record "$comment_id" "$comment_updated_at" "$comment_body_sha" "$outcome"
echo "✅ Comment #$comment_id processed with outcome: $outcome."

rm -f "$prompt_file" "$output_file" "$response_file"
CURRENT_ISSUE_WORKTREE=""
exit 0
