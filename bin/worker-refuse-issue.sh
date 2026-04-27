#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$SCRIPT_DIR/doctor.sh"

doctor_init

if [ -f "$GRKR_CONFIG_FILE" ]; then
  . "$GRKR_CONFIG_FILE"
fi

REPO=${REPO:-}
PROJECT_OWNER=${PROJECT_OWNER:-}
PROJECT_NUMBER=${PROJECT_NUMBER:-}
STATUS_FIELD_NAME=${STATUS_FIELD_NAME:-Status}
TODO_VALUE=${TODO_VALUE:-Todo}
IN_PROGRESS_VALUE=${IN_PROGRESS_VALUE:-In Progress}
DONE_VALUE=${DONE_VALUE:-Done}
BACKLOG_VALUE=${BACKLOG_VALUE:-Backlog}

MAIN_BRANCH=${MAIN_BRANCH:-main}
GRKR_DIR="$GRKR_ROOT/.grkr"
TASKS_DIR="$GRKR_DIR/tasks"
MAX_FILE_LINES=${MAX_FILE_LINES:-1000}

require_config_value() {
  local name=$1
  local value=${2-}

  if [ -z "$value" ]; then
    printf 'Missing required config value: %s\n' "$name" >&2
    exit 1
  fi
}

require_config_value "REPO" "$REPO"
require_config_value "PROJECT_OWNER" "$PROJECT_OWNER"
require_config_value "PROJECT_NUMBER" "$PROJECT_NUMBER"

slugify_text() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9]/-/g; s/-\{2,\}/-/g; s/^-//; s/-$//' \
    | cut -c1-80
}

task_slug_for_issue() {
  local issue=$1
  local title=$2
  local title_slug

  title_slug=$(slugify_text "$title")
  [ -n "$title_slug" ] || title_slug="task"
  printf 'issue-%s-%s\n' "$issue" "$title_slug"
}

timestamp_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

checkpoint_marker() {
  local stage=$1
  local task_slug=$2

  printf '<!-- grkr:checkpoint stage=%s task=%s version=1 -->' "$stage" "$task_slug"
}

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

valid_refusal_class() {
  case "$1" in
    underspecified|too_large|missing_dependency|needs_design_decision|unsafe_autonomous_change|repo_not_ready|other)
      return 0
      ;;
  esac
  return 1
}

normalize_refusal_class_candidate() {
  local candidate

  candidate=$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | tr ' -' '__' | tr -cd 'a-z0-9_')
  if valid_refusal_class "$candidate"; then
    printf '%s\n' "$candidate"
  else
    printf 'other\n'
  fi
}

refusal_missing_requirements_markdown() {
  local refusal_class=$1
  local reasoning=$2

  case "$refusal_class" in
    underspecified)
      cat <<EOF
- Explicit acceptance criteria or expected behavior examples
- Clear success conditions for the implementation and test stages
EOF
      ;;
    too_large)
      cat <<EOF
- A smaller, explicitly scoped first slice of work
- A concrete split between independent follow-up issues
EOF
      ;;
    missing_dependency)
      cat <<EOF
- The missing upstream dependency, API, or prerequisite issue
- Confirmation that the dependency is available in the target branch
EOF
      ;;
    needs_design_decision)
      cat <<EOF
- A concrete design or product decision for the ambiguous behavior
- Confirmation of the preferred implementation direction
EOF
      ;;
    unsafe_autonomous_change)
      cat <<EOF
- Human review for the risky change path
- A safer bounded approach or rollback strategy
EOF
      ;;
    repo_not_ready)
      cat <<EOF
- Repository health restored enough for issue-local changes to be validated
- Confirmation that unrelated build or test failures are resolved
EOF
      ;;
    *)
      cat <<EOF
- The missing prerequisite identified in the refusal reasoning above
- A narrower, directly testable issue scope
EOF
      ;;
  esac
}

refusal_next_steps_markdown() {
  local refusal_class=$1

  case "$refusal_class" in
    too_large)
      cat <<EOF
- Split the issue into smaller independently testable tasks
- Re-run the workflow against the first bounded slice
EOF
      ;;
    *)
      cat <<EOF
- Update the issue with the missing detail identified above
- Re-run the workflow after the issue is clarified and bounded
EOF
      ;;
  esac
}

refusal_split_recommendation() {
  case "$1" in
    too_large|unsafe_autonomous_change)
      printf 'Yes. The current issue is too broad for one safe autonomous change.\n'
      ;;
    *)
      printf 'No immediate split is required if the missing prerequisite can be resolved directly in this issue.\n'
      ;;
  esac
}

refusal_follow_up_recommendation() {
  case "$1" in
    too_large|missing_dependency|needs_design_decision)
      printf 'Yes. Follow-up issues are recommended to separate prerequisite or decision work.\n'
      ;;
    *)
      printf 'Not necessarily. The current issue may proceed once the missing information is added.\n'
      ;;
  esac
}

write_refusal_checkpoint_file() {
  local checkpoint_file=$1
  local issue=$2
  local title=$3
  local task_slug=$4
  local refusal_class=$5
  local reasoning=$6

  {
    printf '%s\n\n' "$(checkpoint_marker refusal "$task_slug")"
    printf '## Implementation refused\n\n'
    printf 'Issue #%s: %s\n\n' "$issue" "$title"
    printf '### Refusal summary\n\n'
    printf 'The issue was not implemented because the decision gate returned `refuse`.\n\n'
    printf '### Reason class\n\n'
    printf '%s\n\n' "$refusal_class"
    printf '### Detailed reasoning\n\n'
    printf '%s\n\n' "$reasoning"
    printf '### What is needed before implementation\n\n'
    refusal_missing_requirements_markdown "$refusal_class" "$reasoning"
    printf '\n\n### Suggested next actions\n\n'
    refusal_next_steps_markdown "$refusal_class"
    printf '\n\n### Should the issue be split?\n\n'
    refusal_split_recommendation "$refusal_class"
    printf '\n### Are follow-up issues recommended?\n\n'
    refusal_follow_up_recommendation "$refusal_class"
  } > "$checkpoint_file"
}

ensure_refusal_checkpoint() {
  local issue=$1
  local issue_json=$2
  local task_slug=$3
  local task_dir=$4
  local title=$5
  local refusal_class=$6
  local reasoning=$7
  local checkpoint_file
  local comment_id
  local comment_body
  local refreshed_comments_json

  checkpoint_file="$task_dir/refusal.md"
  comment_id=$(checkpoint_comment_id_from_json "$issue_json" refusal "$task_slug")

  if [ -f "$checkpoint_file" ] && [ -n "$comment_id" ]; then
    echo "♻️ Reusing refusal checkpoint for issue #$issue from comment $comment_id." >&2
    printf '%s\n' "$comment_id"
    return 0
  fi

  if [ -n "$comment_id" ] && [ ! -f "$checkpoint_file" ]; then
    comment_body=$(checkpoint_comment_body_from_json "$issue_json" refusal "$task_slug")
    if [ -n "$comment_body" ]; then
      printf '%s\n' "$comment_body" > "$checkpoint_file"
      echo "♻️ Restored refusal checkpoint for issue #$issue from comment $comment_id." >&2
      printf '%s\n' "$comment_id"
      return 0
    fi
  fi

  write_refusal_checkpoint_file "$checkpoint_file" "$issue" "$title" "$task_slug" "$refusal_class" "$reasoning"
  echo "📝 Posting refusal checkpoint for issue #$issue..." >&2
  gh issue comment "$issue" --body-file "$checkpoint_file" >/dev/null
  refreshed_comments_json=$(fetch_issue_comments_json "$issue")
  comment_id=$(checkpoint_comment_id_from_json "$refreshed_comments_json" refusal "$task_slug")
  printf '%s\n' "$comment_id"
}

issue_project_item_id() {
  local issue=$1
  local issue_json=$2
  local item_id
  local items_json

  item_id=$(printf '%s' "$issue_json" | jq -r --arg project_number "$PROJECT_NUMBER" '
    (.projectItems // [] | if type == "array" then . else [] end
      | map(select(((.project.number // .number // "") | tostring) == $project_number))
      | .[0].id) // empty
  ')
  if [ -n "$item_id" ]; then
    printf '%s\n' "$item_id"
    return 0
  fi

  item_id=$(printf '%s' "$issue_json" | jq -r '
    (.projectItems // [] | if type == "array" then . else [] end | .[0].id) // empty
  ')
  if [ -n "$item_id" ]; then
    printf '%s\n' "$item_id"
    return 0
  fi

  items_json=$(gh project item-list "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --limit 1000 --format json 2>/dev/null || true)
  [ -n "$items_json" ] || return 0

  printf '%s' "$items_json" | jq -r --arg issue "$issue" '
    ((.items // .) | if type == "array" then . else [] end
      | map(select(((.content.number // .content.issue.number // .issue.number // .number // "") | tostring) == $issue))
      | .[0].id) // empty
  '
}

project_status_updates_enabled() {
  case "${ENABLE_PROJECT_STATUS_UPDATES:-true}" in
    false|False|FALSE|0|no|No|NO)
      return 1
      ;;
  esac
  return 0
}

normalize_project_option_name() {
  printf '%s' "${1:-}" | jq -Rr '
    gsub("^\\s+|\\s+$"; "")
    | gsub("\\s+"; " ")
    | ascii_downcase
  '
}

issue_project_status_name() {
  local issue_json=$1
  local project_status

  project_status=$(printf '%s' "$issue_json" | jq -r --arg project_number "$PROJECT_NUMBER" '
    (.projectItems // [] | if type == "array" then . else [] end
      | map(select(((.project.number // .number // "") | tostring) == $project_number))
      | .[0].status.name) // empty
  ')
  if [ -n "$project_status" ]; then
    printf '%s\n' "$project_status"
    return 0
  fi

  printf '%s' "$issue_json" | jq -r '
    (.projectItems // [] | if type == "array" then . else [] end | .[0].status.name) // empty
  '
}

move_issue_to_backlog() {
  local issue=$1
  local issue_json=$2
  local target_status=${BACKLOG_VALUE:-Backlog}
  local item_id
  local current_status
  local project_json
  local field_json
  local project_id
  local field_id
  local option_id
  local normalized_current_status
  local normalized_target_status
  local option_row
  local edit_output

  if ! project_status_updates_enabled; then
    return 0
  fi

  item_id=$(issue_project_item_id "$issue" "$issue_json")
  if [ -z "$item_id" ]; then
    echo "⚠️ Issue #$issue is not linked to project #$PROJECT_NUMBER. Continuing without moving it to $target_status." >&2
    return 0
  fi

  current_status=$(issue_project_status_name "$issue_json")
  normalized_current_status=$(normalize_project_option_name "$current_status")
  normalized_target_status=$(normalize_project_option_name "$target_status")
  if [ -n "$normalized_current_status" ] && [ "$normalized_current_status" = "$normalized_target_status" ]; then
    echo "📥 Issue #$issue is already in $target_status." >&2
    return 0
  fi

  project_json=$(gh project view "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --format json 2>&1) || {
    echo "❌ Unable to load project #$PROJECT_NUMBER before moving issue #$issue: $project_json" >&2
    return 1
  }
  project_id=$(printf '%s' "$project_json" | jq -r '.id // .project.id // empty')
  if [ -z "$project_id" ]; then
    echo "❌ Unable to determine project id for project #$PROJECT_NUMBER." >&2
    return 1
  fi

  field_json=$(gh project field-list "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --format json 2>&1) || {
    echo "❌ Unable to load project fields for project #$PROJECT_NUMBER: $field_json" >&2
    return 1
  }
  field_id=$(printf '%s' "$field_json" | jq -r --arg field_name "$STATUS_FIELD_NAME" '
    ((if type == "object" and has("fields") then .fields else . end) | if type == "array" then . else [] end
      | map(select(.name == $field_name))
      | .[0].id) // empty
  ')
  option_row=$(printf '%s' "$field_json" | jq -r --arg field_name "$STATUS_FIELD_NAME" --arg option_name "$target_status" '
    def normalize:
      gsub("^\\s+|\\s+$"; "")
      | gsub("\\s+"; " ")
      | ascii_downcase;
    (((if type == "object" and has("fields") then .fields else . end) | if type == "array" then . else [] end
      | map(select(.name == $field_name))
      | .[0].options // []) as $options
      | (($options | map(select(.name == $option_name)) | .[0])
        // ($options | map(select((.name | normalize) == ($option_name | normalize))) | .[0])
        // empty)
      | [.id // "", .name // ""] | @tsv)
  ')
  if [ -n "$option_row" ]; then
    IFS="$(printf '\t')" read -r option_id _ <<EOF
$option_row
EOF
  else
    option_id=""
  fi

  if [ -z "$field_id" ] || [ -z "$option_id" ]; then
    echo "❌ Unable to resolve the \"$STATUS_FIELD_NAME\" option \"$target_status\" for project #$PROJECT_NUMBER." >&2
    return 1
  fi

  edit_output=$(gh project item-edit --id "$item_id" --field-id "$field_id" --project-id "$project_id" --single-select-option-id "$option_id" 2>&1) || {
    echo "❌ Unable to move issue #$issue to $target_status: $edit_output" >&2
    return 1
  }

  echo "📥 Moved issue #$issue to $target_status." >&2
  return 0
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

ISSUE_NUMBER=${1:-}
REFUSAL_CLASS=${2:-}
REFUSAL_REASONING=${3:-}

if [ -z "$ISSUE_NUMBER" ]; then
  echo "Usage: $0 <issue-number> [refusal-class] [refusal-reasoning]" >&2
  exit 1
fi

echo "📋 Fetching issue #$ISSUE_NUMBER..." >&2
ISSUE_JSON=$(gh issue view "$ISSUE_NUMBER" --comments --json title,body,url,number,projectItems,comments 2>&1)
if echo "$ISSUE_JSON" | grep -q "Could not resolve"; then
  echo "❌ Issue #$ISSUE_NUMBER not found." >&2
  exit 1
fi

ISSUE_TITLE=$(echo "$ISSUE_JSON" | jq -r '.title')
TASK_SLUG=$(task_slug_for_issue "$ISSUE_NUMBER" "$ISSUE_TITLE")
TASK_DIR="$TASKS_DIR/$TASK_SLUG"
PROGRESS_FILE="$TASK_DIR/progress.json"

if [ ! -f "$PROGRESS_FILE" ]; then
  echo "❌ Progress file not found: $PROGRESS_FILE" >&2
  echo "   The issue workflow must be started before refusal can be processed." >&2
  exit 1
fi

mkdir -p "$TASK_DIR"

if [ -z "$REFUSAL_CLASS" ]; then
  REFUSAL_CLASS="underspecified"
fi

if [ -z "$REFUSAL_REASONING" ]; then
  REFUSAL_REASONING="The issue does not appear ready for safe autonomous implementation in its current state."
fi

REFUSAL_CLASS=$(normalize_refusal_class_candidate "$REFUSAL_CLASS")

REFUSAL_COMMENT_ID=$(ensure_refusal_checkpoint "$ISSUE_NUMBER" "$ISSUE_JSON" "$TASK_SLUG" "$TASK_DIR" "$ISSUE_TITLE" "$REFUSAL_CLASS" "$REFUSAL_REASONING")

move_issue_to_backlog "$ISSUE_NUMBER" "$ISSUE_JSON" || {
  echo "⚠️ Refusal for issue #$ISSUE_NUMBER was recorded, but the project status could not be moved to ${BACKLOG_VALUE:-Backlog}." >&2
}

mark_task_progress_refused "$PROGRESS_FILE" "$REFUSAL_CLASS" "$REFUSAL_COMMENT_ID"

printf 'REFUSAL_PROCESSED=1\n'
printf 'ISSUE_NUMBER=%s\n' "$ISSUE_NUMBER"
printf 'TASK_SLUG=%q\n' "$TASK_SLUG"
printf 'REFUSAL_CLASS=%q\n' "$REFUSAL_CLASS"
printf 'REFUSAL_COMMENT_ID=%q\n' "$REFUSAL_COMMENT_ID"
printf 'PROGRESS_FILE=%q\n' "$PROGRESS_FILE"

echo "⏸️ Refused implementation for issue #$ISSUE_NUMBER." >&2
