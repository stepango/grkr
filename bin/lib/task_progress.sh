# bin/lib/task_progress.sh
# Shared helpers for task progress JSON state (ensure/init, stage updates, mark complete/failed/refused) + meta.env / issue-context.json writers.
# Extracted per t_b5bd0fa8 (fix: bin/grkr under 1000 LOC) + prior t_58795e29 refusal pattern to satisfy AGENTS.md "every file <=1000 LOC".
# Small explicit extraction; no behavior change. Duplicated JSON jq logic consolidated here for sharing between bin/grkr (process_issue, ensure_checkpoint, test checkpoint) and bin/lib/refusal_paths.sh (refusal marks).
# Includes timestamp_utc (only used by these).
# GitHub-only v2. Sourced in bin/grkr after grkr-issue-workflow.sh (and refusal_paths); fns available at runtime for calls from lib.
# Preserves all shell conventions (jq, mktemp, printf %q, etc).

timestamp_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

ensure_task_progress_file() {
  local progress_file=$1
  local issue=$2
  local project_item_id=$3
  local task_slug=$4
  local branch=$5
  local now
  local tmp_file

  [ -f "$progress_file" ] && return 0

  now=$(timestamp_utc)
  tmp_file=$(mktemp "${TMPDIR:-/tmp}/grkr-progress.XXXXXX")
  jq -n \
    --argjson issue_number "$issue" \
    --arg project_item_id "$project_item_id" \
    --arg task_slug "$task_slug" \
    --arg branch "$branch" \
    --arg started_at "$now" \
    --arg updated_at "$now" '
    {
      issue_number: $issue_number,
      task_slug: $task_slug,
      branch: $branch,
      status: "planning",
      decision: "undecided",
      stages: {
        research: {status: "pending"},
        plan: {status: "pending"},
        implement_or_refuse: {status: "pending"},
        test: {status: "pending"}
      },
      started_at: $started_at,
      updated_at: $updated_at
    }
    | if $project_item_id == "" then . else . + {project_item_id: $project_item_id} end
  ' > "$tmp_file"
  mv "$tmp_file" "$progress_file"
}

update_task_progress_stage() {
  local progress_file=$1
  local stage=$2
  local status=$3
  local comment_id=$4
  local now
  local tmp_file

  now=$(timestamp_utc)
  tmp_file=$(mktemp "${TMPDIR:-/tmp}/grkr-progress.XXXXXX")
  jq \
    --arg stage "$stage" \
    --arg status "$status" \
    --arg comment_id "$comment_id" \
    --arg updated_at "$now" '
    .status = "planning"
    | .updated_at = $updated_at
    | .stages[$stage].status = $status
    | if $comment_id == "" then
        del(.stages[$stage].comment_id)
      else
        .stages[$stage].comment_id = ($comment_id | tonumber? // $comment_id)
      end
  ' "$progress_file" > "$tmp_file"
  mv "$tmp_file" "$progress_file"
}

mark_task_progress_failed() {
  local progress_file=$1
  local stage=$2
  local now
  local tmp_file

  now=$(timestamp_utc)
  tmp_file=$(mktemp "${TMPDIR:-/tmp}/grkr-progress.XXXXXX")
  jq \
    --arg stage "$stage" \
    --arg updated_at "$now" '
    .status = "failed"
    | .updated_at = $updated_at
    | .stages[$stage].status = "failed"
  ' "$progress_file" > "$tmp_file"
  mv "$tmp_file" "$progress_file"
}

mark_task_progress_complete() {
  local progress_file=$1
  local branch_url=$2
  local pr_url=$3
  local now
  local tmp_file

  now=$(timestamp_utc)
  tmp_file=$(mktemp "${TMPDIR:-/tmp}/grkr-progress.XXXXXX")
  jq \
    --arg branch_url "$branch_url" \
    --arg pr_url "$pr_url" \
    --arg updated_at "$now" '
    .status = "complete"
    | .decision = "proceed"
    | .updated_at = $updated_at
    | .stages.implement_or_refuse.status = "done"
    | .stages.test.status = "done"
    | .branch_url = $branch_url
    | .pr_url = $pr_url
  ' "$progress_file" > "$tmp_file"
  mv "$tmp_file" "$progress_file"
}

mark_task_progress_refused() {
  local progress_file=$1
  local reason_class=$2
  local comment_id=$3
  local now
  local tmp_file

  now=$(timestamp_utc)
  tmp_file=$(mktemp "${TMPDIR:-/tmp}/grkr-progress.XXXXXX")
  jq \
    --arg reason_class "$reason_class" \
    --arg comment_id "$comment_id" \
    --arg updated_at "$now" '
    .status = "refused"
    | .decision = "refuse"
    | .updated_at = $updated_at
    | .stages.implement_or_refuse.status = "done"
    | .stages.implement_or_refuse.reason_class = $reason_class
    | if $comment_id == "" then
        del(.stages.implement_or_refuse.comment_id)
      else
        .stages.implement_or_refuse.comment_id = ($comment_id | tonumber? // $comment_id)
      end
    | .stages.test.status = "skipped"
  ' "$progress_file" > "$tmp_file"
  mv "$tmp_file" "$progress_file"
}

write_task_meta_env() {
  local task_dir=$1
  local issue=$2
  local task_slug=$3
  local branch=$4
  local url=$5
  local project_item_id=$6
  local meta_file

  meta_file="$task_dir/meta.env"
  {
    printf 'ISSUE_NUMBER=%q\n' "$issue"
    printf 'TASK_SLUG=%q\n' "$task_slug"
    printf 'BRANCH=%q\n' "$branch"
    printf 'ISSUE_URL=%q\n' "$url"
    printf 'PROJECT_ITEM_ID=%q\n' "$project_item_id"
  } > "$meta_file"
}

write_issue_context_file() {
  local task_dir=$1
  local issue_json=$2
  local context_file

  context_file="$task_dir/issue-context.json"
  printf '%s' "$issue_json" | jq '.' > "$context_file"
}
