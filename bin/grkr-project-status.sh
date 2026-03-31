#!/bin/bash

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

move_issue_to_project_status() {
  local issue=$1
  local issue_json=$2
  local target_status=$3
  local missing_item_message=$4
  local already_message=$5
  local moved_message=$6
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
    echo "$missing_item_message"
    return 0
  fi

  current_status=$(issue_project_status_name "$issue_json")
  normalized_current_status=$(normalize_project_option_name "$current_status")
  normalized_target_status=$(normalize_project_option_name "$target_status")
  if [ -n "$normalized_current_status" ] && [ "$normalized_current_status" = "$normalized_target_status" ]; then
    echo "$already_message"
    return 0
  fi

  project_json=$(gh project view "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --format json 2>&1) || {
    echo "❌ Unable to load project #$PROJECT_NUMBER before starting issue #$issue: $project_json"
    return 1
  }
  project_id=$(printf '%s' "$project_json" | jq -r '.id // .project.id // empty')
  if [ -z "$project_id" ]; then
    echo "❌ Unable to determine project id for project #$PROJECT_NUMBER."
    return 1
  fi

  field_json=$(gh project field-list "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --format json 2>&1) || {
    echo "❌ Unable to load project fields for project #$PROJECT_NUMBER: $field_json"
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
    echo "❌ Unable to resolve the \"$STATUS_FIELD_NAME\" option \"$target_status\" for project #$PROJECT_NUMBER."
    return 1
  fi

  edit_output=$(gh project item-edit --id "$item_id" --field-id "$field_id" --project-id "$project_id" --single-select-option-id "$option_id" 2>&1) || {
    echo "❌ Unable to move issue #$issue to $target_status: $edit_output"
    return 1
  }

  echo "$moved_message"
}

move_issue_to_in_progress() {
  local issue=$1
  local issue_json=$2
  local target_status=${IN_PROGRESS_VALUE:-In Progress}

  move_issue_to_project_status \
    "$issue" \
    "$issue_json" \
    "$target_status" \
    "⚠️ Issue #$issue is not linked to project #$PROJECT_NUMBER. Continuing without moving it to $target_status." \
    "🚧 Issue #$issue is already in $target_status." \
    "🚧 Moved issue #$issue to $target_status."
}

move_issue_to_done() {
  local issue=$1
  local issue_json=$2
  local target_status=${DONE_VALUE:-Done}

  move_issue_to_project_status \
    "$issue" \
    "$issue_json" \
    "$target_status" \
    "⚠️ Issue #$issue is not linked to project #$PROJECT_NUMBER. Continuing without moving it to $target_status." \
    "✅ Issue #$issue is already in $target_status." \
    "✅ Moved issue #$issue to $target_status."
}

move_issue_to_backlog() {
  local issue=$1
  local issue_json=$2
  local target_status=${BACKLOG_VALUE:-Backlog}

  move_issue_to_project_status \
    "$issue" \
    "$issue_json" \
    "$target_status" \
    "⚠️ Issue #$issue is not linked to project #$PROJECT_NUMBER. Continuing without moving it to $target_status." \
    "📥 Issue #$issue is already in $target_status." \
    "📥 Moved issue #$issue to $target_status."
}
