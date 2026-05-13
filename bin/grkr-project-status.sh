#!/bin/bash

# GitHub Project status management functions backed by Gleam
# This script provides shell functions that route to the Gleam CLI

# Determine the project root for running Gleam commands
_grkr_project_root() {
  echo "${GRKR_GLEAM_PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/..}"
}

# Run the Gleam project status CLI
_grkr_run_cli() {
  local project_root
  project_root=$(_grkr_project_root)

  if [ -f "$project_root/gleam.toml" ]; then
    (cd "$project_root" && gleam run -m grkr/project_status_cli -- "$@")
    return $?
  fi

  # Fallback if Gleam project is not available (for development)
  case "${1:-}" in
    check-enabled)
      case "${ENABLE_PROJECT_STATUS_UPDATES:-true}" in
        false|False|FALSE|0|no|No|NO) echo "disabled" ;;
        *) echo "enabled" ;;
      esac
      ;;
    normalize)
      echo "${2:-}" | jq -Rr 'gsub("^\\s+|\\s+$"; "") | gsub("\\s+"; " ") | ascii_downcase'
      ;;
    *)
      return 1
      ;;
  esac
}

project_status_updates_enabled() {
  local result
  result=$(_grkr_run_cli check-enabled)
  case "$result" in
    enabled) return 0 ;;
    *) return 1 ;;
  esac
}

normalize_project_option_name() {
  _grkr_run_cli normalize "${1:-}"
}

issue_project_status_name() {
  local issue_json=$1
  local project_number=${PROJECT_NUMBER:-}

  _grkr_run_cli extract-status-name "$issue_json" "$project_number"
}

issue_project_item_id() {
  local issue=$1
  local issue_json=$2
  local item_id
  local items_json

  # First try to extract from issue JSON
  item_id=$(_grkr_run_cli extract-item-id "$issue_json" "${PROJECT_NUMBER:-}")

  if [ -n "$item_id" ]; then
    printf '%s\n' "$item_id"
    return 0
  fi

  # Fallback: query item list via gh and search
  items_json=$(gh project item-list "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --limit 1000 --format json 2>/dev/null || true)
  [ -n "$items_json" ] || return 0

  _grkr_run_cli find-item-id "$items_json" "$issue"
}

move_issue_to_project_status() {
  local issue=$1
  local issue_json=$2
  local target_status=$3
  local missing_item_message=$4
  local already_message=$5
  local moved_message=$6
  local project_json
  local field_json
  local edit_output
  local item_id
  local current_status
  local normalized_current_status
  local normalized_target_status
  local project_id
  local option_row
  local field_id
  local option_id

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

  # Load project data via gh
  project_json=$(gh project view "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --format json 2>&1) || {
    echo "❌ Unable to load project #$PROJECT_NUMBER before starting issue #$issue: $project_json"
    return 1
  }

  project_id=$(_grkr_run_cli project-id "$project_json")
  if [ -z "$project_id" ]; then
    echo "❌ Unable to determine project id for project #$PROJECT_NUMBER."
    return 1
  fi

  field_json=$(gh project field-list "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --format json 2>&1) || {
    echo "❌ Unable to load project fields for project #$PROJECT_NUMBER: $field_json"
    return 1
  }

  option_row=$(_grkr_run_cli resolve-option "$field_json" "${STATUS_FIELD_NAME:-Status}" "$target_status")
  if [ -n "$option_row" ]; then
    IFS=$'\t' read -r field_id option_id <<<"$option_row"
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
  return 0
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
