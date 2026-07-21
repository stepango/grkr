# bin/lib/github_issue_stages_research_plan.sh
# Stages-split slice 1 (docs/design-github-issue-stages-split.md §4–§6 / §8 / §10):
# fetch_issue_comments_json + checkpoint_comment_id_from_json +
# checkpoint_comment_body_from_json + ensure_checkpoint_stage extracted from
# github_issue.sh into this sibling module. github_issue.sh is the facade that
# sources this file. bin/grkr still sources only github_issue.sh.
#
# Ambient deps resolved at call time (from bin/grkr or tests sourcing github_issue.sh):
#   checkpoint_marker (issue_shared), update_task_progress_stage,
#   write_research_checkpoint_file, write_plan_checkpoint_file (templates),
#   gh, jq.
# ensure_test_checkpoint (stages-split slice 2 in github_issue_stages_test.sh)
# calls the comment helpers ambiently (facade sources research_plan then test).
# Zero behavior change. Stable function names. No Linear / issue_shared dump.
# No new flags. No checkpoint-json Gleam extract.

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
