#!/bin/bash
# Thin Gleam project_status host (GitHub-only v2; gh+messages in sh). <=100 LOC.
# Per AGENTS.md: preserve bin/ conventions for sourced fn lib (no side effects on source, env-driven, gh adapter only).
# Delegates planning/extraction/normalization/resolution to grkr/project_status_cli; keeps gh fetches + edits + UX messages in sh.

_grkr_run_cli() {
  local project_root=${GRKR_GLEAM_PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/..}
  (cd "$project_root" && gleam run --no-print-progress -m grkr/project_status_cli -- "$@")
}

project_status_updates_enabled() {
  local r; r=$(_grkr_run_cli check-enabled 2>/dev/null || echo disabled)
  [ "$r" = enabled ]
}

normalize_project_option_name() { _grkr_run_cli normalize "${1:-}"; }

issue_project_status_name() { _grkr_run_cli extract-status-name "${1:-}" "${PROJECT_NUMBER:-}"; }

issue_project_item_id() {
  local issue=$1 issue_json=$2 pnum=${PROJECT_NUMBER:-}
  local id; id=$(_grkr_run_cli extract-item-id "$issue_json" "$pnum" 2>/dev/null || true)
  [ -n "$id" ] && { echo "$id"; return 0; }
  local items; items=$(gh project item-list "$pnum" --owner "${PROJECT_OWNER:-}" --limit 1000 --format json 2>/dev/null || true)
  [ -n "$items" ] || { echo ""; return 0; }
  _grkr_run_cli find-item-id "$items" "$issue"
}

move_issue_to_project_status() {
  local issue=$1 issue_json=$2 target=$3 miss=$4 already=$5 moved=$6
  project_status_updates_enabled || return 0
  local item; item=$(issue_project_item_id "$issue" "$issue_json")
  [ -z "$item" ] && { echo "$miss"; return 0; }
  local cur; cur=$(issue_project_status_name "$issue_json")
  if [ -n "$cur" ]; then
    local nc nt; nc=$(normalize_project_option_name "$cur"); nt=$(normalize_project_option_name "$target")
    [ "$nc" = "$nt" ] && { echo "$already"; return 0; }
  fi
  local pjson fjson ijson
  pjson=$(gh project view "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --format json 2>&1) || { echo "❌ Unable to load project #$PROJECT_NUMBER before starting issue #$issue: $pjson" >&2; return 1; }
  fjson=$(gh project field-list "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --format json 2>&1) || { echo "❌ Unable to load project fields for project #$PROJECT_NUMBER: $fjson" >&2; return 1; }
  ijson=$(gh project item-list "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --limit 1000 --format json 2>/dev/null || true)
  local plan
  if [ -n "$ijson" ]; then
    plan=$(_grkr_run_cli plan-move-with-lookup "$issue_json" "$pjson" "$fjson" "$ijson" "$target" 2>/dev/null || echo "no_action\tresolution_failed")
  else
    plan=$(_grkr_run_cli plan-move "$issue_json" "$pjson" "$fjson" "$target" 2>/dev/null || echo "no_action\tresolution_failed")
  fi
  case "$plan" in
    move$'\t'*)
      local _m iid fid oid pid _o; IFS=$'\t' read -r _m iid fid oid pid _o <<<"$plan"
      local eout; eout=$(gh project item-edit --id "$iid" --field-id "$fid" --project-id "$pid" --single-select-option-id "$oid" 2>&1) || { echo "❌ Unable to move issue #$issue to $target: $eout" >&2; return 1; }
      echo "$moved"
      ;;
    no_action$'\t'item_missing) echo "$miss" ;;
    no_action$'\t'already) echo "$already" ;;
    no_action$'\t'disabled) return 0 ;;
    *) echo "❌ Unable to resolve the \"$STATUS_FIELD_NAME\" option \"$target\" for project #$PROJECT_NUMBER." >&2; return 1 ;;
  esac
}

move_issue_to_in_progress() {
  local issue=$1 issue_json=$2 target=${IN_PROGRESS_VALUE:-In Progress}
  move_issue_to_project_status "$issue" "$issue_json" "$target" \
    "⚠️ Issue #$issue is not linked to project #$PROJECT_NUMBER. Continuing without moving it to $target." \
    "🚧 Issue #$issue is already in $target." "🚧 Moved issue #$issue to $target."
}

move_issue_to_done() {
  local issue=$1 issue_json=$2 target=${DONE_VALUE:-Done}
  move_issue_to_project_status "$issue" "$issue_json" "$target" \
    "⚠️ Issue #$issue is not linked to project #$PROJECT_NUMBER. Continuing without moving it to $target." \
    "✅ Issue #$issue is already in $target." "✅ Moved issue #$issue to $target."
}

move_issue_to_backlog() {
  local issue=$1 issue_json=$2 target=${BACKLOG_VALUE:-Backlog}
  move_issue_to_project_status "$issue" "$issue_json" "$target" \
    "⚠️ Issue #$issue is not linked to project #$PROJECT_NUMBER. Continuing without moving it to $target." \
    "📥 Issue #$issue is already in $target." "📥 Moved issue #$issue to $target."
}
