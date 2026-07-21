# bin/lib/linear_issue_stages.sh
# Facade for Linear stage bodies (docs/design-linear-issue-stages-split.md).
#
# Stages-split slice 1–4: ensure_linear_refusal_checkpoint lives in sibling
# linear_issue_stages_refusal.sh; ensure_linear_checkpoint_stage +
# ensure_linear_implement_in_progress live in sibling
# linear_issue_stages_research_plan.sh; ensure_linear_test_checkpoint lives in
# sibling linear_issue_stages_test.sh; ensure_linear_publish_complete lives in
# sibling linear_issue_stages_publish.sh (all sourced below). Remaining stage
# bodies still defined in this file until slice 5 moves them:
#   - run_linear_decision_stage + handle_linear_decision_refuse + run_linear_implement_stage
#     (→ stages_implement.sh; then this file becomes source-only)
#
# linear_issue.sh still sources only this facade after linear_mutate.sh.
# Public function names stable; ambient call-time resolution unchanged.
#
# Historical Linear thinning (design-linear-issue-thinning.md) moved stage bodies
# out of linear_issue.sh into this file (slices 1–5 → product tip f6b34d4 / #133).
# This facade begins the next LOC-hygiene pass (concern modules + thin entry).
#
# Ambient deps resolved at call time from sourcing context (bin/grkr or direct test
# sourcing of linear_issue.sh after its prerequisites):
#
# For test checkpoint (sibling linear_issue_stages_test.sh):
#   build_command_list, run_test_stage_hook, write_test_checkpoint_with_header,
#   run_progress_cli, checkpoint_marker (via progress), cleanup_test_result_logs,
#   mark_task_progress_failed, update_task_progress_stage, maybe_apply_linear_mutation
#   (from linear_mutate.sh, which must be sourced first), CURRENT_ISSUE_WORKTREE,
#   LINEAR_STATE_TEST_ID, etc.
#
# For publish+complete (sibling linear_issue_stages_publish.sh):
#   ensure_publishable_file_sizes, check_file_line_limit (now in issue_shared.sh),
#   stage_relevant_issue_files, git_in_issue_context,
#   generate_linear_implement_commit_message,
#   extract_linear_codex_pr_body, mark_task_progress_complete, run_progress_cli,
#   maybe_apply_linear_mutation (from linear_mutate.sh sourced first).
#   Globals used: CURRENT_ISSUE_WORKTREE, REPO, MAIN_BRANCH, LINEAR_STATE_DONE_ID,
#   BRANCH_URL, PR_URL (set inside fn).
#
# For refusal checkpoint (sibling linear_issue_stages_refusal.sh):
#   run_progress_cli (plan-linear-refusal, render-refusal, linear-comment-mutation,
#   linear-state-mutation, linear-state), mark_task_progress_refused,
#   maybe_apply_linear_mutation (from linear_mutate.sh, must be sourced first).
#   No GitHub / gh project APIs.
#
# For research/plan checkpoint + implement_in_progress (sibling
# linear_issue_stages_research_plan.sh):
#   write_research_checkpoint_file, write_plan_checkpoint_file (templates),
#   run_progress_cli (linear-comment-mutation, linear-state, linear-state-mutation),
#   update_task_progress_stage, maybe_apply_linear_mutation (from linear_mutate.sh,
#   must be sourced first). No gh / GitHub APIs.
#
# For decision/implement orchestration:
#   prepare_issue_worktree, cleanup_issue_worktree, write_decision_prompt_file,
#   write_issue_prompt_file, run_codex_prompt (now in issue_shared.sh), run_decision_gate,
#   detect_implementation_refusal, normalize_refusal_class, extract_refusal_reasoning,
#   ensure_linear_implement_in_progress, ensure_linear_refusal_checkpoint.
#   Globals: ISSUE_IDENTIFIER, ISSUE_ID, ISSUE_TITLE, ISSUE_URL, BODY, TASK_SLUG,
#   TASK_DIR, PROGRESS_FILE, BRANCH, CURRENT_ISSUE_WORKTREE, CURRENT_PROMPT_FILE,
#   LINEAR_STATE_IMPLEMENTATION_ID, LINEAR_STATE_ID etc.
#
# Mirrors github_issue.sh vertical extract pattern for Linear + Gleam facade hygiene:
#   - github_issue.sh owns GitHub-specific ensure_* / publish_* / bootstrap/decision/implement/finalize.
#   - linear_issue.sh stays thin sequencer + load/meta/progress seed + decode / run_provider / project_root.
#   - stages facade owns extracted Linear stage bodies (and sources concern siblings as they land).
#   - process_linear_issue call sites unchanged; external --linear-issue contract identical.
#   - Shared helpers stay shared / provider-agnostic.
#
# No behavior change. GitHub untouched. GRKR_ISSUE_PROVIDER default unchanged.
# linear_mutate.sh must be sourced before this file so maybe_apply_linear_mutation exists.

# Source Linear refusal stage body (stages-split slice 1). Fail closed if missing
# so tests that copy lib/ cannot silently omit the sibling.
REFUSAL_LIB_CANDIDATE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/linear_issue_stages_refusal.sh"
if [ -f "$REFUSAL_LIB_CANDIDATE" ]; then
  . "$REFUSAL_LIB_CANDIDATE"
else
  echo "❌ missing Linear stages refusal module: $REFUSAL_LIB_CANDIDATE" >&2
  return 1 2>/dev/null || exit 1
fi

# Source Linear research/plan + implement_in_progress (stages-split slice 4). Fail closed
# if missing so tests that copy lib/ cannot silently omit the sibling. Sourced before
# remaining implement bodies in this file (design: refusal + research_plan before implement).
RESEARCH_PLAN_LIB_CANDIDATE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/linear_issue_stages_research_plan.sh"
if [ -f "$RESEARCH_PLAN_LIB_CANDIDATE" ]; then
  . "$RESEARCH_PLAN_LIB_CANDIDATE"
else
  echo "❌ missing Linear stages research_plan module: $RESEARCH_PLAN_LIB_CANDIDATE" >&2
  return 1 2>/dev/null || exit 1
fi

# Source Linear test stage body (stages-split slice 2). Fail closed if missing
# so tests that copy lib/ cannot silently omit the sibling.
TEST_LIB_CANDIDATE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/linear_issue_stages_test.sh"
if [ -f "$TEST_LIB_CANDIDATE" ]; then
  . "$TEST_LIB_CANDIDATE"
else
  echo "❌ missing Linear stages test module: $TEST_LIB_CANDIDATE" >&2
  return 1 2>/dev/null || exit 1
fi

# Source Linear publish stage body (stages-split slice 3). Fail closed if missing
# so tests that copy lib/ cannot silently omit the sibling.
PUBLISH_LIB_CANDIDATE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/linear_issue_stages_publish.sh"
if [ -f "$PUBLISH_LIB_CANDIDATE" ]; then
  . "$PUBLISH_LIB_CANDIDATE"
else
  echo "❌ missing Linear stages publish module: $PUBLISH_LIB_CANDIDATE" >&2
  return 1 2>/dev/null || exit 1
fi

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
