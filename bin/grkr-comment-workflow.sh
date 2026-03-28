comment_job_lock_name() {
  local comment_id=$1

  printf 'comment-%s\n' "$comment_id"
}

comment_job_log_file() {
  local comment_id=$1

  printf '%s/.grkr/logs/jobs/comment-%s.log\n' "$GRKR_ROOT" "$comment_id"
}

comment_worktree_slug() {
  local comment_id=$1

  printf 'comment-%s\n' "$comment_id"
}

comment_branch_name() {
  local comment_id=$1

  printf 'robot/comment-%s\n' "$comment_id"
}

comment_worktree_dir() {
  local comment_id=$1

  printf '%s/.grkr/worktrees/comment-%s\n' "$GRKR_ROOT" "$comment_id"
}

comment_state_file() {
  printf '%s/.grkr/state/processed_comments.json\n' "$GRKR_ROOT"
}

comment_last_scan_file() {
  printf '%s/.grkr/state/last_comment_scan_at\n' "$GRKR_ROOT"
}

comment_body_trimmed() {
  printf '%s' "${1:-}" | jq -Rr 'gsub("^\\s+|\\s+$"; "")'
}

comment_command_text() {
  local body
  local trimmed

  body=${1:-}
  trimmed=$(comment_body_trimmed "$body")
  case "$trimmed" in
    '@:robot:'*)
      trimmed=${trimmed#@:robot:}
      printf '%s' "$trimmed" | sed '1s/^[[:space:]]*//'
      ;;
    *)
      printf '%s' "$trimmed"
      ;;
  esac
}

comment_is_actionable_body() {
  case "$(comment_body_trimmed "${1:-}")" in
    '@:robot:'*)
      return 0
      ;;
  esac
  return 1
}

comment_body_sha() {
  local body=${1:-}

  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$body" | sha256sum | awk '{print $1}'
    return 0
  fi

  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$body" | shasum -a 256 | awk '{print $1}'
    return 0
  fi

  if command -v openssl >/dev/null 2>&1; then
    printf '%s' "$body" | openssl dgst -sha256 | awk '{print $2}'
    return 0
  fi

  printf '%s' "$body" | cksum | awk '{print $1}'
}

comment_state_init() {
  local state_file

  state_file=$(comment_state_file)
  mkdir -p "$(dirname "$state_file")"
  [ -f "$state_file" ] || printf '{}\n' > "$state_file"
}

comment_state_entry_matches() {
  local comment_id=$1
  local updated_at=$2
  local body_sha=$3

  comment_state_init
  jq -e --arg comment_id "$comment_id" --arg updated_at "$updated_at" --arg body_sha "$body_sha" '
    .[$comment_id]?
    | select(.status == "done" and .updated_at == $updated_at and .body_sha == $body_sha)
  ' "$(comment_state_file)" >/dev/null 2>&1
}

comment_state_record() {
  local comment_id=$1
  local updated_at=$2
  local body_sha=$3
  local outcome=$4
  local processed_at=${5:-}
  local state_file
  local tmp_file

  comment_state_init
  [ -n "$processed_at" ] || processed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  state_file=$(comment_state_file)
  tmp_file=$(mktemp "${TMPDIR:-/tmp}/grkr-comment-state.XXXXXX")
  jq \
    --arg comment_id "$comment_id" \
    --arg updated_at "$updated_at" \
    --arg body_sha "$body_sha" \
    --arg outcome "$outcome" \
    --arg processed_at "$processed_at" '
    .[$comment_id] = {
      status: "done",
      updated_at: $updated_at,
      body_sha: $body_sha,
      outcome: $outcome,
      processed_at: $processed_at
    }
  ' "$state_file" > "$tmp_file"
  mv "$tmp_file" "$state_file"
}

comment_fetch_json() {
  local comment_id=$1

  gh api "repos/$REPO/issues/comments/$comment_id" 2>/dev/null
}

comment_fetch_parent_json() {
  local issue_url=$1

  gh api "$issue_url" 2>/dev/null
}

comment_fetch_parent_comments_json() {
  local issue_url=$1

  gh api "$issue_url/comments" 2>/dev/null
}

comment_fetch_pull_request_json() {
  local pull_request_url=$1

  [ -n "$pull_request_url" ] || return 1
  gh api "$pull_request_url" 2>/dev/null
}

comment_issue_number_from_url() {
  local issue_url=$1

  printf '%s' "$issue_url" | sed -E 's#.*/issues/([0-9]+)$#\1#'
}

comment_worktree_base_ref() {
  local issue_json=$1
  local pull_request_url
  local pull_request_json
  local head_sha

  pull_request_url=$(printf '%s' "$issue_json" | jq -r '.pull_request.url // empty')
  if [ -n "$pull_request_url" ]; then
    pull_request_json=$(comment_fetch_pull_request_json "$pull_request_url" 2>/dev/null || true)
    if [ -n "$pull_request_json" ]; then
      head_sha=$(printf '%s' "$pull_request_json" | jq -r '.head.sha // empty')
      [ -n "$head_sha" ] && {
        printf '%s\n' "$head_sha"
        return 0
      }
    fi
  fi

  issue_worktree_base_ref
}

comment_recent_comments_summary() {
  local comments_json=$1

  printf '%s' "$comments_json" | jq -r '
    ((if type == "array" then . else [] end) | reverse | .[0:5] | reverse)
    | map({
        author: (.user.login // .author.login // "unknown"),
        body: ((.body // "") | gsub("\\s+"; " ") | ltrimstr(" ") | rtrimstr(" "))
      })
    | map("- @" + .author + ": " + (.body | .[0:140]))
    | join("\n")
  '
}

comment_default_response() {
  local outcome=$1

  case "$outcome" in
    answer-only)
      printf '%s\n' 'Answered the command without making repository changes.'
      ;;
    code-change)
      printf '%s\n' 'Applied the requested code change in the dedicated worktree.'
      ;;
    triage)
      printf '%s\n' 'Triaged the request and recorded the result in the command thread.'
      ;;
    refuse)
      printf '%s\n' 'Refused the command after evaluating the request and context.'
      ;;
    *)
      printf '%s\n' 'Processed the command.'
      ;;
  esac
}

comment_default_commit_message() {
  local comment_id=$1

  printf 'feat(robot): handle comment #%s\n' "$comment_id"
}

comment_add_reaction() {
  local comment_id=$1
  local reaction=$2

  gh api "repos/$REPO/issues/comments/$comment_id/reactions" \
    -X POST \
    -f content="$reaction" \
    --jq '.id' 2>/dev/null
}

comment_remove_reaction() {
  local comment_id=$1
  local reaction_id=$2

  [ -n "$reaction_id" ] || return 0
  gh api "repos/$REPO/issues/comments/$comment_id/reactions/$reaction_id" -X DELETE >/dev/null 2>&1 || true
}

comment_write_prompt_file() {
  local file=$1
  local comment_id=$2
  local outcome_context=$3
  local command_text=$4
  local issue_number=$5
  local issue_title=$6
  local issue_body=$7
  local issue_url=$8
  local issue_comments_summary=$9
  local worktree_dir=${10}
  local base_ref=${11}

  cat > "$file" <<EOF
Process the GitHub comment command below.

Return a single compact JSON object on the first non-empty line and nothing else.

Required keys:
- "outcome": one of "answer-only", "code-change", "triage", or "refuse"
- "response": markdown reply body
- "commit_message": optional commit message for code changes or triage work

Comment rules:
- Support answer-only, code-change, triage, and refuse outcomes.
- Use the dedicated worktree for any mutation.
- Keep the response concise and actionable.
- Do not emit shell code or extra prose outside the JSON object.

Comment metadata:
- Comment id: $comment_id
- Outcome context: $outcome_context
- Command text: $command_text

Issue/PR context:
- Number: $issue_number
- Title: $issue_title
- URL: $issue_url
- Worktree: $worktree_dir
- Base ref: $base_ref

Issue or PR body:
$issue_body

Recent comments:
$issue_comments_summary
EOF
}

comment_first_json_line() {
  local output_file=$1

  awk 'NF {print; exit}' "$output_file"
}

run_codex_prompt() {
  local prompt_file=$1
  local output_file=$2
  local phase_label=$3
  local mode=${4:-replace}
  local workdir=${5:-$(pwd)}
  local run_output_file

  run_output_file=$(mktemp "${TMPDIR:-/tmp}/grkr-codex-output.XXXXXX")
  echo "🚀 Running codex to $phase_label..."
  echo "Prompt saved to $prompt_file for reference."
  codex exec --full-auto --cd "$workdir" < "$prompt_file" >"$run_output_file" 2>&1
  cat "$run_output_file"
  echo ""

  persist_task_log_output "$run_output_file" "$output_file" "$phase_label" "$mode"
  echo "✅ codex has finished $phase_label."
}
