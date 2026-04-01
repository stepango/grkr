#!/bin/bash
set -u
set -o pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$SCRIPT_DIR/doctor.sh"

doctor_init

load_runtime_config() {
  if [ -f "$GRKR_CONFIG_FILE" ]; then
    . "$GRKR_CONFIG_FILE"
  fi

  REPO=${REPO:-unknown/unknown}
  MAIN_BRANCH=${MAIN_BRANCH:-main}
  LOOP_INTERVAL_SECS=${LOOP_INTERVAL_SECS:-20}

  GRKR_DIR="$GRKR_ROOT/.grkr"
  STATE_DIR="$GRKR_DIR/state"
  LOCKS_DIR="$GRKR_DIR/locks"
  LOGS_DIR="$GRKR_DIR/logs"
  JOB_LOGS_DIR="$LOGS_DIR/jobs"
  WORKTREES_DIR="$GRKR_DIR/worktrees"
  TASKS_DIR="$GRKR_DIR/tasks"
  ACTIVE_JOBS_FILE="$STATE_DIR/active_jobs.json"
  PROCESSED_COMMENTS_FILE="$STATE_DIR/processed_comments.json"
  PROJECT_CACHE_FILE="$STATE_DIR/project_cache.json"
  PR_CACHE_FILE="$STATE_DIR/pr_cache.json"
  LAST_COMMENT_SCAN_FILE="$STATE_DIR/last_comment_scan_at"
  MAIN_LOG_FILE="$LOGS_DIR/main.log"
  LOOP_LOG_FILE="$LOGS_DIR/loop.log"
  VALIDATION_OK=0
}

escape_log_value() {
  local value=${1-}
  value=${value//$'\n'/ }
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  printf '%s' "$value"
}

job_log_file() {
  local job_key=$1
  local file_name
  file_name=$(printf '%s' "$job_key" | sed 's/[:\/]/-/g')
  printf '%s/%s.log\n' "$JOB_LOGS_DIR" "$file_name"
}

log_event() {
  local level=$1
  local phase=${2:--}
  local job_key=${3:--}
  local entity=${4:--}
  local message=${5-}
  local line

  line="$(date -u +"%Y-%m-%dT%H:%M:%SZ") $level phase=$phase job=$job_key entity=$entity msg=\"$(escape_log_value "$message")\""
  printf '%s\n' "$line"
  printf '%s\n' "$line" >> "$MAIN_LOG_FILE"
  printf '%s\n' "$line" >> "$LOOP_LOG_FILE"
  if [ "$job_key" != "-" ]; then
    printf '%s\n' "$line" >> "$(job_log_file "$job_key")"
  fi
}

log_info() {
  log_event "INFO" "$@"
}

log_warn() {
  log_event "WARN" "$@"
}

log_error() {
  log_event "ERROR" "$@"
}

ensure_runtime_layout() {
  mkdir -p "$STATE_DIR" "$LOCKS_DIR" "$LOGS_DIR" "$JOB_LOGS_DIR" "$WORKTREES_DIR" "$TASKS_DIR"
  touch "$MAIN_LOG_FILE" "$LOOP_LOG_FILE" "$LOCKS_DIR/main.lock" "$LOCKS_DIR/comments.lock" "$LOCKS_DIR/prs.lock" "$LOCKS_DIR/issues.lock"
  [ -f "$ACTIVE_JOBS_FILE" ] || printf '{}\n' > "$ACTIVE_JOBS_FILE"
  [ -f "$PROCESSED_COMMENTS_FILE" ] || printf '[]\n' > "$PROCESSED_COMMENTS_FILE"
  [ -f "$PROJECT_CACHE_FILE" ] || printf '{}\n' > "$PROJECT_CACHE_FILE"
  [ -f "$PR_CACHE_FILE" ] || printf '{}\n' > "$PR_CACHE_FILE"
  [ -f "$LAST_COMMENT_SCAN_FILE" ] || : > "$LAST_COMMENT_SCAN_FILE"
}

refresh_validation() {
  local output
  local status=0

  output=$(doctor_validate 2>&1) || status=$?
  if [ -n "$output" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      if [ "$status" -eq 0 ]; then
        log_info "startup_validation" "-" "repo/$REPO" "$line"
      else
        log_error "startup_validation" "-" "repo/$REPO" "$line"
      fi
    done <<EOF
$output
EOF
  fi

  if [ "$status" -eq 0 ]; then
    VALIDATION_OK=1
  else
    VALIDATION_OK=0
    log_warn "startup_validation" "-" "repo/$REPO" "mutating_operations_disabled=true"
  fi
}

job_key_lock_name() {
  local job_key=$1

  case "$job_key" in
    pr:*:*)
      printf 'pr-%s\n' "$(printf '%s' "$job_key" | cut -d: -f2)"
      ;;
    issue:*:*)
      printf 'issue-%s\n' "$(printf '%s' "$job_key" | cut -d: -f2)"
      ;;
    comment:*)
      printf 'comment-%s\n' "$(printf '%s' "$job_key" | cut -d: -f2)"
      ;;
    *)
      return 1
      ;;
  esac
}

remove_active_job() {
  local job_key=$1
  local tmp_file

  tmp_file=$(mktemp "${TMPDIR:-/tmp}/grkr-active-jobs.XXXXXX")
  if jq --arg key "$job_key" 'del(.[$key])' "$ACTIVE_JOBS_FILE" > "$tmp_file"; then
    mv "$tmp_file" "$ACTIVE_JOBS_FILE"
    return 0
  fi

  rm -f "$tmp_file"
  return 1
}

record_active_job() {
  local job_key=$1
  local pid=$2
  local entity_type=$3
  local entity_id=$4
  local lock_name=$5
  local task_slug=$6
  local project_item_id=${7:-}
  local tmp_file

  tmp_file=$(mktemp "${TMPDIR:-/tmp}/grkr-active-jobs.XXXXXX")
  jq \
    --arg key "$job_key" \
    --argjson pid "$pid" \
    --arg entity_type "$entity_type" \
    --arg entity_id "$entity_id" \
    --arg lock_name "$lock_name" \
    --arg task_slug "$task_slug" \
    --arg project_item_id "$project_item_id" \
    --arg started_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" '
    .[$key] = {
      pid: $pid,
      entity_type: $entity_type,
      entity_id: $entity_id,
      lock_name: $lock_name,
      task_slug: $task_slug,
      started_at: $started_at
    }
    | if $project_item_id == "" then
        .
      else
        .[$key].project_item_id = $project_item_id
      end
  ' "$ACTIVE_JOBS_FILE" > "$tmp_file" && mv "$tmp_file" "$ACTIVE_JOBS_FILE"
}

recover_dead_jobs() {
  local phase=$1
  local entries
  local stale_found=0

  entries=$(jq -c 'to_entries[]?' "$ACTIVE_JOBS_FILE" 2>/dev/null) || {
    log_error "$phase" "-" "repo/$REPO" "active_jobs_state_invalid=true"
    return 1
  }

  [ -n "$entries" ] || return 0

  while IFS= read -r entry; do
    local job_key
    local pid
    local entity_type
    local entity_id
    local lock_name

    [ -n "$entry" ] || continue
    job_key=$(printf '%s' "$entry" | jq -r '.key')
    pid=$(printf '%s' "$entry" | jq -r '.value.pid // empty')
    entity_type=$(printf '%s' "$entry" | jq -r '.value.entity_type // "job"')
    entity_id=$(printf '%s' "$entry" | jq -r '.value.entity_id // "unknown"')
    lock_name=$(printf '%s' "$entry" | jq -r '.value.lock_name // empty')

    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      continue
    fi

    stale_found=1
    if [ -z "$lock_name" ]; then
      lock_name=$(job_key_lock_name "$job_key" 2>/dev/null || true)
    fi
    if [ -n "$lock_name" ]; then
      rm -f "$LOCKS_DIR/$lock_name.lock"
    fi
    remove_active_job "$job_key" || {
      log_error "$phase" "$job_key" "$entity_type/$entity_id" "active_jobs_update_failed=true"
      continue
    }
    log_warn "$phase" "$job_key" "$entity_type/$entity_id" "stale_job pid=${pid:-missing} recovered=true"
  done <<EOF
$entries
EOF

  if [ "$stale_found" -eq 0 ]; then
    log_info "$phase" "-" "repo/$REPO" "stale_jobs=0"
  fi
}

purge_stale_lock_files() {
  local purged=0
  local lock_file

  if ! jq -e '.' "$ACTIVE_JOBS_FILE" >/dev/null 2>&1; then
    log_error "cleanup_stale_worktrees" "-" "repo/$REPO" "active_jobs_state_invalid=true"
    return 1
  fi

  while IFS= read -r lock_file; do
    [ -n "$lock_file" ] || continue
    if jq -e --arg lock_name "$(basename "$lock_file" .lock)" 'to_entries[]? | select(.value.lock_name == $lock_name)' "$ACTIVE_JOBS_FILE" >/dev/null 2>&1; then
      continue
    fi
    if (
      flock -n 9 || exit 1
    ) 9>"$lock_file"; then
      rm -f "$lock_file"
      purged=$((purged + 1))
    fi
  done < <(find "$LOCKS_DIR" -maxdepth 1 -type f \( -name 'pr-*.lock' -o -name 'issue-*.lock' -o -name 'comment-*.lock' \) | sort)

  log_info "cleanup_stale_worktrees" "-" "repo/$REPO" "purged_stale_locks=$purged"
}

active_issue_execution_count() {
  jq '[keys[]? | select(test("^issue:[0-9]+:execution$"))] | length' "$ACTIVE_JOBS_FILE"
}

phase_should_fail() {
  case ",${GRKR_FAIL_PHASES:-}," in
    *,"$1",*)
      return 0
      ;;
  esac
  return 1
}

run_phase_command() {
  (
    set -e
    "$@"
  )
  local status=$?

  return "$status"
}

run_phase_with_lock() {
  local phase=$1
  local lock_name=$2
  shift 2

  if phase_should_fail "$phase"; then
    return 64
  fi

  if [ "$VALIDATION_OK" -ne 1 ]; then
    run_phase_command "$@"
    return $?
  fi

  (
    set -e
    flock -n 9 || exit 75
    "$@"
  ) 9>"$LOCKS_DIR/$lock_name.lock"
  local status=$?

  case "$status" in
    0)
      return 0
      ;;
    75)
      log_warn "$phase" "-" "repo/$REPO" "lock_busy=$lock_name"
      return 0
      ;;
    *)
      return "$status"
      ;;
  esac
}

phase_sync_main_impl() {
  local status=0

  if [ "$VALIDATION_OK" -ne 1 ]; then
    log_warn "sync_main" "-" "repo/$REPO" "skipped validation_ok=false"
    return 0
  fi

  "$SCRIPT_DIR/worker-sync-main.sh" || status=$?

  case "$status" in
    0)
      log_info "sync_main" "-" "repo/$REPO" "synced_branch=$MAIN_BRANCH"
      return 0
      ;;
    75)
      log_warn "sync_main" "-" "repo/$REPO" "lock_busy=main"
      return 0
      ;;
    *)
      return "$status"
      ;;
  esac
}

phase_scan_prs_impl() {
  log_info "scan_and_schedule_pr_conflicts" "-" "repo/$REPO" "scheduled_jobs=0 worker_logic=pending"
}

phase_scan_comments_impl() {
  log_info "scan_and_schedule_comment_commands" "-" "repo/$REPO" "scheduled_jobs=0 worker_logic=pending"
}

schedule_issue_execution_job() {
  local issue_number=$1
  local job_key=$2
  local task_slug=$3
  local project_item_id=$4
  local lock_name
  local lock_file
  local job_log
  local pid

  lock_name=$(job_key_lock_name "$job_key")
  lock_file="$LOCKS_DIR/$lock_name.lock"
  job_log=$(job_log_file "$job_key")
  : > "$job_log"

  (
    flock -n 9 || exit 75
    "$SCRIPT_DIR/grkr" --issue "$issue_number"
  ) 9>"$lock_file" >>"$job_log" 2>&1 &
  pid=$!

  record_active_job "$job_key" "$pid" "issue" "$issue_number" "$lock_name" "$task_slug" "$project_item_id"
  log_info "pick_and_schedule_issue_execution" "$job_key" "issue/$issue_number" "scheduled_jobs=1 selected_issue=$issue_number task_slug=$task_slug"
}

phase_pick_issue_impl() {
  local active_execution_count
  local selection_file
  local project_item_id
  local status=0

  if [ "$VALIDATION_OK" -ne 1 ]; then
    log_warn "pick_and_schedule_issue_execution" "-" "repo/$REPO" "skipped validation_ok=false"
    return 0
  fi

  active_execution_count=$(active_issue_execution_count) || {
    log_error "pick_and_schedule_issue_execution" "-" "repo/$REPO" "active_jobs_state_invalid=true"
    return 1
  }

  if [ "$active_execution_count" -gt 0 ]; then
    log_info "pick_and_schedule_issue_execution" "-" "repo/$REPO" "scheduled_jobs=0 active_issue_execution=true"
    return 0
  fi

  selection_file=$(mktemp "${TMPDIR:-/tmp}/grkr-pick-issue.XXXXXX")
  "$SCRIPT_DIR/worker-pick-issue.sh" > "$selection_file" || status=$?

  if [ "$status" -ne 0 ]; then
    rm -f "$selection_file"
    return "$status"
  fi

  . "$selection_file"
  rm -f "$selection_file"

  if [ "${SELECTED:-0}" != "1" ]; then
    log_info "pick_and_schedule_issue_execution" "-" "repo/$REPO" "scheduled_jobs=0 candidate=none"
    return 0
  fi

  project_item_id=${PROJECT_ITEM_ID:-}
  schedule_issue_execution_job "$ISSUE_NUMBER" "$JOB_KEY" "$TASK_SLUG" "$project_item_id"
}

phase_reap_impl() {
  recover_dead_jobs "reap_finished_jobs"
}

phase_cleanup_impl() {
  if [ $((LOOP_COUNT % 10)) -ne 0 ]; then
    log_info "cleanup_stale_worktrees" "-" "repo/$REPO" "cleanup_due=false"
    return 0
  fi

  purge_stale_lock_files
}

run_phase() {
  local phase=$1
  local status=0

  log_info "$phase" "-" "repo/$REPO" "phase_started=true"
  case "$phase" in
    sync_main)
      run_phase_command phase_sync_main_impl || status=$?
      ;;
    scan_and_schedule_pr_conflicts)
      run_phase_with_lock "$phase" "prs" phase_scan_prs_impl || status=$?
      ;;
    scan_and_schedule_comment_commands)
      run_phase_with_lock "$phase" "comments" phase_scan_comments_impl || status=$?
      ;;
    pick_and_schedule_issue_execution)
      run_phase_with_lock "$phase" "issues" phase_pick_issue_impl || status=$?
      ;;
    reap_finished_jobs)
      run_phase_command phase_reap_impl || status=$?
      ;;
    cleanup_stale_worktrees)
      run_phase_command phase_cleanup_impl || status=$?
      ;;
    *)
      status=1
      ;;
  esac

  if [ "$status" -eq 0 ]; then
    log_info "$phase" "-" "repo/$REPO" "phase_finished=true"
  else
    log_error "$phase" "-" "repo/$REPO" "phase_failed exit_code=$status"
  fi
}

sleep_remaining_time() {
  local tick_started_at=$1
  local remaining
  local now

  now=$(date +%s)
  remaining=$((LOOP_INTERVAL_SECS - (now - tick_started_at)))
  if [ "$remaining" -le 0 ]; then
    log_info "sleep_until_next_tick" "-" "repo/$REPO" "sleep_secs=0"
    return 0
  fi

  log_info "sleep_until_next_tick" "-" "repo/$REPO" "sleep_secs=$remaining"
  sleep "$remaining"
}

main() {
  local max_ticks=${GRKR_MAX_TICKS:-}

  load_runtime_config
  ensure_runtime_layout
  log_info "supervisor" "-" "repo/$REPO" "starting interval_secs=$LOOP_INTERVAL_SECS"

  LOOP_COUNT=0
  while true; do
    local tick_started_at

    LOOP_COUNT=$((LOOP_COUNT + 1))
    tick_started_at=$(date +%s)

    refresh_validation
    recover_dead_jobs "loop_recovery" || true
    run_phase "sync_main"
    run_phase "scan_and_schedule_pr_conflicts"
    run_phase "scan_and_schedule_comment_commands"
    run_phase "pick_and_schedule_issue_execution"
    run_phase "reap_finished_jobs"
    run_phase "cleanup_stale_worktrees"
    sleep_remaining_time "$tick_started_at"

    if [ -n "$max_ticks" ] && [ "$LOOP_COUNT" -ge "$max_ticks" ]; then
      log_info "supervisor" "-" "repo/$REPO" "stopping max_ticks=$max_ticks"
      break
    fi
  done
}

main "$@"
