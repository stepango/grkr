# bin/lib/linear_issue.sh
# Linear --linear-issue MVP helpers for bin/grkr (research + plan only).
# Loads Linear issue context via Gleam issue_provider fetch-issue (fixture or live).
# Posts/plans checkpoints via progress/cli linear-comment-mutation + existing templates.
# No GitHub gh issue view. Implement/test/PR stages deferred past MVP.

linear_issue_project_root() {
  printf '%s\n' "${GRKR_GLEAM_PROJECT_ROOT:-$(dirname "$SCRIPT_DIR")}"
}

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
# Optional GRKR_LINEAR_MUTATE=1 may attempt live GraphQL later; currently dry-run only.
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
    echo "🔑 $stage mutation idempotency_key=$idempotency_key (dry-run; set GRKR_LINEAR_MUTATE=1 when live apply lands)"
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
      state_mut=$(run_progress_cli linear-state-mutation "$linear_issue_id" "$state_id" 2>/dev/null) || state_mut=""
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

  echo "🔑 refuse comment idempotency_key=${comment_key:-unknown} target_state=${target_state:-Backlog} (dry-run; set GRKR_LINEAR_MUTATE=1 when live apply lands)"
  # comment_id in progress uses idempotency key string until live mutate returns real id
  mark_task_progress_refused "$progress_file" "$reason_class" "${comment_key:-}"
  echo "✅ Linear refuse progress planned for $identifier (no live Linear mutations by default)."
}

# Plan Linear "In Progress" state mutation (dry-run) for implement stage.
# Writes implement.linear-state-mutation.txt (when state id available) + logs.
# Updates progress implement_or_refuse to done (parity after proceed decision).
# Does not perform live GraphQL; GRKR_LINEAR_MUTATE has no effect in this slice.
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
    mutation_out=$(run_progress_cli linear-state-mutation "$linear_issue_id" "$state_id" 2>/dev/null) || mutation_out=""
  else
    mutation_out=""
  fi

  if [ -n "$mutation_out" ]; then
    idempotency_key=$(printf '%s\n' "$mutation_out" | tail -n1)
    printf '%s\n' "$mutation_out" > "$mutation_file"
    echo "🔑 implement state mutation idempotency_key=$idempotency_key (dry-run; set GRKR_LINEAR_MUTATE=1 when live apply lands)"
  else
    # Name-only record for dry-run when no concrete state id is known
    {
      printf 'TARGET_STATE=%s\n' "$target_state"
      printf 'STATE_MUTATION_PLANNED=0\n'
    } > "$mutation_file"
    echo "🔑 implement state target=$target_state (dry-run; no state id provided; set GRKR_LINEAR_MUTATE=1 when live apply lands)"
  fi

  # Mark implement_or_refuse done (decision gate already set decision=proceed)
  update_task_progress_stage "$progress_file" "implement_or_refuse" "done" "${idempotency_key:-}"
  echo "✅ Linear implement In Progress mutation planned for $identifier (worktree left for subsequent stages)."
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

  # Success path for implement slice: progress already marked done by ensure_linear_implement_in_progress.
  # Leave worktree and implementation.log for subsequent stages (test/publish deferred).
  CURRENT_ISSUE_WORKTREE="$ISSUE_WORKTREE_DIR"
  rm -f "$prompt_file"
  CURRENT_PROMPT_FILE=""
  echo "✅ Linear implement stage complete for $ISSUE_IDENTIFIER (decision=proceed; In Progress mutation planned; implementation.log written)."
  echo "STAGE=implement"
  echo "TASK_DIR=$TASK_DIR"
  echo "WORKTREE=$ISSUE_WORKTREE_DIR"
  return 0
}
