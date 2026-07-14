# bin/lib/linear_issue.sh
# Linear --linear-issue helpers for bin/grkr (research + plan + decision + implement + test + publish+complete).
# Loads Linear issue context via Gleam issue_provider fetch-issue (fixture or live).
# Plans checkpoints via progress/cli; when GRKR_LINEAR_MUTATE=1 + token, applies after each dump (guarded).
# Default remains pure dry-run (identical logs/artifacts). GitHub PR from linear-*; Done + completion.
# GitHub default + all GitHub paths untouched. Live mutate writes sidecars + §8 markers.

linear_issue_project_root() {
  printf '%s\n' "${GRKR_GLEAM_PROJECT_ROOT:-$(dirname "$SCRIPT_DIR")}"
}

# Source the guarded mutate apply helper (keeps this file under 1000 LOC per AGENTS.md).
# The helper is thin and provides maybe_apply_linear_mutation.
MUTATE_LIB_CANDIDATE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/linear_mutate.sh"
if [ -f "$MUTATE_LIB_CANDIDATE" ]; then
  . "$MUTATE_LIB_CANDIDATE"
fi

run_issue_provider_cli() {
  local prj
  prj=$(linear_issue_project_root)
  if [ ! -f "$prj/gleam.toml" ]; then
    echo "❌ Missing gleam.toml at $prj (for issue_provider CLI)" >&2
    return 1
  fi
  (cd "$prj" && gleam run -m grkr/issue_provider/main -- "$@")
}

# Decode a Gleam shell_quote payload (optional surrounding double quotes).
# Wire protocol is single-line KEY="..." with escapes: \\ \" \$ \` \n \r.
# Physical newlines must never appear inside values (multi-line Linear bodies use \n).
decode_shell_assignment_value() {
  local val="$1"
  local output=""
  local i=0
  local len
  local c
  local next

  if [ "${val#\"}" != "$val" ] && [ "${val%\"}" != "$val" ]; then
    val=${val#\"}
    val=${val%\"}
  fi

  len=${#val}
  while [ "$i" -lt "$len" ]; do
    c=${val:i:1}
    if [ "$c" = '\' ] && [ $((i + 1)) -lt "$len" ]; then
      next=${val:i+1:1}
      case "$next" in
        n) output+=$'\n' ;;
        r) output+=$'\r' ;;
        \\) output+='\' ;;
        '"') output+='"' ;;
        '$') output+='$' ;;
        '`') output+='`' ;;
        *) output+="$next" ;;
      esac
      i=$((i + 2))
    else
      output+="$c"
      i=$((i + 1))
    fi
  done
  printf '%s' "$output"
}

# Parse single-line KEY="value" shell assignments from gleam fetch-issue stdout.
# Only accepts known keys; values are shell_quote-encoded by the Gleam emitter
# (including \n/\r for multi-line title/description).
load_linear_issue_assignments() {
  local identifier=$1
  local raw
  local line
  local key
  local val

  FOUND=0
  ISSUE_ID=""
  ISSUE_IDENTIFIER=""
  ISSUE_TITLE=""
  ISSUE_DESCRIPTION=""
  ISSUE_URL=""
  ISSUE_STATE=""
  ISSUE_STATE_ID=""
  ISSUE_PRIORITY=""
  ISSUE_UPDATED_AT=""
  JOB_KEY=""
  TASK_SLUG=""
  ERROR=""

  raw=$(run_issue_provider_cli fetch-issue "$identifier") || {
    echo "❌ Failed to load Linear issue $identifier via issue_provider fetch-issue" >&2
    printf '%s\n' "$raw" >&2
    return 1
  }

  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      FOUND=*|ISSUE_ID=*|ISSUE_IDENTIFIER=*|ISSUE_TITLE=*|ISSUE_DESCRIPTION=*|ISSUE_URL=*|ISSUE_STATE=*|ISSUE_STATE_ID=*|ISSUE_PRIORITY=*|ISSUE_UPDATED_AT=*|JOB_KEY=*|TASK_SLUG=*|ERROR=*)
        key=${line%%=*}
        val=$(decode_shell_assignment_value "${line#*=}")
        case "$key" in
          FOUND) FOUND=$val ;;
          ISSUE_ID) ISSUE_ID=$val ;;
          ISSUE_IDENTIFIER) ISSUE_IDENTIFIER=$val ;;
          ISSUE_TITLE) ISSUE_TITLE=$val ;;
          ISSUE_DESCRIPTION) ISSUE_DESCRIPTION=$val ;;
          ISSUE_URL) ISSUE_URL=$val ;;
          ISSUE_STATE) ISSUE_STATE=$val ;;
          ISSUE_STATE_ID) ISSUE_STATE_ID=$val ;;
          ISSUE_PRIORITY) ISSUE_PRIORITY=$val ;;
          ISSUE_UPDATED_AT) ISSUE_UPDATED_AT=$val ;;
          JOB_KEY) JOB_KEY=$val ;;
          TASK_SLUG) TASK_SLUG=$val ;;
          ERROR) ERROR=$val ;;
        esac
        ;;
    esac
  done <<EOF
$raw
EOF

  if [ "${FOUND:-0}" != "1" ]; then
    echo "❌ Linear issue $identifier not found: ${ERROR:-unknown error}" >&2
    return 1
  fi
  if [ -z "${ISSUE_IDENTIFIER:-}" ] || [ -z "${TASK_SLUG:-}" ]; then
    echo "❌ Linear fetch-issue missing required fields for $identifier" >&2
    return 1
  fi
  return 0
}

write_linear_task_meta_env() {
  local task_dir=$1
  local identifier=$2
  local task_slug=$3
  local branch=$4
  local url=$5
  local linear_id=$6
  local meta_file

  meta_file="$task_dir/meta.env"
  {
    printf 'PROVIDER=linear\n'
    printf 'ISSUE_IDENTIFIER=%q\n' "$identifier"
    printf 'ISSUE_ID=%q\n' "$linear_id"
    printf 'TASK_SLUG=%q\n' "$task_slug"
    printf 'BRANCH=%q\n' "$branch"
    printf 'ISSUE_URL=%q\n' "$url"
  } > "$meta_file"
}

ensure_linear_task_progress_file() {
  local progress_file=$1
  local identifier=$2
  local task_slug=$3
  local branch=$4
  local now
  local tmp_file

  [ -f "$progress_file" ] && return 0

  now=$(timestamp_utc)
  tmp_file=$(mktemp "${TMPDIR:-/tmp}/grkr-progress.XXXXXX")
  jq -n \
    --arg issue_identifier "$identifier" \
    --arg task_slug "$task_slug" \
    --arg branch "$branch" \
    --arg provider "linear" \
    --arg started_at "$now" \
    --arg updated_at "$now" '
    {
      provider: $provider,
      issue_identifier: $issue_identifier,
      task_slug: $task_slug,
      branch: $branch,
      status: "planning",
      decision: "undecided",
      stages: {
        research: {status: "pending"},
        plan: {status: "pending"},
        implement_or_refuse: {status: "pending"},
        test: {status: "pending"}
      },
      started_at: $started_at,
      updated_at: $updated_at
    }
  ' > "$tmp_file"
  mv "$tmp_file" "$progress_file"
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
    maybe_apply_linear_mutation "$mutation_comment_file"
    maybe_apply_linear_mutation "$mutation_state_file"
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
    maybe_apply_linear_mutation "$mutation_comment_file"
    maybe_apply_linear_mutation "$mutation_state_file"
  fi

  maybe_apply_linear_mutation "$mutation_comment_file"
  maybe_apply_linear_mutation "$mutation_state_file"
  echo "🔑 refuse comment idempotency_key=${comment_key:-unknown} target_state=${target_state:-Backlog} (set GRKR_LINEAR_MUTATE=1 to apply)"
  # comment_id in progress uses idempotency key string until live mutate returns real id
  mark_task_progress_refused "$progress_file" "$reason_class" "${comment_key:-}"
  echo "✅ Linear refuse progress planned for $identifier (no live Linear mutations by default)."
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
# Reuses shared: ensure_publishable_file_sizes (with remediation), stage_relevant, git_in_*, check_file_line_limit,
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

process_linear_issue() {
  local IDENTIFIER=$1
  local ISSUE_WORKTREE_DIR
  local TASKS_DIR
  local TASK_DIR
  local PROGRESS_FILE
  local BRANCH
  local BODY

  if [ -z "$IDENTIFIER" ]; then
    echo "❌ --linear-issue requires a non-empty identifier (e.g. ENG-123)"
    return 1
  fi

  if [ "$VALIDATION_OK" -ne 1 ]; then
    echo "⚠️ Validation failed; skipping Linear issue $IDENTIFIER."
    return 1
  fi

  echo "📋 Loading Linear issue $IDENTIFIER..."
  load_linear_issue_assignments "$IDENTIFIER" || return 1

  BODY=${ISSUE_DESCRIPTION:-No description provided.}
  TASKS_DIR="$GRKR_ROOT/.grkr/tasks"
  if [ -z "${TASK_SLUG:-}" ]; then
    TASK_SLUG=$(printf '%s' "$ISSUE_IDENTIFIER" | tr '[:upper:]' '[:lower:]' | tr '/' '-')
  fi
  TASK_DIR="$TASKS_DIR/$TASK_SLUG"
  PROGRESS_FILE="$TASK_DIR/progress.json"
  BRANCH="linear-$TASK_SLUG"

  echo "📝 Issue: $ISSUE_TITLE"
  echo "🔗 $ISSUE_URL"
  echo "🏷️  identifier=$ISSUE_IDENTIFIER task_slug=$TASK_SLUG job_key=$JOB_KEY"

  mkdir -p "$TASK_DIR"
  write_linear_task_meta_env "$TASK_DIR" "$ISSUE_IDENTIFIER" "$TASK_SLUG" "$BRANCH" "$ISSUE_URL" "$ISSUE_ID"
  jq -n \
    --arg id "$ISSUE_ID" \
    --arg identifier "$ISSUE_IDENTIFIER" \
    --arg title "$ISSUE_TITLE" \
    --arg description "$BODY" \
    --arg url "$ISSUE_URL" \
    --arg state "$ISSUE_STATE" \
    --arg state_id "$ISSUE_STATE_ID" \
    --arg task_slug "$TASK_SLUG" \
    --arg job_key "$JOB_KEY" \
    '{
      id: $id,
      identifier: $identifier,
      title: $title,
      description: $description,
      url: $url,
      state: {name: $state, id: $state_id},
      task_slug: $task_slug,
      job_key: $job_key,
      provider: "linear"
    }' > "$TASK_DIR/issue-context.json"

  ensure_linear_task_progress_file "$PROGRESS_FILE" "$ISSUE_IDENTIFIER" "$TASK_SLUG" "$BRANCH"

  # Use Linear internal UUID when available for GraphQL mutations; fall back to identifier.
  local mutation_issue_id=${ISSUE_ID:-$ISSUE_IDENTIFIER}

  ensure_linear_checkpoint_stage research \
    "$ISSUE_IDENTIFIER" "$mutation_issue_id" "$TASK_SLUG" "$TASK_DIR" \
    "$ISSUE_TITLE" "$BODY" "$ISSUE_URL" "$PROGRESS_FILE" || return 1

  ensure_linear_checkpoint_stage plan \
    "$ISSUE_IDENTIFIER" "$mutation_issue_id" "$TASK_SLUG" "$TASK_DIR" \
    "$ISSUE_TITLE" "$BODY" "$ISSUE_URL" "$PROGRESS_FILE" || return 1

  ISSUE_WORKTREE_DIR=$(prepare_issue_worktree "$BRANCH" "$TASK_SLUG") || return 1
  CURRENT_ISSUE_WORKTREE="$ISSUE_WORKTREE_DIR"
  echo "🌿 Linear worktree ready: $ISSUE_WORKTREE_DIR"

  # Ensure provider context for decision_gate + linear_flow (provider-aware).
  GRKR_ISSUE_PROVIDER=linear
  export GRKR_ISSUE_PROVIDER

  # Decision gate (reuses existing provider-aware gate + linear_flow for refuse).
  decision_prompt_file=$(mktemp "${TMPDIR:-/tmp}/grkr-decision-prompt.XXXXXX")
  decision_output_file=$(mktemp "${TMPDIR:-/tmp}/grkr-decision-output.XXXXXX")
  write_decision_prompt_file "$decision_prompt_file" "$ISSUE_IDENTIFIER" "$ISSUE_TITLE" "$ISSUE_URL" "$BODY" "$TASK_SLUG" "$ISSUE_WORKTREE_DIR"
  run_codex_prompt "$decision_prompt_file" "$decision_output_file" "decide whether to implement the issue" replace "$ISSUE_WORKTREE_DIR"
  decision=$(run_decision_gate "$ISSUE_IDENTIFIER" "$decision_output_file" "$PROGRESS_FILE" "$TASK_SLUG" "$ISSUE_WORKTREE_DIR" "$decision_prompt_file" || echo "")
  decision=$(printf '%s' "$decision" | tr -d '\r\n' | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  case "$decision" in
    proceed|refuse)
      IMPLEMENTATION_DECISION=$decision
      ;;
    *)
      echo "❌ Decision gate for Linear $ISSUE_IDENTIFIER returned an invalid result."
      rm -f "$decision_prompt_file" "$decision_output_file"
      return 1
      ;;
  esac
  rm -f "$decision_prompt_file" "$decision_output_file"

  if [ "$decision" != "proceed" ]; then
    # Refusal side effects (checkpoint, planned Backlog mutation, progress refused) already performed
    # inside decision_gate via linear_flow. Clean local worktree only.
    if [ -n "${ISSUE_WORKTREE_DIR:-}" ]; then
      cleanup_issue_worktree "$ISSUE_WORKTREE_DIR"
      echo "🧹 Removed Linear worktree: $ISSUE_WORKTREE_DIR"
    fi
    CURRENT_ISSUE_WORKTREE=""
    echo "⏸️ Refused Linear issue $ISSUE_IDENTIFIER at decision gate."
    echo "TASK_DIR=$TASK_DIR"
    return 0
  fi

  # Proceed: plan In Progress state mutation (dry-run), then run implement codex.
  # Use ISSUE_STATE_ID as a candidate if it represents the target; prefer explicit LINEAR_STATE_IMPLEMENTATION_ID.
  local impl_state_id=${LINEAR_STATE_IMPLEMENTATION_ID:-${ISSUE_STATE_ID:-}}
  ensure_linear_implement_in_progress \
    "$ISSUE_IDENTIFIER" "$mutation_issue_id" "$TASK_SLUG" "$TASK_DIR" \
    "$PROGRESS_FILE" "$impl_state_id"

  # Implement codex (mirrors GitHub process_issue path; no gh, no test, no publish in this slice).
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
    # Reuse the already-Liner-aware refusal checkpoint helper (no dupe logic).
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
    return 0
  fi

  # Success path: test stage (exec in worktree, test.md + In Review dry-run), then
  # publish+complete (PR from linear-* + mark complete + Done/comment dry-run). GitHub path untouched.
  ensure_linear_test_checkpoint \
    "$ISSUE_IDENTIFIER" "$mutation_issue_id" "$TASK_SLUG" "$TASK_DIR" \
    "$ISSUE_TITLE" "$PROGRESS_FILE" || {
      CURRENT_ISSUE_WORKTREE=""
      return 1
  }
  # keep CURRENT set for publish; defer rm of prompt until after publish (remediation may need it)
  echo "✅ Linear test stage complete for $ISSUE_IDENTIFIER (decision=proceed; test mutations planned; test.md written)."
  ensure_linear_publish_complete \
    "$ISSUE_IDENTIFIER" "$mutation_issue_id" "$TASK_SLUG" "$TASK_DIR" \
    "$ISSUE_TITLE" "$ISSUE_URL" "$BODY" "$codex_output_file" "$BRANCH" \
    "$PROGRESS_FILE" "$prompt_file" || {
      CURRENT_ISSUE_WORKTREE=""
      rm -f "$prompt_file"
      CURRENT_PROMPT_FILE=""
      return 1
  }
  CURRENT_ISSUE_WORKTREE=""
  rm -f "$prompt_file"
  CURRENT_PROMPT_FILE=""
  echo "✅ Linear publish + complete planned for $ISSUE_IDENTIFIER"
  echo "STAGE=complete"
  echo "TASK_DIR=$TASK_DIR"
  echo "WORKTREE=$ISSUE_WORKTREE_DIR"
  return 0
}
