# bin/lib/linear_issue_stages.sh
# Slice 1: ensure_linear_test_checkpoint extracted from linear_issue.sh (first vertical
# Linear-only stage body per docs/design-linear-issue-thinning.md §9).
# Slice 2: ensure_linear_publish_complete (publish + complete) extracted from
# linear_issue.sh (second vertical per design §8/§10). PR from linear-* + mark complete
# + complete comment planned FIRST then Done state (no GitHub labels, no gh issue edits).
# Slice 3: ensure_linear_refusal_checkpoint extracted from linear_issue.sh (third
# vertical per design §8/§10). Writes refusal.md + plans comment + optional Backlog
# state via plan-linear-refusal (or fallback render+mutations); marks refused; soft
# by default. No gh / GitHub APIs.
#
# Ambient deps resolved at call time from sourcing context (bin/grkr or direct test
# sourcing of linear_issue.sh after its prerequisites):
#
# For Slice 1 (test checkpoint):
#   build_command_list, run_test_stage_hook, write_test_checkpoint_with_header,
#   run_progress_cli, checkpoint_marker (via progress), cleanup_test_result_logs,
#   mark_task_progress_failed, update_task_progress_stage, maybe_apply_linear_mutation
#   (from linear_mutate.sh, which must be sourced first), CURRENT_ISSUE_WORKTREE,
#   LINEAR_STATE_TEST_ID, etc.
#
# For Slice 2 (publish+complete):
#   ensure_publishable_file_sizes, check_file_line_limit (now in issue_shared.sh),
#   stage_relevant_issue_files, git_in_issue_context,
#   generate_linear_implement_commit_message,
#   extract_linear_codex_pr_body, mark_task_progress_complete, run_progress_cli,
#   maybe_apply_linear_mutation (from linear_mutate.sh sourced first).
#   Globals used: CURRENT_ISSUE_WORKTREE, REPO, MAIN_BRANCH, LINEAR_STATE_DONE_ID,
#   BRANCH_URL, PR_URL (set inside fn).
#
# For Slice 3 (refusal checkpoint):
#   run_progress_cli (plan-linear-refusal, render-refusal, linear-comment-mutation,
#   linear-state-mutation, linear-state), mark_task_progress_refused,
#   maybe_apply_linear_mutation (from linear_mutate.sh, must be sourced first).
#   No GitHub / gh project APIs.
#
# For Slice 4 (research/plan checkpoint + implement_in_progress):
#   write_research_checkpoint_file, write_plan_checkpoint_file (templates),
#   run_progress_cli (linear-comment-mutation, linear-state, linear-state-mutation),
#   update_task_progress_stage, maybe_apply_linear_mutation (from linear_mutate.sh,
#   must be sourced first). No gh / GitHub APIs.
#
# For Slice 5 (final thin sequencer): run_linear_decision_stage, handle_linear_decision_refuse,
# run_linear_implement_stage extracted from process_linear_issue body. process_linear_issue
# is now pure sequencing (bootstrap + ensure checkpoints + run_decision + handle-or-proceed +
# run_implement + ensure test/publish + finalize echoes). Mirrors GitHub after PR #121.
#
# Ambient deps for new fns (Slice 5):
#   prepare_issue_worktree, cleanup_issue_worktree, write_decision_prompt_file,
#   write_issue_prompt_file, run_codex_prompt, run_decision_gate, detect_implementation_refusal,
#   normalize_refusal_class, extract_refusal_reasoning, ensure_linear_implement_in_progress,
#   ensure_linear_refusal_checkpoint. Globals: ISSUE_IDENTIFIER, ISSUE_ID, ISSUE_TITLE,
#   ISSUE_URL, BODY, TASK_SLUG, TASK_DIR, PROGRESS_FILE, BRANCH, CURRENT_ISSUE_WORKTREE,
#   CURRENT_PROMPT_FILE, LINEAR_STATE_IMPLEMENTATION_ID, LINEAR_STATE_ID etc.
#
# Mirrors github_issue.sh vertical extract pattern for Linear:
#   - github_issue.sh owns GitHub-specific ensure_* / publish_* / bootstrap/decision/implement/finalize.
#   - linear_issue.sh stays thin sequencer + load_linear_issue_assignments / meta / progress seed + decode / run_provider / project_root.
#   - stages sibling owns extracted Linear stage bodies + the decision/implement orchestration blocks.
#   - process_linear_issue call sites unchanged; external --linear-issue contract identical.
#   - Shared helpers stay shared / provider-agnostic.
#
# No behavior change. GitHub untouched. GRKR_ISSUE_PROVIDER default unchanged.
# linear_mutate.sh must be sourced before this file so maybe_apply_linear_mutation exists.

# Wire Linear test stage after successful implement (spec/26 parity).
# Reuses shared build_command_list, run_test_stage_hook, cleanup_test_result_logs,
# write_test_checkpoint_with_header (Linear header), checkpoint_marker, run_progress_cli.
# Executes BUILD/TEST (or npm test) inside CURRENT_ISSUE_WORKTREE.
# Writes test.md (marker + "Linear issue ID: title" + sections).
# Plans test.linear-mutation.txt (comment) + test.linear-state-mutation.txt ("In Review").
# Updates stages.test done|failed; leaves worktree on success; no gh, no publish, no complete.
# Resume: local test.md + progress done (no remote lookup).
# GRKR_LINEAR_MUTATE=1 applies after dumps (soft).
ensure_linear_test_checkpoint() {
  local identifier=$1
  local mutation_issue_id=$2
  local task_slug=$3
  local task_dir=$4
  local title=$5
  local progress_file=$6
  local checkpoint_file
  local command_list_file
  local results_file
  local command
  local log_file
  local status
  local recommendation="ready"
  local overall_result="PASS"
  local total_commands=0
  local passed_commands=0
  local failed_commands=0
  local worktree_shell_path
  local body
  local mutation_out
  local idempotency_key
  local target_state
  local state_mutation_file

  if [ -z "$identifier" ] || [ -z "$task_slug" ] || [ -z "$progress_file" ]; then
    echo "❌ ensure_linear_test_checkpoint requires identifier, task_slug, progress_file" >&2
    return 1
  fi

  checkpoint_file="$task_dir/test.md"

  if [ -f "$checkpoint_file" ]; then
    if jq -e '.stages.test.status == "done"' "$progress_file" >/dev/null 2>&1; then
      echo "♻️ Reusing local test checkpoint for Linear $identifier."
      return 0
    fi
  fi

  # Thin hook (provider-agnostic; heavy exec stays in shell).
  run_test_stage_hook

  command_list_file=$(mktemp "${TMPDIR:-/tmp}/grkr-test-commands.XXXXXX")
  results_file=$(mktemp "${TMPDIR:-/tmp}/grkr-test-results.XXXXXX")
  build_command_list > "$command_list_file"

  while IFS= read -r command; do
    [ -n "$command" ] || continue
    total_commands=$((total_commands + 1))
    log_file=$(mktemp "${TMPDIR:-/tmp}/grkr-test-output.XXXXXX")
    echo "🧪 Running verification command for Linear $identifier: $command"
    if [ -n "${CURRENT_ISSUE_WORKTREE:-}" ]; then
      worktree_shell_path=$(printf '%q' "$CURRENT_ISSUE_WORKTREE")
      if bash -lc "cd $worktree_shell_path && $command" > "$log_file" 2>&1; then
        status="PASS"
        passed_commands=$((passed_commands + 1))
      else
        status="FAIL"
        failed_commands=$((failed_commands + 1))
        overall_result="FAIL"
        recommendation="needs follow-up"
      fi
    elif bash -lc "$command" > "$log_file" 2>&1; then
      status="PASS"
      passed_commands=$((passed_commands + 1))
    else
      status="FAIL"
      failed_commands=$((failed_commands + 1))
      overall_result="FAIL"
      recommendation="needs follow-up"
    fi
    printf '%s\t%s\t%s\n' "$status" "$command" "$log_file" >> "$results_file"
  done < "$command_list_file"

  # Write using shared writer with Linear header (no # on identifier).
  local header_line
  header_line=$(printf 'Linear issue %s: %s' "$identifier" "$title")
  write_test_checkpoint_with_header \
    "$checkpoint_file" \
    "$header_line" \
    "$task_slug" \
    "$command_list_file" \
    "$results_file" \
    "$recommendation" \
    "$overall_result" \
    "$total_commands" \
    "$passed_commands" \
    "$failed_commands"

  # Plan Linear comment mutation (dry-run).
  echo "📝 Planning Linear test checkpoint mutation for $identifier..."
  body=$(cat "$checkpoint_file")
  mutation_out=$(run_progress_cli linear-comment-mutation \
    "$mutation_issue_id" \
    "$body" \
    test \
    "$task_slug" 2>/dev/null) || mutation_out=""

  if [ -n "$mutation_out" ]; then
    idempotency_key=$(printf '%s\n' "$mutation_out" | tail -n1)
    printf '%s\n' "$mutation_out" > "$task_dir/test.linear-mutation.txt"
    maybe_apply_linear_mutation "$task_dir/test.linear-mutation.txt"
    echo "🔑 test mutation idempotency_key=${idempotency_key} (set GRKR_LINEAR_MUTATE=1 to apply)"
  else
    echo "⚠️ progress CLI linear-comment-mutation planning failed for test; local checkpoint kept."
  fi

  # Plan Linear state mutation to test_state (default "In Review").
  target_state=$(run_progress_cli linear-state test 2>/dev/null || echo "In Review")
  state_mutation_file="$task_dir/test.linear-state-mutation.txt"

  echo "📝 Planning Linear test state mutation for $identifier (target=$target_state)..."
  if [ -n "${LINEAR_STATE_TEST_ID:-}" ]; then
    local state_mut
    state_mut=$(run_progress_cli linear-state-mutation "$mutation_issue_id" "${LINEAR_STATE_TEST_ID}" test 2>/dev/null) || state_mut=""
    if [ -n "$state_mut" ]; then
      printf '%s\n' "$state_mut" > "$state_mutation_file"
      maybe_apply_linear_mutation "$state_mutation_file"
      echo "🔑 test state mutation idempotency_key=$(printf '%s\n' "$state_mut" | tail -n1)"
    else
      {
        printf 'TARGET_STATE=%s\n' "$target_state"
        printf 'STATE_MUTATION_PLANNED=0\n'
      } > "$state_mutation_file"
      maybe_apply_linear_mutation "$state_mutation_file"
    fi
  else
    {
      printf 'TARGET_STATE=%s\n' "$target_state"
      printf 'STATE_MUTATION_PLANNED=0\n'
    } > "$state_mutation_file"
    maybe_apply_linear_mutation "$state_mutation_file"
    echo "🔑 test state target=$target_state (no LINEAR_STATE_TEST_ID; set GRKR_LINEAR_MUTATE=1 when live apply lands)"
  fi

  if [ "$failed_commands" -gt 0 ]; then
    update_task_progress_stage "$progress_file" test "failed" "${idempotency_key:-}"
    cleanup_test_result_logs "$results_file"
    rm -f "$command_list_file" "$results_file"
    mark_task_progress_failed "$progress_file" test
    CURRENT_ISSUE_WORKTREE=""
    return 1
  fi

  update_task_progress_stage "$progress_file" test "done" "${idempotency_key:-}"
  cleanup_test_result_logs "$results_file"
  rm -f "$command_list_file" "$results_file"

  echo "✅ Linear test stage complete for $identifier (commands executed in worktree; test.md + dry-run mutations written)."
  return 0
}

# ensure_linear_publish_complete wires the publish + complete dry-run for Linear after test success.
# Reuses shared (issue_shared.sh): ensure_publishable_file_sizes (with remediation), check_file_line_limit,
#   stage_relevant, git_in_*, 
# generate_linear_implement_commit_message, extract_linear_codex_pr_body (no Fixes footer),
# mark_task_progress_complete, run_progress_cli (for pr_summary/Done + comment).
# GitHub label edits and gh issue comment are NEVER performed on Linear path.
# On no-changes: still mark complete + plan Linear Done/comment (BRANCH/PR urls may be empty).
# On publish hard failure: return 1 without mark or complete.*.txt dumps.
ensure_linear_publish_complete() {
  local identifier=$1
  local mutation_issue_id=$2
  local task_slug=$3
  local task_dir=$4
  local title=$5
  local issue_url=$6
  local body=$7
  local codex_output_file=$8
  local branch=$9
  local progress_file=${10:-}
  local prompt_file=${11:-}

  if [ -z "$identifier" ] || [ -z "$task_slug" ] || [ -z "$progress_file" ]; then
    echo "❌ ensure_linear_publish_complete requires identifier, task_slug, progress_file" >&2
    return 1
  fi

  # 1. Ensure sizes (may run remediation codex using prompt + codex_output; stages relevant internally)
  ensure_publishable_file_sizes "$identifier" "$title" "$task_slug" "$prompt_file" "$codex_output_file" || return 1

  # 2. Publish (mirror structure of publish_issue_changes but Linear-specific; no labels)
  echo "🔄 Auto-committing, pushing and creating PR..."
  stage_relevant_issue_files
  if git_in_issue_context diff --cached --quiet; then
    echo "No changes for $identifier"
    # fall through: still mark + plan Linear complete (urls may remain unset)
  else
    if ! check_file_line_limit; then
      echo "❌ Commit aborted due to file size limit."
      return 1
    fi

    local commit_msg
    commit_msg=$(generate_linear_implement_commit_message "$identifier" "$title")
    git_in_issue_context commit -m "$commit_msg" || {
      echo "❌ git commit failed for $identifier"
      return 1
    }
    git_in_issue_context push -u origin "$branch" || {
      echo "❌ git push failed for $identifier"
      return 1
    }
    BRANCH_URL="https://github.com/$REPO/tree/$branch"

    local PR_BODY_FILE
    PR_BODY_FILE=$(mktemp "${TMPDIR:-/tmp}/grkr-pr-body.XXXXXX")
    extract_linear_codex_pr_body "$codex_output_file" "$PR_BODY_FILE" "$body" "$title" "$identifier" "$issue_url"

    local pr_list_json
    local pr_number
    local pr_create_output
    pr_list_json=$(gh pr list --head "$branch" --json number,url 2>/dev/null || true)
    pr_number=$(printf '%s' "$pr_list_json" | jq -r '.[0].number // empty')
    if [ -n "$pr_number" ]; then
      gh pr edit "$pr_number" --title "$title" --body-file "$PR_BODY_FILE" >/dev/null
      PR_URL=$(printf '%s' "$pr_list_json" | jq -r '.[0].url // empty')
      echo "✅ PR updated: $PR_URL"
    else
      pr_create_output=$(gh pr create --base "${MAIN_BRANCH:-main}" --head "$branch" --title "$title" --body-file "$PR_BODY_FILE" 2>&1) || {
        echo "$pr_create_output"
        rm -f "$PR_BODY_FILE"
        return 1
      }
      PR_URL=$(printf '%s\n' "$pr_create_output" | awk '/^https?:\/\// {url=$0} END {print url}')
      if [ -z "$PR_URL" ]; then
        echo "$pr_create_output"
        rm -f "$PR_BODY_FILE"
        return 1
      fi
      echo "✅ PR created: $PR_URL"
    fi
    rm -f "$PR_BODY_FILE"
  fi

  # 3. Mark progress complete (provider-agnostic; records urls even if partial/empty)
  mark_task_progress_complete "$progress_file" "${BRANCH_URL:-}" "${PR_URL:-}"

  # 4. Plan completion comment FIRST (per design: comment before Done state), then apply.
  local mutation_out
  local comment_body
  comment_body=$(cat <<'CMT'
## Completion summary

Linear issue __IDENT__: __TITLE__

- Recommendation: ready
- Branch: __BRANCH__
- PR: __PR__
CMT
)
  # substitute safely
  comment_body=${comment_body//__IDENT__/$identifier}
  comment_body=${comment_body//__TITLE__/$title}
  comment_body=${comment_body//__BRANCH__/${BRANCH_URL:-}}
  comment_body=${comment_body//__PR__/${PR_URL:-}}

  echo "📝 Planning Linear completion comment for $identifier..."
  mutation_out=$(run_progress_cli linear-comment-mutation \
    "$mutation_issue_id" \
    "$comment_body" \
    pr_summary \
    "$task_slug" 2>/dev/null) || mutation_out=""

  local complete_mutation_file="$task_dir/complete.linear-mutation.txt"
  if [ -n "$mutation_out" ]; then
    local idempotency_key
    idempotency_key=$(printf '%s\n' "$mutation_out" | tail -n1)
    printf '%s\n' "$mutation_out" > "$complete_mutation_file"
    maybe_apply_linear_mutation "$complete_mutation_file"
    echo "🔑 complete comment idempotency_key=${idempotency_key}"
  else
    echo "⚠️ progress CLI linear-comment-mutation planning failed for complete; local summary kept."
    # write a fallback local body for test visibility
    printf '%s\n' "$comment_body" > "$complete_mutation_file"
    maybe_apply_linear_mutation "$complete_mutation_file"
  fi

  # 5. Plan Linear Done state mutation AFTER comment (design order).
  local target_state
  target_state=$(run_progress_cli linear-state pr_summary 2>/dev/null || echo "Done")
  local state_mutation_file="$task_dir/complete.linear-state-mutation.txt"

  echo "📝 Planning Linear complete / Done state mutation for $identifier (target=$target_state)..."
  if [ -n "${LINEAR_STATE_DONE_ID:-}" ]; then
    local state_mut
    state_mut=$(run_progress_cli linear-state-mutation "$mutation_issue_id" "${LINEAR_STATE_DONE_ID}" complete 2>/dev/null) || state_mut=""
    if [ -n "$state_mut" ]; then
      printf '%s\n' "$state_mut" > "$state_mutation_file"
      maybe_apply_linear_mutation "$state_mutation_file"
      echo "🔑 complete state mutation idempotency_key=$(printf '%s\n' "$state_mut" | tail -n1)"
    else
      {
        printf 'TARGET_STATE=%s\n' "$target_state"
        printf 'STATE_MUTATION_PLANNED=0\n'
      } > "$state_mutation_file"
      maybe_apply_linear_mutation "$state_mutation_file"
    fi
  else
    {
      printf 'TARGET_STATE=%s\n' "$target_state"
      printf 'STATE_MUTATION_PLANNED=0\n'
    } > "$state_mutation_file"
    maybe_apply_linear_mutation "$state_mutation_file"
    echo "🔑 complete state target=$target_state (no LINEAR_STATE_DONE_ID; set GRKR_LINEAR_MUTATE=1 when live apply lands)"
  fi

  echo "✅ Linear publish + complete planned for $identifier"
  return 0
}

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
