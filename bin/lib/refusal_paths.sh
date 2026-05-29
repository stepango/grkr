# bin/lib/refusal_paths.sh
# Common helpers for workflow/decision/refusal paths (extracted per t_4703a519 + t_58795e29 to satisfy AGENTS.md "every file <=1000 LOC").
# Updated in t_b5bd0fa8 (task_progress shared extract); now sources alongside task_progress.sh for shared mark_* fns.
# Small explicit extractions; no behavior change. Duplicated CLI invocation + output parsing consolidated here.
# Includes handle_decision_refusal + handle_implementation_refusal (for impl-to-refusal conversion during codex run) + low-level fns (normalize, extract, invoke, parse_comment).
# Used by bin/grkr (decision gate refusal + impl-to-refusal conversion paths; fixes missing fn post-thinning).
# GitHub-only v2. Sourced after grkr-issue-workflow.sh (for parse_refusal_decision_output etc).
# Preserves all shell conventions.

normalize_refusal_class() {
  local raw_output=$1
  local candidate
  candidate=$(printf '%s\n' "$raw_output" | awk 'NR == 1 {print}')
  local class
  class=$(printf '%s' "${candidate:-}" | tr '[:upper:]' '[:lower:]' | tr ' -' '__' | tr -cd 'a-z0-9_')
  case "$class" in
    underspecified|too_large|missing_dependency|needs_design_decision|unsafe_autonomous_change|repo_not_ready|other) ;;
    *) class=other ;;
  esac
  printf '%s' "$class"
}

extract_refusal_reasoning() {
  local raw_output=$1
  local default_reason=${2:-"The issue does not appear ready for safe autonomous implementation in its current state."}
  local reasoning
  reasoning=$(printf '%s\n' "$raw_output" | awk 'found {print} /^---$/ {found=1}' | sed '/^$/d')
  [ -z "$reasoning" ] && reasoning="$default_reason"
  printf '%s' "$reasoning"
}

invoke_refusal_cli() {
  local issue=$1
  local class=$2
  local reasoning=$3
  local emits_file=$4
  local project_root=${GRKR_GLEAM_PROJECT_ROOT:-$(dirname "${SCRIPT_DIR:-$PWD}")}
  local gleam_status=0
  if [ -f "$project_root/gleam.toml" ]; then
    set +e
    (cd "$project_root" && gleam run -m grkr/refusal/cli -- "$issue" "$class" "$reasoning") 2>&1 | tee "$emits_file"
    gleam_status=$?
    set -e
  else
    echo "❌ Missing gleam.toml at $project_root (required for v2 refusal/cli)" >&2
    gleam_status=1
  fi
  return $gleam_status
}

parse_refusal_comment_id() {
  local emits_file=$1
  grep '^REFUSAL_COMMENT_ID=' "$emits_file" 2>/dev/null | head -1 | sed 's/[^=]*=//' | tr -d '"' || true
}

# Full handler for decision-gate refusal path (extracted/centralized here for LOC hygiene + to restore missing def).
# Called from process_issue when decision != proceed.
handle_decision_refusal() {
  local ISSUE=$1
  local PROGRESS_FILE=$2
  local decision_output_file=$3
  local decision_prompt_file=$4
  local ISSUE_WORKTREE_DIR=$5

  local parsed_refusal
  parsed_refusal=$(parse_refusal_decision_output "$decision_output_file")

  local refusal_class
  refusal_class=$(normalize_refusal_class "$parsed_refusal")

  local reasoning
  reasoning=$(extract_refusal_reasoning "$parsed_refusal")

  local refusal_emits
  refusal_emits=$(mktemp "${TMPDIR:-/tmp}/grkr-refusal-emits.XXXXXX")

  if ! invoke_refusal_cli "$ISSUE" "$refusal_class" "$reasoning" "$refusal_emits"; then
    rm -f "$refusal_emits" "$decision_prompt_file" "$decision_output_file"
    return 1
  fi

  local refusal_comment_id
  refusal_comment_id=$(parse_refusal_comment_id "$refusal_emits")

  mark_task_progress_refused "$PROGRESS_FILE" "$refusal_class" "$refusal_comment_id"

  rm -f "$refusal_emits" "$decision_prompt_file" "$decision_output_file"

  CURRENT_ISSUE_WORKTREE=""
  echo "⏸️ Refused implementation for issue #$ISSUE."
  ATTACH_ISSUE_LOGS=0
  attach_issue_logs
  return 0
}

# Handler for the impl-to-refusal conversion path (extracted to lib in t_58795e29 for LOC hygiene + shared helpers per AGENTS.md).
# Mirrors structure of handle_decision_refusal but for post-implementation codex detection (via detect_implementation_refusal).
# Takes pre-parsed class + reasoning (caller uses normalize/extract now; removed dupe awk from bin/grkr).
# Does invoke + parse id; prints class\nid as final two lines (for caller's tail/head capture + mark).
# Does NOT mark, set CURRENT, attach, or print message (caller does that for this path).
# On error: rm emits only; caller does prompt cleanup in || block.
handle_implementation_refusal() {
  local ISSUE=$1
  local PROGRESS_FILE=$2
  local refusal_class=$3
  local reasoning=$4

  local refusal_emits
  refusal_emits=$(mktemp "${TMPDIR:-/tmp}/grkr-refusal-emits.XXXXXX")

  if ! invoke_refusal_cli "$ISSUE" "$refusal_class" "$reasoning" "$refusal_emits"; then
    rm -f "$refusal_emits"
    return 1
  fi

  local refusal_comment_id
  refusal_comment_id=$(parse_refusal_comment_id "$refusal_emits")

  rm -f "$refusal_emits"

  # Final two lines for caller capture: refusal_class + refusal_comment_id (preserves legacy parsing in process_issue)
  printf '%s\n%s\n' "$refusal_class" "$refusal_comment_id"
  return 0
}
