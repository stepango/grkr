# bin/lib/linear_issue_stages_implement.sh
# Stages-split slice 5 (docs/design-linear-issue-stages-split.md section 4-5 / 8 / 10):
# run_linear_decision_stage + handle_linear_decision_refuse + run_linear_implement_stage
# extracted from linear_issue_stages.sh into this sibling module. linear_issue_stages.sh
# is the source-only facade that sources this file (after refusal + research_plan).
# linear_issue.sh still sources only the stages facade after linear_mutate.sh.
#
# Ambient deps resolved at call time (from bin/grkr or tests sourcing linear_issue.sh):
#   prepare_issue_worktree, cleanup_issue_worktree, write_decision_prompt_file,
#   write_issue_prompt_file, run_codex_prompt (now in issue_shared.sh), run_decision_gate,
#   detect_implementation_refusal, normalize_refusal_class, extract_refusal_reasoning,
#   ensure_linear_implement_in_progress, ensure_linear_refusal_checkpoint.
#   Globals: ISSUE_IDENTIFIER, ISSUE_ID, ISSUE_TITLE, ISSUE_URL, BODY, TASK_SLUG,
#   TASK_DIR, PROGRESS_FILE, BRANCH, CURRENT_ISSUE_WORKTREE, CURRENT_PROMPT_FILE,
#   LINEAR_STATE_IMPLEMENTATION_ID, LINEAR_STATE_ID etc.
# No GitHub / gh project APIs. GRKR_LINEAR_MUTATE default OFF unchanged.
# Zero behavior change. Stable function names run_linear_decision_stage,
# handle_linear_decision_refuse, run_linear_implement_stage.

# --- Slice 5: thin process_linear_issue orchestration (final Linear shell slice per design §8) ---
# Bootstrap stays in linear_issue.sh (uses load/meta/progress seed kept there).
# Decision + implement blocks moved exact (zero intentional behavior change).
# process_linear_issue is now thin sequencer only, matching GitHub post-a3d9702.

# Decision stage (prepare worktree through decision case / IMPLEMENTATION_DECISION set).
# Includes GRKR_ISSUE_PROVIDER=linear export, write_decision_prompt, run_codex_prompt,
# run_decision_gate, normalize, invalid → return 1 with temp cleanup.
# Sets ISSUE_WORKTREE_DIR and IMPLEMENTATION_DECISION.
# Exact body move from process_linear_issue (preserves early CURRENT set for Linear parity).
# Temps cleaned on invalid path. Side effects for refuse inside run_decision_gate (linear_flow).
run_linear_decision_stage() {
  local decision_prompt_file
  local decision_output_file
  local decision

  ISSUE_WORKTREE_DIR=$(prepare_issue_worktree "$BRANCH" "$TASK_SLUG") || return 1
  CURRENT_ISSUE_WORKTREE="$ISSUE_WORKTREE_DIR"
  echo "🌿 Linear worktree ready: $ISSUE_WORKTREE_DIR"

  # Ensure provider context for decision_gate + linear_flow (provider-aware).
  GRKR_ISSUE_PROVIDER=linear
  export GRKR_ISSUE_PROVIDER

  decision_prompt_file=$(mktemp "${TMPDIR:-/tmp}/grkr-decision-prompt.XXXXXX")
  decision_output_file=$(mktemp "${TMPDIR:-/tmp}/grkr-decision-output.XXXXXX")
  write_decision_prompt_file "$decision_prompt_file" "$ISSUE_IDENTIFIER" "$ISSUE_TITLE" "$ISSUE_URL" "$BODY" "$TASK_SLUG" "$ISSUE_WORKTREE_DIR"
  run_codex_prompt "$decision_prompt_file" "$decision_output_file" "decide whether to implement the issue" replace "$ISSUE_WORKTREE_DIR"
  decision=$(run_decision_gate "$ISSUE_IDENTIFIER" "$decision_output_file" "$PROGRESS_FILE" "$TASK_SLUG" "$ISSUE_WORKTREE_DIR" "$decision_prompt_file" || echo "")
  decision=$(printf '%s' "$decision" | tr -d '\r\n' | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  rm -f "$decision_prompt_file" "$decision_output_file"
  case "$decision" in
    proceed|refuse)
      IMPLEMENTATION_DECISION=$decision
      ;;
    *)
      echo "❌ Decision gate for Linear $ISSUE_IDENTIFIER returned an invalid result."
      return 1
      ;;
  esac
}

# Refuse cleanup when decision was refuse (worktree + globals + echoes; TASK_DIR echo).
# Exact from original. Decision gate already performed checkpoint/backlog/progress/comment side effects.
handle_linear_decision_refuse() {
  if [ -n "${ISSUE_WORKTREE_DIR:-}" ]; then
    cleanup_issue_worktree "$ISSUE_WORKTREE_DIR"
    echo "🧹 Removed Linear worktree: $ISSUE_WORKTREE_DIR"
  fi
  CURRENT_ISSUE_WORKTREE=""
  echo "⏸️ Refused Linear issue $ISSUE_IDENTIFIER at decision gate."
  echo "TASK_DIR=$TASK_DIR"
}

# Implement stage (ensure in progress + codex implement + detect impl-refusal conversion path).
# On impl-refusal: ensure_linear_refusal_checkpoint (already Linear) + cleanup + messages;
# sets LINEAR_IMPL_REFUSED=1, returns 0 (terminal).
# On real error: clears state and returns 1.
# On success (no refusal): leaves worktree/prompt/codex_output via globals (CURRENT_PROMPT_FILE,
# TASK_DIR/implementation.log, ISSUE_WORKTREE_DIR) for test+publish stages. Returns 0.
# Uses recompute of mutation_issue_id from ambient ISSUE_ID/IDENTIFIER (set by bootstrap/load).
run_linear_implement_stage() {
  local prompt_file
  local codex_output_file
  local implementation_refusal
  local implementation_refusal_class
  local implementation_refusal_reasoning
  local mutation_issue_id=${ISSUE_ID:-$ISSUE_IDENTIFIER}

  # Proceed: plan In Progress state mutation (dry-run), then run implement codex.
  # Use ISSUE_STATE_ID as a candidate if it represents the target; prefer explicit LINEAR_STATE_IMPLEMENTATION_ID.
  local impl_state_id=${LINEAR_STATE_IMPLEMENTATION_ID:-${ISSUE_STATE_ID:-}}
  ensure_linear_implement_in_progress \
    "$ISSUE_IDENTIFIER" "$mutation_issue_id" "$TASK_SLUG" "$TASK_DIR" \
    "$PROGRESS_FILE" "$impl_state_id"

  prompt_file=$(mktemp "${TMPDIR:-/tmp}/grkr-prompt.XXXXXX")
  CURRENT_PROMPT_FILE="$prompt_file"
  write_issue_prompt_file "$prompt_file" "$ISSUE_IDENTIFIER" "$ISSUE_TITLE" "$ISSUE_URL" "$BODY" "$TASK_SLUG" "$ISSUE_WORKTREE_DIR"
  codex_output_file="$TASK_DIR/implementation.log"
  run_codex_prompt "$prompt_file" "$codex_output_file" "implement the issue" replace "$ISSUE_WORKTREE_DIR"
  implementation_refusal=$(detect_implementation_refusal "$codex_output_file")
  if [ -n "$implementation_refusal" ]; then
    echo "⚠️ Implementation discovered blockers that require refusal."
    echo "🔄 Converting implementation attempt to refusal for Linear $ISSUE_IDENTIFIER."
    implementation_refusal_class=$(normalize_refusal_class "$implementation_refusal")
    implementation_refusal_reasoning=$(extract_refusal_reasoning "$implementation_refusal" "Implementation discovered that the Linear issue is not ready for safe autonomous completion.")
    mkdir -p "$TASK_DIR/codex"
    cp "$codex_output_file" "$TASK_DIR/codex/implementation-before-refusal.log"
    # Reuse the already-Linear-aware refusal checkpoint helper (no dupe logic).
    ensure_linear_refusal_checkpoint \
      "$ISSUE_IDENTIFIER" "$mutation_issue_id" "$TASK_SLUG" "$TASK_DIR" \
      "$PROGRESS_FILE" "$implementation_refusal_class" "$implementation_refusal_reasoning" "$impl_state_id" || {
      CURRENT_ISSUE_WORKTREE=""
      rm -f "$prompt_file"
      CURRENT_PROMPT_FILE=""
      return 1
    }
    if [ -n "${ISSUE_WORKTREE_DIR:-}" ]; then
      cleanup_issue_worktree "$ISSUE_WORKTREE_DIR"
      echo "🧹 Removed Linear worktree: $ISSUE_WORKTREE_DIR"
    fi
    CURRENT_ISSUE_WORKTREE=""
    rm -f "$prompt_file"
    CURRENT_PROMPT_FILE=""
    echo "⏸️ Refused Linear issue $ISSUE_IDENTIFIER (converted during implementation)."
    echo "TASK_DIR=$TASK_DIR"
    LINEAR_IMPL_REFUSED=1
    return 0
  fi
  # success path: worktree + CURRENT_PROMPT_FILE + $TASK_DIR/implementation.log left for caller stages
  return 0
}

