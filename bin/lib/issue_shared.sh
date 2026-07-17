# bin/lib/issue_shared.sh
# Neutral shared helpers for both GitHub and Linear issue paths.
# First slice: test-write cluster (build_command_list, cleanup_test_result_logs,
# write_test_checkpoint_with_header).
#
# Sourced by bin/grkr AFTER task_progress/refusal_paths and BEFORE
# lib/linear_issue.sh (which sources stages) and lib/github_issue.sh.
# This ordering ensures definitions exist when provider stages call them.
#
# Call-time ambient resolution: functions like checkpoint_marker are defined
# later in bin/grkr (or in scope at runtime); bash resolves names at call time,
# identical to prior behavior when these lived inside grkr after sourcing.
# No redefinition of checkpoint_marker here.

build_command_list() {
  local command_count=0

  if [ -n "${BUILD_COMMAND:-}" ]; then
    printf '%s\n' "$BUILD_COMMAND"
    command_count=$((command_count + 1))
  fi

  if [ -n "${TEST_COMMAND:-}" ]; then
    printf '%s\n' "$TEST_COMMAND"
    command_count=$((command_count + 1))
  fi

  if [ "$command_count" -eq 0 ]; then
    printf '%s\n' "npm test"
  fi
}

cleanup_test_result_logs() {
  local results_file=$1
  local log_file

  [ -f "$results_file" ] || return 0
  while IFS="$(printf '\t')" read -r _ _ log_file; do
    [ -n "$log_file" ] || continue
    rm -f "$log_file"
  done < "$results_file"
}

# Shared body writer for test checkpoint (thin reuse for GitHub + Linear).
# GitHub callers use write_test_checkpoint_file (preserves "Issue #N: title" + gh behavior).
# Linear calls this directly with "Linear issue ID: title" (no # on identifier).
# All sections, marker, excerpts, risks, recommendation identical.
# Extracted per design-linear-test-stage.md to avoid duplication while keeping GitHub ensure_test_checkpoint 100% unchanged.
write_test_checkpoint_with_header() {
  local checkpoint_file=$1
  local header_line=$2
  local task_slug=$3
  local commands_file=$4
  local results_file=$5
  local recommendation=$6
  local overall_result=$7
  local total_commands=$8
  local passed_commands=$9
  local failed_commands=${10}

  {
    printf '%s\n\n' "$(checkpoint_marker test "$task_slug")"
    printf '## Test checkpoint\n\n'
    printf '%s\n\n' "$header_line"

    printf '### Commands run\n\n'
    while IFS= read -r command; do
      [ -n "$command" ] || continue
      printf -- '- `%s`\n' "$command"
    done < "$commands_file"
    printf '\n'

    printf '### Pass/fail summary\n\n'
    printf -- '- Overall result: %s\n' "$overall_result"
    printf -- '- Commands passed: %s/%s\n' "$passed_commands" "$total_commands"
    if [ "$failed_commands" -gt 0 ]; then
      printf -- '- Commands failed: %s\n' "$failed_commands"
    fi
    while IFS="$(printf '\t')" read -r status command _; do
      [ -n "$command" ] || continue
      printf -- '- `%s`: %s\n' "$command" "$status"
    done < "$results_file"
    printf '\n'

    printf '### Output excerpts\n\n'
    while IFS="$(printf '\t')" read -r status command log_file; do
      [ -n "$command" ] || continue
      printf '#### `%s`\n\n' "$command"
      printf '```text\n'
      if [ -s "$log_file" ]; then
        sed -n '1,20p' "$log_file"
        if [ "$(wc -l < "$log_file" | tr -d '[:space:]')" -gt 20 ]; then
          printf '...\n'
        fi
      else
        printf '(no output)\n'
      fi
      printf '```\n\n'
    done < "$results_file"

    printf '### Remaining risks\n\n'
    if [ "$failed_commands" -gt 0 ]; then
      printf -- '- At least one configured verification command failed; inspect the command output above before merging.\n'
    fi
    printf -- '- The checkpoint covers only the configured local verification commands; GitHub-side checks and broader manual validation may still be pending.\n\n'

    printf '### Recommendation\n\n'
    printf '%s\n' "$recommendation"
  } > "$checkpoint_file"
}
