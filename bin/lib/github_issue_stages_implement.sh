# bin/lib/github_issue_stages_implement.sh
# Stages-split slice 4 (docs/design-github-issue-stages-split.md §4–§6 / §8 / §10):
# bootstrap_github_issue_task + run_github_decision_stage +
# handle_github_decision_refuse + run_github_implement_stage +
# finalize_github_issue_complete extracted from github_issue.sh into this sibling
# module. github_issue.sh is the source-only facade that sources this file after
# github_issue_stages_research_plan.sh and before github_issue_stages_test.sh then
# github_issue_stages_publish.sh. bin/grkr still sources only github_issue.sh.
#
# Ambient deps resolved at call time (from bin/grkr or tests sourcing github_issue.sh):
#   prepare_issue_worktree, cleanup_issue_worktree, write_decision_prompt_file,
#   write_issue_prompt_file, run_codex_prompt (issue_shared), run_decision_gate,
#   detect_implementation_refusal, normalize_refusal_class, extract_refusal_reasoning,
#   handle_implementation_refusal, mark_task_progress_*, move_issue_to_*,
#   attach_issue_logs, post_completion_comment (publish sibling, ambient),
#   task_slug_for_issue, write_task_meta_env, write_issue_context_file,
#   ensure_task_progress_file, issue_project_item_id, gh, jq.
# Globals: ISSUE, TITLE, BODY, URL, ISSUE_JSON, TASK_*, PROGRESS_FILE, BRANCH,
#   CURRENT_*, IMPLEMENTATION_DECISION, GITHUB_IMPL_REFUSED, BRANCH_URL, PR_URL,
#   VALIDATION_OK, etc.
# Zero behavior change. Stable function names. No Linear / issue_shared dump.
# No new flags. No checkpoint-json Gleam extract.

# --- Slice 6: process_issue thinning (orchestrator moved to thin launcher in bin/grkr) ---

# Bootstrap: validation, gh fetch, globals (TITLE/BODY/URL etc), TASK_DIR/PROGRESS/BRANCH,
# meta/context/progress writes. Returns 1 on validation fail or not-found.
# Sets same globals process_issue used to set so downstream stages (checkpoints, decision, etc)
# and shared code continue to work identically. Exact body moved from process_issue.
bootstrap_github_issue_task() {
  local ISSUE=$1
  if [ "$VALIDATION_OK" -ne 1 ]; then
    echo "⚠️ Validation failed; skipping issue #$ISSUE."
    return 1
  fi
  echo "📋 Fetching issue #$ISSUE..."
  ISSUE_JSON=$(gh issue view "$ISSUE" --comments --json title,body,url,number,projectItems,comments 2>&1)
  if echo "$ISSUE_JSON" | grep -q "Could not resolve"; then
    echo "❌ Issue #$ISSUE not found."
    return 1
  fi
  TITLE=$(echo "$ISSUE_JSON" | jq -r '.title')
  BODY=$(echo "$ISSUE_JSON" | jq -r '.body // "No description provided."')
  URL=$(echo "$ISSUE_JSON" | jq -r '.url')
  TASKS_DIR="$GRKR_ROOT/.grkr/tasks"
  TASK_SLUG=$(task_slug_for_issue "$ISSUE" "$TITLE")
  TASK_DIR="$TASKS_DIR/$TASK_SLUG"
  PROGRESS_FILE="$TASK_DIR/progress.json"
  echo "📝 Issue: $TITLE"
  echo "🔗 $URL"
  BRANCH="issue-$ISSUE"
  CURRENT_ISSUE="$ISSUE"
  ATTACH_ISSUE_LOGS=1
  PROJECT_ITEM_ID=$(issue_project_item_id "$ISSUE" "$ISSUE_JSON")
  mkdir -p "$TASK_DIR"
  write_task_meta_env "$TASK_DIR" "$ISSUE" "$TASK_SLUG" "$BRANCH" "$URL" "$PROJECT_ITEM_ID"
  write_issue_context_file "$TASK_DIR" "$ISSUE_JSON"
  ensure_task_progress_file "$PROGRESS_FILE" "$ISSUE" "$PROJECT_ITEM_ID" "$TASK_SLUG" "$BRANCH"
}

# Decision stage (prepare worktree + codex decision + gate). Exact body moved.
# Sets ISSUE_WORKTREE_DIR and IMPLEMENTATION_DECISION.
# Returns 0 and prints decision value for logging context; 1 on invalid gate result (after cleanup).
# Temps cleaned in all paths. Side effects for refuse are inside run_decision_gate (Gleam).
run_github_decision_stage() {
  local decision_prompt_file
  local decision_output_file
  local decision

  ISSUE_WORKTREE_DIR=$(prepare_issue_worktree "$BRANCH" "$TASK_SLUG") || return 1
  decision_prompt_file=$(mktemp "${TMPDIR:-/tmp}/grkr-decision-prompt.XXXXXX")
  decision_output_file=$(mktemp "${TMPDIR:-/tmp}/grkr-decision-output.XXXXXX")
  write_decision_prompt_file "$decision_prompt_file" "$ISSUE" "$TITLE" "$URL" "$BODY" "$TASK_SLUG" "$ISSUE_WORKTREE_DIR"
  # Wired to Gleam decision_gate (spec/22 implement-or-refuse + t_4e22c63f): thin shell runs codex to output file (orchestration); gate does extract, progress update, refuse path (calls refusal/flow for checkpoint/backlog/comment), prints "proceed"/"refuse" on stdout.
  # Replaces prior inlined run_implementation_decision_gate + extract/update/handle_decision_refusal (now dupe removed; gate reuses Gleam decision + refusal/flow).
  run_codex_prompt "$decision_prompt_file" "$decision_output_file" "decide whether to implement the issue" replace "$ISSUE_WORKTREE_DIR"
  decision=$(run_decision_gate "$ISSUE" "$decision_output_file" "$PROGRESS_FILE" "$TASK_SLUG" "$ISSUE_WORKTREE_DIR" "$decision_prompt_file" || echo "")
  decision=$(printf '%s' "$decision" | tr -d '\r\n' | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  rm -f "$decision_prompt_file" "$decision_output_file"
  case "$decision" in
    proceed|refuse)
      IMPLEMENTATION_DECISION=$decision
      ;;
    *)
      echo "❌ Decision gate for issue #$ISSUE returned an invalid result."
      return 1
      ;;
  esac
}

# Refuse cleanup when decision was refuse (worktree + globals + attach logs).
# Exact messages and side effects from original process_issue refuse tail.
# (Decision gate already performed checkpoint/backlog/progress/comment side effects.)
handle_github_decision_refuse() {
  if [ -n "${ISSUE_WORKTREE_DIR:-}" ]; then
    cleanup_issue_worktree "$ISSUE_WORKTREE_DIR"
    echo "🧹 Removed issue worktree: $ISSUE_WORKTREE_DIR"
  fi
  CURRENT_ISSUE_WORKTREE=""
  ATTACH_ISSUE_LOGS=0
  attach_issue_logs
}

# Implement stage (move in progress + codex implement + detect impl-refusal conversion path).
# On impl-refusal: full conversion (handle + mark refused + cleanup + attach + messages), sets flag, returns 0 (terminal).
# On real error: clears state and returns 1.
# On success (no refusal): leaves worktree/prompt/codex_output in place via globals for sizes/test/publish; returns 0 to continue.
# Uses CURRENT_PROMPT_FILE and $TASK_DIR/implementation.log for downstream (no local leakage).
run_github_implement_stage() {
  local prompt_file
  local codex_output_file
  local implementation_refusal
  local implementation_refusal_class
  local implementation_refusal_reasoning
  local refusal_result
  local refusal_class
  local refusal_comment_id

  move_issue_to_in_progress "$ISSUE" "$ISSUE_JSON" || return 1
  CURRENT_ISSUE_WORKTREE="$ISSUE_WORKTREE_DIR"
  prompt_file=$(mktemp "${TMPDIR:-/tmp}/grkr-prompt.XXXXXX")
  CURRENT_PROMPT_FILE="$prompt_file"
  write_issue_prompt_file "$prompt_file" "$ISSUE" "$TITLE" "$URL" "$BODY" "$TASK_SLUG" "$ISSUE_WORKTREE_DIR"
  codex_output_file="$TASK_DIR/implementation.log"
  run_codex_prompt "$prompt_file" "$codex_output_file" "implement the issue" replace "$ISSUE_WORKTREE_DIR"
  implementation_refusal=$(detect_implementation_refusal "$codex_output_file")
  if [ -n "$implementation_refusal" ]; then
    echo "⚠️ Implementation discovered blockers that require refusal."
    echo "🔄 Converting implementation attempt to refusal for issue #$ISSUE."
    implementation_refusal_class=$(normalize_refusal_class "$implementation_refusal")
    implementation_refusal_reasoning=$(extract_refusal_reasoning "$implementation_refusal" "Implementation discovered that the issue is not ready for safe autonomous completion.")
    mkdir -p "$TASK_DIR/codex"
    cp "$codex_output_file" "$TASK_DIR/codex/implementation-before-refusal.log"
    refusal_result=$(handle_implementation_refusal "$ISSUE" "$PROGRESS_FILE" "$implementation_refusal_class" "$implementation_refusal_reasoning") || {
      CURRENT_ISSUE_WORKTREE=""
      rm -f "$prompt_file"
      CURRENT_PROMPT_FILE=""
      return 1
    }
    refusal_class=$(printf '%s\n' "$refusal_result" | tail -n2 | head -n1)
    refusal_comment_id=$(printf '%s\n' "$refusal_result" | tail -n1)
    mark_task_progress_refused "$PROGRESS_FILE" "$refusal_class" "$refusal_comment_id"
    if [ -n "${ISSUE_WORKTREE_DIR:-}" ]; then
      cleanup_issue_worktree "$ISSUE_WORKTREE_DIR"
      echo "🧹 Removed issue worktree: $ISSUE_WORKTREE_DIR"
    fi
    CURRENT_ISSUE_WORKTREE=""
    rm -f "$prompt_file"
    CURRENT_PROMPT_FILE=""
    echo "⏸️ Refused implementation for issue #$ISSUE (converted during implementation)."
    ATTACH_ISSUE_LOGS=0
    attach_issue_logs
    GITHUB_IMPL_REFUSED=1
    return 0
  fi
  # success path: worktree + CURRENT_PROMPT_FILE + $TASK_DIR/implementation.log left for caller stages
  return 0
}

# Finalize tail for happy complete path (exact). Clears worktree/prompt, marks, moves to Done, posts comment, attaches logs.
# Keeps process_issue thin without hiding the move warn (warn is still emitted).
finalize_github_issue_complete() {
  CURRENT_ISSUE_WORKTREE=""
  mark_task_progress_complete "$PROGRESS_FILE" "$BRANCH_URL" "$PR_URL"
  if ! move_issue_to_done "$ISSUE" "$ISSUE_JSON"; then
    echo "⚠️ Issue #$ISSUE implementation succeeded, but the project status could not be moved to ${DONE_VALUE:-Done}."
  fi
  post_completion_comment "$ISSUE" "$TITLE" "$BRANCH_URL" "$PR_URL"
  rm -f "$CURRENT_PROMPT_FILE"
  CURRENT_PROMPT_FILE=""
  ATTACH_ISSUE_LOGS=0
  attach_issue_logs
}
