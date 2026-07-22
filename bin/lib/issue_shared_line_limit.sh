# bin/lib/issue_shared_line_limit.sh
# Concern-split slice 3 (docs/design-issue-shared-concern-split.md):
# collect_file_line_limit_violations + check_file_line_limit +
# ensure_publishable_file_sizes extracted from issue_shared.sh.
# Facade (issue_shared.sh) sources this sibling; bin/grkr still sources only the facade.
# Ambient call-time deps: git_in_issue_context, MAX_FILE_LINES,
# stage_relevant_issue_files, run_codex_prompt (still in facade until slice 5),
# write_line_limit_fix_prompt, CURRENT_ISSUE_WORKTREE.
# Zero behavior change; stable public names collect_file_line_limit_violations,
# check_file_line_limit, ensure_publishable_file_sizes.

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
  echo "🔧 Staged files exceed the $MAX_FILE_LINES-line limit. Asking coding agent to refactor before publish."
  write_line_limit_fix_prompt "$prompt_file" "$issue" "$title" "$task_slug" "$violations"
  run_codex_prompt "$prompt_file" "$codex_output_file" "remediate file line-limit violations" append "${CURRENT_ISSUE_WORKTREE:-$(pwd)}"

  stage_relevant_issue_files
  if check_file_line_limit; then
    return 0
  fi

  echo "❌ Commit aborted due to file size limit."
  return 1
}
