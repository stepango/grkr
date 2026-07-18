# bin/lib/issue_shared.sh
# Neutral shared helpers for both GitHub and Linear issue paths.
# Slice 1: test-write cluster (build_command_list, cleanup_test_result_logs,
# write_test_checkpoint_with_header).
# Slice 2: line-limit + ensure_publishable_file_sizes
#   (collect_file_line_limit_violations, check_file_line_limit,
#   ensure_publishable_file_sizes).
# Slice 3: run_codex_prompt (codex exec + persist_task_log_output bridge).
# Slice 4: run_progress_cli + checkpoint_marker (progress CLI bridge + marker fallback).
#
# Sourced by bin/grkr AFTER task_progress/refusal_paths and BEFORE
# lib/linear_issue.sh (which sources stages) and lib/github_issue.sh.
# This ordering ensures definitions exist when provider stages call them.
#
# Ambient call-time deps (resolved in grkr / grkr-issue-workflow / templates
# at call time; bash name resolution): git_in_issue_context,
# stage_relevant_issue_files, persist_task_log_output (from grkr-issue-workflow.sh),
# write_line_limit_fix_prompt (grkr-templates.sh), MAX_FILE_LINES,
# CURRENT_ISSUE_WORKTREE. No re-exports; exact prior behavior.
#
# SCRIPT_DIR and optional GRKR_GLEAM_PROJECT_ROOT are ambient from the
# caller (bin/grkr sets SCRIPT_DIR before sourcing issue_shared); bash resolves
# at call time. run_progress_cli prefers gleam run -m grkr/progress/cli when
# gleam.toml present under project root (or GRKR_GLEAM_PROJECT_ROOT override);
# otherwise falls back to inline marker for "marker" subcommand or errors.
# checkpoint_marker is a thin convenience over the marker path.

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

collect_file_line_limit_violations() {
  local file
  local line_count

  while IFS= read -r -d '' file; do
    [ -n "$file" ] || continue
    line_count=$(git_in_issue_context show ":$file" | wc -l | tr -d '[:space:]')
    if [ "$line_count" -gt "$MAX_FILE_LINES" ]; then
      printf '%s\t%s\n' "$file" "$line_count"
    fi
  done < <(git_in_issue_context diff --cached --name-only --diff-filter=ACMR -z)
}

check_file_line_limit() {
  local file
  local line_count
  local violations=0

  while IFS="$(printf '\t')" read -r file line_count; do
    [ -n "$file" ] || continue
    echo "❌ $file has $line_count lines. Files must be $MAX_FILE_LINES lines or fewer."
    violations=1
  done < <(collect_file_line_limit_violations)

  return $violations
}

ensure_publishable_file_sizes() {
  local issue=$1
  local title=$2
  local task_slug=$3
  local prompt_file=$4
  local codex_output_file=$5
  local violations

  stage_relevant_issue_files
  if git_in_issue_context diff --cached --quiet; then
    return 0
  fi

  violations=$(collect_file_line_limit_violations)
  if [ -z "$violations" ]; then
    return 0
  fi

  check_file_line_limit
  echo "🔧 Staged files exceed the $MAX_FILE_LINES-line limit. Asking codex to refactor before publish."
  write_line_limit_fix_prompt "$prompt_file" "$issue" "$title" "$task_slug" "$violations"
  run_codex_prompt "$prompt_file" "$codex_output_file" "remediate file line-limit violations" append "${CURRENT_ISSUE_WORKTREE:-$(pwd)}"

  stage_relevant_issue_files
  if check_file_line_limit; then
    return 0
  fi

  echo "❌ Commit aborted due to file size limit."
  return 1
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

run_progress_cli() {
  local project_root
  project_root=${GRKR_GLEAM_PROJECT_ROOT:-$(dirname "$SCRIPT_DIR")}

  if [ -f "$project_root/gleam.toml" ]; then
    (cd "$project_root" && gleam run -m grkr/progress/cli -- "$@")
    return
  fi

  case "${1:-}" in
    marker)
      printf '<!-- grkr:checkpoint stage=%s task=%s version=1 -->' "$2" "$3"
      ;;
    *)
      printf 'Missing Gleam project root for grkr progress CLI: %s\n' "$project_root" >&2
      return 1
      ;;
  esac
}

checkpoint_marker() {
  local stage=$1
  local task_slug=$2

  run_progress_cli marker "$stage" "$task_slug"
}
