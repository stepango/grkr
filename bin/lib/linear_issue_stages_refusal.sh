# bin/lib/linear_issue_stages_refusal.sh
# Stages-split slice 1 (docs/design-linear-issue-stages-split.md §4–§5 / §8 / §10):
# ensure_linear_refusal_checkpoint extracted from linear_issue_stages.sh into this
# sibling module. linear_issue_stages.sh is the facade that sources this file.
# linear_issue.sh still sources only the stages facade after linear_mutate.sh.
#
# Ambient deps resolved at call time (from bin/grkr or tests sourcing linear_issue.sh):
#   run_progress_cli (plan-linear-refusal, render-refusal, linear-comment-mutation,
#   linear-state-mutation, linear-state), mark_task_progress_refused,
#   maybe_apply_linear_mutation (from linear_mutate.sh, must be sourced before stages).
# No GitHub / gh project APIs. GRKR_LINEAR_MUTATE default OFF unchanged.
# Zero behavior change. Stable function name ensure_linear_refusal_checkpoint.

# Linear refuse progress path (post-MVP t_503ca0f3): write refusal.md, plan
# commentCreate + Backlog state mutations via progress/cli (dry-run by default).
# Does NOT call gh project / GitHub issue APIs. Full worker-refuse Linear CLI is sibling scope.
# Optional state_id (Linear workflow state UUID) plans issueUpdate; empty state_id still records
# TARGET_STATE name from LINEAR_STATE_BACKLOG / default "Backlog".
# progress.json parity: mark_task_progress_refused (status=refused, test skipped).
ensure_linear_refusal_checkpoint() {
  local identifier=$1
  local linear_issue_id=$2
  local task_slug=$3
  local task_dir=$4
  local progress_file=$5
  local reason_class=$6
  local reasoning=$7
  local state_id=${8:-}
  local refusal_file
  local plan_out
  local comment_key
  local target_state
  local body
  local mutation_comment_file
  local mutation_state_file
  local plan_file

  refusal_file="$task_dir/refusal.md"
  mutation_comment_file="$task_dir/refusal.linear-mutation.txt"
  mutation_state_file="$task_dir/refusal.linear-state-mutation.txt"
  plan_file="$task_dir/refusal.linear-plan.txt"

  if [ -z "$identifier" ] || [ -z "$task_slug" ] || [ -z "$progress_file" ]; then
    echo "❌ ensure_linear_refusal_checkpoint requires identifier, task_slug, progress_file" >&2
    return 1
  fi
  if [ -z "$reason_class" ]; then
    reason_class="other"
  fi
  if [ -z "$reasoning" ]; then
    reasoning="No reasoning provided for Linear refuse path."
  fi

  mkdir -p "$task_dir"

  if [ -f "$refusal_file" ] && [ -f "$mutation_comment_file" ]; then
    echo "♻️ Reusing local Linear refusal checkpoint for $identifier."
    comment_key=$(grep -E '^COMMENT_IDEMPOTENCY_KEY=' "$plan_file" 2>/dev/null | head -1 | sed 's/^[^=]*=//' || true)
    if [ -z "$comment_key" ]; then
      comment_key=$(tail -n1 "$mutation_comment_file" 2>/dev/null || true)
    fi
    mark_task_progress_refused "$progress_file" "$reason_class" "${comment_key:-}"
    return 0
  fi

  echo "📝 Planning Linear refuse checkpoint for $identifier (class=$reason_class)..."
  if [ -n "$state_id" ]; then
    plan_out=$(run_progress_cli plan-linear-refusal \
      "$linear_issue_id" "$task_slug" "$reason_class" "$reasoning" "$state_id" 2>/dev/null) || plan_out=""
  else
    plan_out=$(run_progress_cli plan-linear-refusal \
      "$linear_issue_id" "$task_slug" "$reason_class" "$reasoning" 2>/dev/null) || plan_out=""
  fi

  if [ -z "$plan_out" ]; then
    # Fallback: compose via existing render + mutation CLIs
    body=$(run_progress_cli render-refusal "$task_slug" "$reason_class" "$reasoning" 2>/dev/null) || body=""
    if [ -z "$body" ]; then
      echo "❌ progress CLI plan-linear-refusal / render-refusal failed for $identifier" >&2
      return 1
    fi
    printf '%s\n' "$body" > "$refusal_file"
    plan_out=$(run_progress_cli linear-comment-mutation \
      "$linear_issue_id" "$body" refusal "$task_slug" 2>/dev/null) || plan_out=""
    comment_key=$(printf '%s\n' "$plan_out" | tail -n1)
    printf '%s\n' "$plan_out" > "$mutation_comment_file"
    target_state=$(run_progress_cli linear-state refusal 2>/dev/null || echo "Backlog")
    {
      printf 'TARGET_STATE=%s\n' "$target_state"
      printf 'COMMENT_IDEMPOTENCY_KEY=%s\n' "$comment_key"
      printf 'STATE_MUTATION_PLANNED=0\n'
    } > "$plan_file"
    if [ -n "$state_id" ]; then
      local state_mut
      state_mut=$(run_progress_cli linear-state-mutation "$linear_issue_id" "$state_id" refusal 2>/dev/null) || state_mut=""
      if [ -n "$state_mut" ]; then
        printf '%s\n' "$state_mut" > "$mutation_state_file"
        printf 'STATE_MUTATION_PLANNED=1\n' >> "$plan_file"
        printf 'STATE_IDEMPOTENCY_KEY=%s\n' "$(printf '%s\n' "$state_mut" | tail -n1)" >> "$plan_file"
      fi
    fi
  else
    printf '%s\n' "$plan_out" > "$plan_file"
    target_state=$(printf '%s\n' "$plan_out" | grep -E '^TARGET_STATE=' | head -1 | sed 's/^[^=]*=//')
    comment_key=$(printf '%s\n' "$plan_out" | grep -E '^COMMENT_IDEMPOTENCY_KEY=' | head -1 | sed 's/^[^=]*=//')
    # Extract body after ---BODY---
    body=$(printf '%s\n' "$plan_out" | awk 'f{print} /^---BODY---$/{f=1}')
    if [ -z "$body" ]; then
      body=$(run_progress_cli render-refusal "$task_slug" "$reason_class" "$reasoning" 2>/dev/null) || body=""
    fi
    printf '%s\n' "$body" > "$refusal_file"
    # Comment mutation dump (query + variables + key) for parity with research/plan *.linear-mutation.txt
    {
      printf '%s\n' "$plan_out" | awk '/^---COMMENT_QUERY---$/{p=1;next} /^---COMMENT_VARIABLES---$/{p=2;next} /^---BODY---$/{exit} p==1{print} p==2{print}'
      printf '%s\n' "$comment_key"
    } > "$mutation_comment_file"
    if printf '%s\n' "$plan_out" | grep -q '^STATE_MUTATION_PLANNED=1'; then
      {
        printf '%s\n' "$plan_out" | awk '/^---STATE_QUERY---$/{p=1;next} /^---STATE_VARIABLES---$/{p=2;next} /^---COMMENT_QUERY---$/{exit} p==1{print} p==2{print}'
        printf '%s\n' "$plan_out" | grep -E '^STATE_IDEMPOTENCY_KEY=' | head -1 | sed 's/^[^=]*=//'
      } > "$mutation_state_file"
    fi
  fi

  maybe_apply_linear_mutation "$mutation_comment_file"
  maybe_apply_linear_mutation "$mutation_state_file"
  echo "🔑 refuse comment idempotency_key=${comment_key:-unknown} target_state=${target_state:-Backlog} (set GRKR_LINEAR_MUTATE=1 to apply)"
  # comment_id in progress uses idempotency key string until live mutate returns real id
  mark_task_progress_refused "$progress_file" "$reason_class" "${comment_key:-}"
  echo "✅ Linear refuse progress planned for $identifier (no live Linear mutations by default)."
}
