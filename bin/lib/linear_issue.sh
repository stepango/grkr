# bin/lib/linear_issue.sh
# Linear --linear-issue helpers for bin/grkr (research + plan + decision + implement + test + publish+complete).
# Loads Linear issue context via Gleam issue_provider fetch-issue (fixture or live).
# Plans checkpoints via progress/cli; when GRKR_LINEAR_MUTATE=1 + token, applies after each dump (guarded).
# Default remains pure dry-run (identical logs/artifacts). GitHub PR from linear-*; Done + completion.
# GitHub default + all GitHub paths untouched. Live mutate writes sidecars + §8 markers.
#
# process_linear_issue is now a thin sequencer (final slice 5). Stage bodies + decision/implement
# orchestration live in linear_issue_stages.sh (slices 1-5). This file retains:
# process_linear_issue (thin), load_linear_issue_assignments, write_linear_task_meta_env,
# ensure_linear_task_progress_file, decode_shell_assignment_value, run_issue_provider_cli,
# linear_issue_project_root + sourcing of mutate+stages. Zero behavior change.

linear_issue_project_root() {
  printf '%s\n' "${GRKR_GLEAM_PROJECT_ROOT:-$(dirname "$SCRIPT_DIR")}"
}

# Source the guarded mutate apply helper (keeps this file under 1000 LOC per AGENTS.md).
# The helper is thin and provides maybe_apply_linear_mutation.
MUTATE_LIB_CANDIDATE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/linear_mutate.sh"
if [ -f "$MUTATE_LIB_CANDIDATE" ]; then
  . "$MUTATE_LIB_CANDIDATE"
fi

# Source extracted Linear stage bodies (sibling lib pattern). Slice 1: test checkpoint.
# Slice 2: publish+complete (ensure_linear_publish_complete moved to stages).
# Slice 3: refusal checkpoint (ensure_linear_refusal_checkpoint moved to stages).
# Slice 4: research/plan checkpoint + implement_in_progress (ensure_linear_checkpoint_stage + ensure_linear_implement_in_progress moved to stages).
# Slice 5: run_linear_decision_stage + handle_linear_decision_refuse + run_linear_implement_stage moved;
# process_linear_issue reduced to thin sequencer (bootstrap + ensure_* + run_* + handle + finalize).
# Must be after mutate so maybe_apply_linear_mutation is in scope at call time.
# Ambient resolution mirrors github_issue.sh verticals; call sites in process_linear_issue unchanged.
STAGES_LIB_CANDIDATE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/linear_issue_stages.sh"
if [ -f "$STAGES_LIB_CANDIDATE" ]; then
  . "$STAGES_LIB_CANDIDATE"
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

# Bootstrap: identifier/validation check, load assignments, set BODY/TASKS_DIR/TASK_DIR/PROGRESS/BRANCH,
# echo title/url/tags, mkdir + write meta + issue-context.json + ensure progress.
# Exact body moved from process_linear_issue. Sets same globals so downstream stages
# (ensure_*, run_linear_*) and shared code continue to work identically.
# (load_linear_issue_assignments, write_linear_task_meta_env, ensure_linear_task_progress_file
# and decode/run_provider stay in this file per preferred ownership.)
bootstrap_linear_issue_task() {
  local IDENTIFIER=$1
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
}

process_linear_issue() {
  local IDENTIFIER=$1
  LINEAR_IMPL_REFUSED=0
  bootstrap_linear_issue_task "$IDENTIFIER" || return 1
  # Use Linear internal UUID when available for GraphQL mutations; fall back to identifier.
  local mutation_issue_id=${ISSUE_ID:-$ISSUE_IDENTIFIER}

  ensure_linear_checkpoint_stage research \
    "$ISSUE_IDENTIFIER" "$mutation_issue_id" "$TASK_SLUG" "$TASK_DIR" \
    "$ISSUE_TITLE" "$BODY" "$ISSUE_URL" "$PROGRESS_FILE" || return 1

  ensure_linear_checkpoint_stage plan \
    "$ISSUE_IDENTIFIER" "$mutation_issue_id" "$TASK_SLUG" "$TASK_DIR" \
    "$ISSUE_TITLE" "$BODY" "$ISSUE_URL" "$PROGRESS_FILE" || return 1

  run_linear_decision_stage || return 1
  if [ "${IMPLEMENTATION_DECISION:-}" != "proceed" ]; then
    handle_linear_decision_refuse
    return 0
  fi

  run_linear_implement_stage || {
    CURRENT_ISSUE_WORKTREE=""
    return 1
  }
  if [ "${LINEAR_IMPL_REFUSED:-0}" = "1" ]; then
    return 0
  fi

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
    "$ISSUE_TITLE" "$ISSUE_URL" "$BODY" "$TASK_DIR/implementation.log" "$BRANCH" \
    "$PROGRESS_FILE" "$CURRENT_PROMPT_FILE" || {
      CURRENT_ISSUE_WORKTREE=""
      rm -f "$CURRENT_PROMPT_FILE"
      CURRENT_PROMPT_FILE=""
      return 1
  }
  # finalize tail (clear state, rm prompt, echo complete markers)
  CURRENT_ISSUE_WORKTREE=""
  rm -f "$CURRENT_PROMPT_FILE"
  CURRENT_PROMPT_FILE=""
  echo "✅ Linear publish + complete planned for $ISSUE_IDENTIFIER"
  echo "STAGE=complete"
  echo "TASK_DIR=$TASK_DIR"
  echo "WORKTREE=$ISSUE_WORKTREE_DIR"
  return 0
}
