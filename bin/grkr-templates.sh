#!/bin/bash
# Thin delegation wrapper for Gleam progress/templates via progress/cli (GitHub-only v2).
# Complete replacement of 317 LOC thick sh per t_7cc455e3 + t_23a1c5ae plan.
# Preserves exact fn signatures + output for bin/grkr + tests (parity verified).
# AGENTS: small explicit, no behavior change. Heavy rendering logic in Gleam progress/templates.gleam (176LOC).
# bin/grkr sources this; tests cp it for isolation.
# Updated in hygiene t_37fb63dc to use progress/cli (removed conflicting templates/ WIP).

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$SCRIPT_DIR/doctor.sh"
doctor_init

if [ -f "$GRKR_CONFIG_FILE" ]; then . "$GRKR_CONFIG_FILE"; fi

# Compact helper for progress/cli render-* (exact parity with workflow thin pattern)
gleam_tpl() {
  local subcmd="$1"; shift
  local prj="${GRKR_GLEAM_PROJECT_ROOT:-$(dirname "$SCRIPT_DIR")}"
  if [ -f "$prj/gleam.toml" ]; then
    (cd "$prj" && gleam run -m "grkr/progress/cli" -- "$subcmd" "$@")
  else
    echo "❌ Missing gleam.toml at $prj (for v2 templates CLI)" >&2
    return 1
  fi
}

# Thin delegates (preserve signatures; Gleam prints to stdout, sh redirects for write fns)
write_research_checkpoint_file() {
  local file=$1; shift
  gleam_tpl render-research-checkpoint "$@" > "$file"
}
write_plan_checkpoint_file() {
  local file=$1; shift
  gleam_tpl render-plan-checkpoint "$@" > "$file"
}
write_decision_prompt_file() {
  local file=$1; shift
  local max_lines=${MAX_FILE_LINES:-1000}
  gleam_tpl render-decision-prompt "$@" "$GRKR_ROOT" "$max_lines" > "$file"
}
write_issue_prompt_file() {
  local file=$1; shift
  local max_lines=${MAX_FILE_LINES:-1000}
  gleam_tpl render-issue-prompt "$@" "$GRKR_ROOT" "$max_lines" > "$file"
}
write_line_limit_fix_prompt() {
  local file=$1; shift
  local max_lines=${MAX_FILE_LINES:-1000}
  gleam_tpl render-line-limit-fix-prompt "$@" "$max_lines" > "$file"
}
write_default_pr_body() {
  local file=$1; shift
  gleam_tpl render-default-pr-body "$@" > "$file"
}
write_compact_pr_body() {
  local file=$1; shift
  gleam_tpl render-compact-pr-body "$@" > "$file"
}
append_issue_footer() {
  local pr_body_file=$1
  local issue=$2
  gleam_tpl render-issue-footer "$issue" >> "$pr_body_file"
}
