# bin/lib/linear_issue_stages_research_plan.sh
# Stages-split slice 4 (docs/design-linear-issue-stages-split.md §4–§5 / §8 / §10):
# ensure_linear_checkpoint_stage + ensure_linear_implement_in_progress extracted from
# linear_issue_stages.sh into this sibling module. linear_issue_stages.sh is the facade
# that sources this file. linear_issue.sh still sources only the stages facade after
# linear_mutate.sh.
#
# Ambient deps resolved at call time (from bin/grkr or tests sourcing linear_issue.sh):
#   write_research_checkpoint_file, write_plan_checkpoint_file (templates),
#   run_progress_cli (linear-comment-mutation, linear-state, linear-state-mutation),
#   update_task_progress_stage, maybe_apply_linear_mutation (from linear_mutate.sh,
#   must be sourced before stages).
# No GitHub / gh project APIs. GRKR_LINEAR_MUTATE default OFF unchanged.
# Zero behavior change. Stable function names ensure_linear_checkpoint_stage and
# ensure_linear_implement_in_progress.

# Write research/plan checkpoint files and plan Linear comment mutations via progress CLI.
# MVP does not require live Linear mutation success: mutation plan is always logged.
# Optional GRKR_LINEAR_MUTATE=1 applies live (soft-fail default). Dumps + sidecars written; default OFF.
ensure_linear_checkpoint_stage() {
  local stage=$1
  local identifier=$2
  local linear_issue_id=$3
  local task_slug=$4
  local task_dir=$5
  local title=$6
  local body=$7
  local url=$8
  local progress_file=$9
  local checkpoint_file
  local mutation_out
  local idempotency_key

  checkpoint_file="$task_dir/$stage.md"

  if [ -f "$checkpoint_file" ]; then
    echo "♻️ Reusing local $stage checkpoint for Linear $identifier."
    update_task_progress_stage "$progress_file" "$stage" "done" ""
    return 0
  fi

  case "$stage" in
    research)
      write_research_checkpoint_file "$checkpoint_file" "$identifier" "$title" "$body" "$url" "$task_slug"
      ;;
    plan)
      write_plan_checkpoint_file "$checkpoint_file" "$identifier" "$title" "$task_slug"
      ;;
    *)
      echo "❌ Unsupported Linear checkpoint stage: $stage"
      return 1
      ;;
  esac

  echo "📝 Planned Linear $stage checkpoint mutation for $identifier..."
  mutation_out=$(run_progress_cli linear-comment-mutation \
    "$linear_issue_id" \
    "$(cat "$checkpoint_file")" \
    "$stage" \
    "$task_slug" 2>/dev/null) || mutation_out=""

  if [ -n "$mutation_out" ]; then
    idempotency_key=$(printf '%s\n' "$mutation_out" | tail -n1)
    printf '%s\n' "$mutation_out" > "$task_dir/$stage.linear-mutation.txt"
    maybe_apply_linear_mutation "$task_dir/$stage.linear-mutation.txt"
    echo "🔑 $stage mutation idempotency_key=$idempotency_key (set GRKR_LINEAR_MUTATE=1 to apply)"
  else
    echo "⚠️ progress CLI linear-comment-mutation planning failed for $stage; local checkpoint kept."
  fi

  update_task_progress_stage "$progress_file" "$stage" "done" "${idempotency_key:-}"
}

# Plan Linear "In Progress" state mutation (dry-run) for implement stage.
# Writes implement.linear-state-mutation.txt (when state id available) + logs.
# Updates progress implement_or_refuse to done (parity after proceed decision).
# GRKR_LINEAR_MUTATE=1 applies via maybe_apply (guarded).
ensure_linear_implement_in_progress() {
  local identifier=$1
  local linear_issue_id=$2
  local task_slug=$3
  local task_dir=$4
  local progress_file=$5
  local state_id=${6:-}
  local target_state
  local mutation_out
  local idempotency_key
  local mutation_file

  mutation_file="$task_dir/implement.linear-state-mutation.txt"

  if [ -z "$identifier" ] || [ -z "$task_slug" ] || [ -z "$progress_file" ]; then
    echo "❌ ensure_linear_implement_in_progress requires identifier, task_slug, progress_file" >&2
    return 1
  fi

  target_state=$(run_progress_cli linear-state implementation 2>/dev/null || echo "In Progress")

  echo "📝 Planning Linear implement In Progress mutation for $identifier (target=$target_state)..."

  if [ -n "$state_id" ]; then
    mutation_out=$(run_progress_cli linear-state-mutation "$linear_issue_id" "$state_id" implement 2>/dev/null) || mutation_out=""
  else
    mutation_out=""
  fi

  if [ -n "$mutation_out" ]; then
    idempotency_key=$(printf '%s\n' "$mutation_out" | tail -n1)
    printf '%s\n' "$mutation_out" > "$mutation_file"
    maybe_apply_linear_mutation "$mutation_file"
    echo "🔑 implement state mutation idempotency_key=$idempotency_key"
  else
    # Name-only record for dry-run when no concrete state id is known
    {
      printf 'TARGET_STATE=%s\n' "$target_state"
      printf 'STATE_MUTATION_PLANNED=0\n'
    } > "$mutation_file"
    maybe_apply_linear_mutation "$mutation_file"
    echo "🔑 implement state target=$target_state (no state id provided; set GRKR_LINEAR_MUTATE=1 when live apply lands)"
  fi

  # Mark implement_or_refuse done (decision gate already set decision=proceed)
  update_task_progress_stage "$progress_file" "implement_or_refuse" "done" "${idempotency_key:-}"
  echo "✅ Linear implement In Progress mutation planned for $identifier (worktree left for subsequent stages)."
}
