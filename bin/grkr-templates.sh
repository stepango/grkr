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

# Thin GitHub PR body helpers (new for slice: delegate ensure limit + codex section select to Gleam).
# Path-based I/O for large content. preserve exact wc-m limit, Fixes-once, awk section, sharded emit in caller.
select_codex_pr_section() {
  local input_file=$1
  gleam_tpl select-codex-pr-section "$input_file"
}

ensure_github_pr_body() {
  local pr_body_file=$1
  shift
  gleam_tpl ensure-github-pr-body "$pr_body_file" "$@"
}

# Linear PR body helpers (thin; reuse default/compact renders, NEVER append "Fixes #N").
# Called only from Linear publish path. Appends "Linear: <identifier>" + url marker.
# Mirrors extract_codex_pr_body + ensure_pr_body_limit structure but omits GitHub footer.
# GitHub paths and ensure_pr_body_limit behavior are untouched.

ensure_linear_pr_body_limit() {
  local pr_body_file=$1
  local body=$2
  local title=$3
  local identifier=$4
  local url=$5
  local body_length

  body_length=$(wc -m < "$pr_body_file" | tr -d '[:space:]')
  if [ "$body_length" -gt "${MAX_PR_BODY_CHARS:-60000}" ]; then
    write_compact_pr_body "$pr_body_file" "$body" "$title"
  fi

  if ! grep -Fq "Linear: $identifier" "$pr_body_file" 2>/dev/null; then
    printf '\nLinear: %s\n' "$identifier" >> "$pr_body_file"
    if [ -n "$url" ]; then
      printf '%s\n' "$url" >> "$pr_body_file"
    fi
  fi
}

extract_linear_codex_pr_body() {
  local codex_output_file=$1
  local pr_body_file=$2
  local body=$3
  local title=$4
  local identifier=$5
  local url=$6

  if [ -s "$codex_output_file" ] || task_log_is_sharded "$codex_output_file"; then
    emit_task_log_stream "$codex_output_file" | awk '
      /^## / {found=1}
      found {print}
    ' > "$pr_body_file"
    if [ -s "$pr_body_file" ]; then
      ensure_linear_pr_body_limit "$pr_body_file" "$body" "$title" "$identifier" "$url"
      return 0
    fi
  fi

  write_default_pr_body "$pr_body_file" "$body" "$title"
  ensure_linear_pr_body_limit "$pr_body_file" "$body" "$title" "$identifier" "$url"
}
