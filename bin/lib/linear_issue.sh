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

# Parse KEY="value" shell assignments from gleam stdout into named vars via eval-safe source.
# Only accepts known keys; values already shell-quoted by the Gleam emitter.
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
        val=${line#*=}
        # Strip surrounding double quotes if present
        if [ "${val#\"}" != "$val" ] && [ "${val%\"}" != "$val" ]; then
          val=${val#\"}
          val=${val%\"}
          val=${val//\\\"/\"}
          val=${val//\\\\/\\}
        fi
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
  echo "🌿 Linear MVP worktree ready: $ISSUE_WORKTREE_DIR"
  echo "✅ Linear MVP complete for $ISSUE_IDENTIFIER (research+plan only; implement/test/PR deferred)."
  echo "MVP_STAGE=plan"
  echo "TASK_DIR=$TASK_DIR"
  echo "WORKTREE=$ISSUE_WORKTREE_DIR"
  return 0
}
