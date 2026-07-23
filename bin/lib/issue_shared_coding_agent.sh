# bin/lib/issue_shared_coding_agent.sh
# Concern-split slice 5 (docs/design-issue-shared-concern-split.md):
# coding-agent bridge extracted from issue_shared.sh.
# Facade (issue_shared.sh) sources this sibling; bin/grkr still sources only the facade.
# Ambient call-time deps: persist_task_log_output (grkr-issue-workflow.sh),
# GRKR_CODING_AGENT / CODING_AGENT / GRKR_AGENT_{DECISION,IMPLEMENT,REMEDIATE},
# CODEX_* / GROK_* / XAI_API_KEY (~/.hermes/.env load when unset).
# Zero behavior change; stable public names run_codex_prompt + run_coding_agent_prompt.

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
    -m "${GROK_MODEL:-grok-4.5}" \
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
