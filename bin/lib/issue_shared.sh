# bin/lib/issue_shared.sh
# Stable facade path for neutral shared helpers (GitHub + Linear issue paths).
# bin/grkr sources only this file (BEFORE lib/linear_issue.sh and lib/github_issue.sh).
#
# Concern-split slices 1–4 (docs/design-issue-shared-concern-split.md):
#   attach_issue_logs → issue_shared_attach.sh (sourced below; fail-closed).
#   run_progress_cli + checkpoint_marker → issue_shared_progress.sh (sourced below; fail-closed).
#   collect_file_line_limit_violations + check_file_line_limit +
#     ensure_publishable_file_sizes → issue_shared_line_limit.sh (sourced below; fail-closed).
#   build_command_list + cleanup_test_result_logs +
#     write_test_checkpoint_with_header → issue_shared_test_write.sh (sourced below; fail-closed).
# Historical "Slice 1–5" labels from shared-helpers extract (#136–#144 /
# design-grkr-shared-helpers-extract.md) are historical extract-into-shared order;
# do not confuse them with concern-split slice numbers in the design above.
#
# Remaining bodies STILL in this facade until later concern-split slices:
#   - coding-agent bridge: _grkr_coding_*, backends, run_coding_agent_prompt,
#     run_codex_prompt (GRKR_CODING_AGENT=codex|grok default codex)
#
# Current facade source order (slices 1–4 landed; coding_agent still in-file):
#   attach → progress → line_limit → test_write
# Future full order (design §4):
#   coding_agent → progress → test_write → line_limit → attach
#
# Ambient call-time deps (resolved in grkr / grkr-issue-workflow / templates
# at call time; bash name resolution): git_in_issue_context,
# stage_relevant_issue_files, persist_task_log_output (from grkr-issue-workflow.sh),
# write_line_limit_fix_prompt (grkr-templates.sh), MAX_FILE_LINES,
# CURRENT_ISSUE_WORKTREE. No re-exports; exact prior behavior.
#
# Progress CLI ambient deps (SCRIPT_DIR / optional GRKR_GLEAM_PROJECT_ROOT) live
# in issue_shared_progress.sh header; line-limit ambient deps live in
# issue_shared_line_limit.sh header; test-write ambient deps (checkpoint_marker)
# live in issue_shared_test_write.sh header; coding-agent keeps call-time deps above.

# Source attach sibling (concern-split slice 1). Fail closed if missing so tests
# that copy lib/ cannot silently omit the sibling.
ATTACH_LIB_CANDIDATE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/issue_shared_attach.sh"
if [ -f "$ATTACH_LIB_CANDIDATE" ]; then
  . "$ATTACH_LIB_CANDIDATE"
else
  echo "❌ missing issue_shared attach module: $ATTACH_LIB_CANDIDATE" >&2
  return 1 2>/dev/null || exit 1
fi

# Source progress sibling (concern-split slice 2). Fail closed if missing.
PROGRESS_LIB_CANDIDATE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/issue_shared_progress.sh"
if [ -f "$PROGRESS_LIB_CANDIDATE" ]; then
  . "$PROGRESS_LIB_CANDIDATE"
else
  echo "❌ missing issue_shared progress module: $PROGRESS_LIB_CANDIDATE" >&2
  return 1 2>/dev/null || exit 1
fi

# Source line_limit sibling (concern-split slice 3). Fail closed if missing.
# coding_agent still in-file so ambient run_codex_prompt works at call time for
# ensure_publishable_file_sizes (slice 5 will extract coding_agent).
LINE_LIMIT_LIB_CANDIDATE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/issue_shared_line_limit.sh"
if [ -f "$LINE_LIMIT_LIB_CANDIDATE" ]; then
  . "$LINE_LIMIT_LIB_CANDIDATE"
else
  echo "❌ missing issue_shared line_limit module: $LINE_LIMIT_LIB_CANDIDATE" >&2
  return 1 2>/dev/null || exit 1
fi

# Source test_write sibling (concern-split slice 4). Fail closed if missing.
# progress is sourced above so checkpoint_marker resolves at call time.
TEST_WRITE_LIB_CANDIDATE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/issue_shared_test_write.sh"
if [ -f "$TEST_WRITE_LIB_CANDIDATE" ]; then
  . "$TEST_WRITE_LIB_CANDIDATE"
else
  echo "❌ missing issue_shared test_write module: $TEST_WRITE_LIB_CANDIDATE" >&2
  return 1 2>/dev/null || exit 1
fi

# Resolve selected coding agent for a workflow step.
# Precedence: step override → GRKR_CODING_AGENT / CODING_AGENT → codex.
# Steps: decision | implement | remediate | default
_grkr_coding_agent_name() {
  local step=${1:-default}
  local raw=""

  case "$step" in
    decision)
      raw="${GRKR_AGENT_DECISION:-${GRKR_CODING_AGENT_DECISION:-}}"
      ;;
    implement)
      raw="${GRKR_AGENT_IMPLEMENT:-${GRKR_CODING_AGENT_IMPLEMENT:-}}"
      ;;
    remediate)
      raw="${GRKR_AGENT_REMEDIATE:-${GRKR_CODING_AGENT_REMEDIATE:-}}"
      ;;
  esac

  if [ -z "$raw" ]; then
    raw="${GRKR_CODING_AGENT:-${CODING_AGENT:-codex}}"
  fi
  printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]'
}

# Map human phase labels (used by GitHub/Linear stages) → step keys.
_grkr_coding_step_from_phase() {
  local phase=$1
  case "$phase" in
    *"decide whether to implement"*) printf 'decision' ;;
    *"implement the issue"*) printf 'implement' ;;
    *"remediate file line-limit"*) printf 'remediate' ;;
    *) printf 'default' ;;
  esac
}

# Codex backend: CODEX_BIN (default codex) + optional CODEX_ARGS (spec/05).
# Prefer non-deprecated sandbox flags; allow CODEX_EXTRA_ARGS for --skip-git-repo-check etc.
_grkr_run_codex_backend() {
  local prompt_file=$1
  local workdir=$2
  local out_file=$3
  local bin="${CODEX_BIN:-codex}"
  local rc=0

  # CODEX_ARGS / CODEX_EXTRA_ARGS intentionally word-split.
  # shellcheck disable=SC2086
  if [ -n "${CODEX_ARGS:-}" ]; then
    "$bin" exec --sandbox workspace-write --full-auto ${CODEX_ARGS} ${CODEX_EXTRA_ARGS:-} --cd "$workdir" <"$prompt_file" >"$out_file" 2>&1 || rc=$?
  else
    "$bin" exec --sandbox workspace-write --full-auto ${CODEX_EXTRA_ARGS:-} --cd "$workdir" <"$prompt_file" >"$out_file" 2>&1 || rc=$?
  fi
  return "$rc"
}

# Grok Build backend: GROK_BIN / ~/.grok/bin/grok, GROK_MODEL, GROK_MAX_TURNS, GROK_ARGS.
# Loads XAI_API_KEY from ~/.hermes/.env when unset (same as hermes grok_build_exec).
_grkr_run_grok_backend() {
  local prompt_file=$1
  local workdir=$2
  local out_file=$3
  local bin="${GROK_BIN:-}"
  local rc=0
  local _xai_line _xai_val

  export PATH="${HOME}/.grok/bin:${HOME}/.local/bin:${PATH}"
  if [ -z "${XAI_API_KEY:-}" ] && [ -f "${HOME}/.hermes/.env" ]; then
    _xai_line=$(grep -E '^XAI_API_KEY=' "${HOME}/.hermes/.env" | head -1 || true)
    if [ -n "$_xai_line" ]; then
      _xai_val="${_xai_line#XAI_API_KEY=}"
      _xai_val=$(printf '%s' "$_xai_val" | tr -d '\r')
      # strip optional surrounding quotes
      if [ "${#_xai_val}" -ge 2 ]; then
        case "${_xai_val:0:1}${_xai_val: -1}" in
          \"\"|\'\') _xai_val="${_xai_val:1:${#_xai_val}-2}" ;;
        esac
      fi
      export XAI_API_KEY="$_xai_val"
    fi
  fi

  if [ -z "$bin" ]; then
    if [ -x "${HOME}/.grok/bin/grok" ]; then
      bin="${HOME}/.grok/bin/grok"
    else
      bin="grok"
    fi
  fi

  # GROK_ARGS intentionally word-split for optional extras (e.g. --check).
  # shellcheck disable=SC2086
  "$bin" \
    --prompt-file "$prompt_file" \
    --cwd "$workdir" \
    -m "${GROK_MODEL:-grok-build}" \
    --yolo \
    --permission-mode bypassPermissions \
    --max-turns "${GROK_MAX_TURNS:-60}" \
    --output-format plain \
    --no-memory \
    ${GROK_ARGS:-} \
    >"$out_file" 2>&1 || rc=$?
  return "$rc"
}

# Stable name kept for call sites (GitHub + Linear stages). Prefer
# run_coding_agent_prompt in new code; both are identical.
run_coding_agent_prompt() {
  run_codex_prompt "$@"
}

run_codex_prompt() {
  local prompt_file=$1
  local output_file=$2
  local phase_label=$3
  local mode=${4:-replace}
  local workdir=${5:-$(pwd)}
  local step=${6:-}
  local run_output_file
  local agent
  local rc=0

  if [ -z "$step" ]; then
    step=$(_grkr_coding_step_from_phase "$phase_label")
  fi
  agent=$(_grkr_coding_agent_name "$step")
  run_output_file=$(mktemp "${TMPDIR:-/tmp}/grkr-agent-output.XXXXXX")
  echo "🚀 Running coding agent ($agent/$step) to $phase_label..."
  echo "Prompt saved to $prompt_file for reference."

  case "$agent" in
    codex)
      _grkr_run_codex_backend "$prompt_file" "$workdir" "$run_output_file" || rc=$?
      ;;
    grok)
      _grkr_run_grok_backend "$prompt_file" "$workdir" "$run_output_file" || rc=$?
      ;;
    *)
      {
        echo "❌ Unknown coding agent '$agent' for step='$step' (supported: codex, grok)."
        echo "   Set GRKR_CODING_AGENT or GRKR_AGENT_{DECISION,IMPLEMENT,REMEDIATE}=codex|grok."
      } >&2
      rm -f "$run_output_file"
      return 2
      ;;
  esac

  cat "$run_output_file"
  echo ""

  persist_task_log_output "$run_output_file" "$output_file" "$phase_label" "$mode"
  echo "✅ coding agent ($agent/$step) finished $phase_label."
  return "$rc"
}
