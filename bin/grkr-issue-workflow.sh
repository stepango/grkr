#!/bin/bash
# Thin delegation wrapper for Gleam workflow/main + decision + task_log (GitHub-only v2).
# Complete replacement of 476 LOC thick sh per t_2ddd4dce.
# Preserves fn signatures for bin/grkr + tests via thin delegates to Gleam CLIs (exact parity).
# AGENTS: small explicit, no behavior change. Dupe refusal fns removed (now in Gleam refusal/assessment + decision).
# bin/grkr updated to call Gleam direct for handle/process paths.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$SCRIPT_DIR/doctor.sh"
doctor_init
if [ -f "$GRKR_CONFIG_FILE" ]; then . "$GRKR_CONFIG_FILE"; fi

# Compact common caller for workflow/* CLIs (decision, task_log, main)
gleam_wf() {
  local mod="$1"; shift
  local prj="${GRKR_GLEAM_PROJECT_ROOT:-$(dirname "$SCRIPT_DIR")}"
  if [ -f "$prj/gleam.toml" ]; then
    (cd "$prj" && gleam run -m "grkr/workflow/$mod" -- "$@")
  else
    echo "❌ Missing gleam.toml at $prj (for v2 $mod CLI)" >&2
    return 1
  fi
}

git_in_issue_context() {
  if [ -n "${CURRENT_ISSUE_WORKTREE:-}" ]; then
    (cd "$CURRENT_ISSUE_WORKTREE" && git "$@")
    return
  fi
  git "$@"
}

# Worktree thin delegates (to workflow/main; parity with old bash + worktree.gleam)
prepare_issue_worktree() { gleam_wf main prepare "$1" "$2" 2>/dev/null || echo ""; }
collect_relevant_issue_paths() { gleam_wf main collect-relevant 2>/dev/null; }
stage_relevant_issue_files() { gleam_wf main stage-relevant; }
cleanup_issue_worktree() { gleam_wf main cleanup "$1" 2>/dev/null || true; }

# Task log thin delegates (to task_log; exact sharding/persist/emit per t_ef6b855f)
task_log_supports_sharding() { gleam_wf task_log supports-sharding "$1" 2>/dev/null; }
task_log_parts_dir() { gleam_wf task_log parts-dir "$1"; }
task_log_is_sharded() { gleam_wf task_log is-sharded "$1" 2>/dev/null; }
emit_task_log_stream() { gleam_wf task_log emit "$1" 2>/dev/null; }
write_task_log_manifest() { gleam_wf task_log write-manifest "$1" "$2" >/dev/null 2>&1 || true; }
persist_task_log_output() {
  gleam_wf task_log persist "$1" "$2" "$3" "${4:-replace}" >/dev/null 2>&1 || {
    echo "⚠️ gleam task_log persist failed for $2" >&2; return 1; }
}

# Decision thin delegates (to decision; exact per t_ee96a4a4 + t_cbc53ef5)
update_task_progress_decision() { gleam_wf decision update-progress "$1" "$2" >/dev/null 2>&1 || true; }
extract_decision_from_output() { gleam_wf decision decide "$1" 2>/dev/null || echo ""; }
parse_refusal_decision_output() { gleam_wf decision parse-refusal "$1" 2>/dev/null || echo "other\n---\n"; }
detect_implementation_refusal() { gleam_wf decision detect-refusal "$1" 2>/dev/null || echo ""; }

# Note: refusal markdown/valid/normalize/requires/write/ensure/complete/run_gate removed (dupe in Gleam; callers in bin/grkr updated to direct CLI or refusal/cli per t_2ddd4dce)
