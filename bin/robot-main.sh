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
  PHASE_BACKOFF_FILE="$STATE_DIR/phase_backoff.json"
  PROCESSED_COMMENTS_FILE="$STATE_DIR/processed_comments.json"
  PROJECT_CACHE_FILE="$STATE_DIR/project_cache.json"
  PR_CACHE_FILE="$STATE_DIR/pr_cache.json"
  LAST_COMMENT_SCAN_FILE="$STATE_DIR/last_comment_scan_at"
  MAIN_LOG_FILE="$LOGS_DIR/main.log"
  LOOP_LOG_FILE="$LOGS_DIR/loop.log"
  COMPLETED_WORKTREE_TTL_SECS=${COMPLETED_WORKTREE_TTL_SECS:-3600}
  FAILED_WORKTREE_TTL_SECS=${FAILED_WORKTREE_TTL_SECS:-86400}
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
  [ -f "$PHASE_BACKOFF_FILE" ] || printf '{}\n' > "$PHASE_BACKOFF_FILE"
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

file_mtime_epoch() {
  local file=$1

  if stat -c %Y "$file" >/dev/null 2>&1; then
    stat -c %Y "$file"
  else
    stat -f %m "$file"
  fi
}

phase_backoff_delay_loops() {
  local attempt=$1
  local loop_interval=${LOOP_INTERVAL_SECS:-20}
  local cap_loops

  if [ "$loop_interval" -gt 0 ]; then
    cap_loops=$((3600 / loop_interval))
  else
    cap_loops=3600
  fi
  [ "$cap_loops" -gt 0 ] || cap_loops=1

  case "$attempt" in
    1) printf '%s\n' 1 ;;
    2) printf '%s\n' 3 ;;
    3) printf '%s\n' 10 ;;
    *) printf '%s\n' "$cap_loops" ;;
  esac
}

phase_backoff_lookup() {
  local phase=$1
  local entry

  entry=$(jq -c --arg phase "$phase" '.[$phase] // empty' "$PHASE_BACKOFF_FILE" 2>/dev/null) || return 1
  [ -n "$entry" ] || return 1
  printf '%s\n' "$entry"
}

phase_backoff_active() {
  local phase=$1
  local entry
  local retry_after_loop
  local retry_after_at

  entry=$(phase_backoff_lookup "$phase") || return 1
  retry_after_loop=$(printf '%s' "$entry" | jq -r '.retry_after_loop // empty')
  retry_after_at=$(printf '%s' "$entry" | jq -r '.retry_after_at // empty')

  if [ -n "$retry_after_loop" ] && [ "$LOOP_COUNT" -lt "$retry_after_loop" ]; then
    return 0
  fi

  if [ -n "$retry_after_loop" ]; then
    return 1
  fi

  if [ -n "$retry_after_at" ] && [ "$(date +%s)" -lt "$retry_after_at" ]; then
    return 0
  fi

  return 1
}

phase_backoff_record() {
  local phase=$1
  local exit_code=$2
  local failure_class=$3
  local entry
  local attempt=1
  local delay_loops
  local delay_secs
  local retry_after_loop
  local retry_after_at
  local now_epoch
  local now
  local tmp_file

  entry=$(phase_backoff_lookup "$phase" || true)
  if [ -n "$entry" ]; then
    attempt=$(printf '%s' "$entry" | jq -r '.attempt // 0')
    attempt=$((attempt + 1))
  fi

  delay_loops=$(phase_backoff_delay_loops "$attempt")
  case "$failure_class" in
    policy|config)
      if [ "${LOOP_INTERVAL_SECS:-20}" -gt 0 ]; then
        delay_loops=$((3600 / LOOP_INTERVAL_SECS))
      else
        delay_loops=3600
      fi
      ;;
  esac
  [ "$delay_loops" -gt 0 ] || delay_loops=1

  delay_secs=$((delay_loops * ${LOOP_INTERVAL_SECS:-20}))
  if [ "$delay_secs" -le 0 ]; then
    delay_secs=$delay_loops
  fi

  retry_after_loop=$((LOOP_COUNT + delay_loops))
  now_epoch=$(date +%s)
  retry_after_at=$((now_epoch + delay_secs))
  now=$(timestamp_utc)
  tmp_file=$(mktemp "${TMPDIR:-/tmp}/grkr-phase-backoff.XXXXXX")
  jq \
    --arg phase "$phase" \
    --arg failure_class "$failure_class" \
    --arg updated_at "$now" \
    --argjson attempt "$attempt" \
    --argjson last_exit_code "$exit_code" \
    --argjson retry_after_loop "$retry_after_loop" \
    --argjson retry_after_at "$retry_after_at" \
    --argjson last_failed_loop "$LOOP_COUNT" '
    .[$phase] = {
      attempt: $attempt,
      failure_class: $failure_class,
      last_exit_code: $last_exit_code,
      retry_after_loop: $retry_after_loop,
      retry_after_at: $retry_after_at,
      last_failed_loop: $last_failed_loop,
      updated_at: $updated_at
    }
  ' "$PHASE_BACKOFF_FILE" > "$tmp_file"
  mv "$tmp_file" "$PHASE_BACKOFF_FILE"
}

phase_backoff_clear() {
  local phase=$1
  local tmp_file

  tmp_file=$(mktemp "${TMPDIR:-/tmp}/grkr-phase-backoff.XXXXXX")
  jq --arg phase "$phase" 'del(.[$phase])' "$PHASE_BACKOFF_FILE" > "$tmp_file"
  mv "$tmp_file" "$PHASE_BACKOFF_FILE"
}

compact_processed_comment_state() {
  local tmp_file

  if ! jq -e 'type == "array"' "$PROCESSED_COMMENTS_FILE" >/dev/null 2>&1; then
    return 0
  fi

  tmp_file=$(mktemp "${TMPDIR:-/tmp}/grkr-processed-comments.XXXXXX")
  jq 'unique' "$PROCESSED_COMMENTS_FILE" > "$tmp_file"
  mv "$tmp_file" "$PROCESSED_COMMENTS_FILE"
}

cleanup_task_worktrees() {
  local now_epoch
  local worktree_dir
  local task_slug
  local progress_file
  local status
  local progress_mtime
  local worktree_mtime
  local age_secs
  local removed_refused=0
  local removed_completed=0
  local removed_failed=0
  local removed_orphaned=0
  local removed_job_logs=0
  local issue_number
  local job_log

  now_epoch=$(date +%s)
  while IFS= read -r -d '' worktree_dir; do
    [ -d "$worktree_dir" ] || continue
    task_slug=$(basename "$worktree_dir")
    progress_file="$TASKS_DIR/$task_slug/progress.json"

    if [ ! -f "$progress_file" ]; then
      worktree_mtime=$(file_mtime_epoch "$worktree_dir")
      age_secs=$((now_epoch - worktree_mtime))
      if [ "$age_secs" -ge "$FAILED_WORKTREE_TTL_SECS" ]; then
        rm -rf "$worktree_dir"
        removed_orphaned=$((removed_orphaned + 1))
      fi
      continue
    fi

    status=$(jq -r '.status // empty' "$progress_file" 2>/dev/null || true)
    progress_mtime=$(file_mtime_epoch "$progress_file")
    age_secs=$((now_epoch - progress_mtime))

    case "$status" in
      refused)
        rm -rf "$worktree_dir"
        removed_refused=$((removed_refused + 1))
        ;;
      complete)
        if [ "$age_secs" -ge "$COMPLETED_WORKTREE_TTL_SECS" ]; then
          rm -rf "$worktree_dir"
          removed_completed=$((removed_completed + 1))
        fi
        ;;
      failed)
        if [ "$age_secs" -ge "$FAILED_WORKTREE_TTL_SECS" ]; then
          rm -rf "$worktree_dir"
          removed_failed=$((removed_failed + 1))
        fi
        ;;
    esac

    if [ ! -d "$worktree_dir" ]; then
      issue_number=$(jq -r '.issue_number // empty' "$progress_file" 2>/dev/null || true)
      if [ -n "$issue_number" ]; then
        job_log=$(job_log_file "issue:${issue_number}:execution")
        if [ -f "$job_log" ]; then
          rm -f "$job_log"
          removed_job_logs=$((removed_job_logs + 1))
        fi
      fi
    fi
  done < <(find "$WORKTREES_DIR" -mindepth 1 -maxdepth 1 -type d -print0)

  compact_processed_comment_state
  log_info "cleanup_stale_worktrees" "-" "repo/$REPO" "purged_completed_worktrees=$removed_completed purged_failed_worktrees=$removed_failed purged_refused_worktrees=$removed_refused purged_orphaned_worktrees=$removed_orphaned purged_job_logs=$removed_job_logs"
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
    return "${GRKR_FAIL_PHASE_EXIT_CODE:-64}"
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

phase_pick_issue_impl() {
  local active_execution_count
  local selection_file
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

  log_info "pick_and_schedule_issue_execution" "$JOB_KEY" "issue/$ISSUE_NUMBER" "scheduled_jobs=0 selected_issue=$ISSUE_NUMBER task_slug=$TASK_SLUG scheduling=pending"
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
  cleanup_task_worktrees
}

run_phase() {
  local phase=$1
  local status=0
  local failure_class=transient
  local backoff_entry

  log_info "$phase" "-" "repo/$REPO" "phase_started=true"
  if phase_backoff_active "$phase"; then
    backoff_entry=$(phase_backoff_lookup "$phase" || true)
    if [ -n "$backoff_entry" ]; then
      log_info "$phase" "-" "repo/$REPO" "backoff_active=true $(printf '%s' "$backoff_entry" | jq -r 'to_entries | map("\(.key)=\(.value|tostring)") | join(" ")')"
    else
      log_info "$phase" "-" "repo/$REPO" "backoff_active=true"
    fi
    return 0
  fi

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
    phase_backoff_clear "$phase"
    log_info "$phase" "-" "repo/$REPO" "phase_finished=true"
  else
    case "$status" in
      77) failure_class=policy ;;
      78) failure_class=config ;;
      *) failure_class=transient ;;
    esac
    phase_backoff_record "$phase" "$status" "$failure_class"
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
