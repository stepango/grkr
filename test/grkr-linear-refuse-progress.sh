#!/bin/bash
# Linear refuse progress path (t_503ca0f3): plans commentCreate + Backlog state
# mutations, writes refusal.md, updates progress.json. Dry-run only (no live Linear).
# Does not rewire worker-refuse CLI; does not call gh project item-edit.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/grkr-linear-refuse.XXXXXX")
trap 'rm -rf "$tmpdir"' EXIT

mkdir -p "$tmpdir/bin" "$tmpdir/.grkr/tasks/eng-123" "$tmpdir/home"
bash "$repo_root/test/test-copy-grkr-lib.sh" "$tmpdir"

gh_log="$tmpdir/gh.log"
: >"$gh_log"
cat >"$tmpdir/bin/gh" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$gh_log"
echo "UNEXPECTED gh during linear refuse progress" >&2
exit 99
EOF
chmod +x "$tmpdir/bin/gh"

# Stubs for helpers expected when linear_issue.sh is sourced outside bin/grkr
SCRIPT_DIR="$tmpdir"
run_progress_cli() {
  local prj="$repo_root"
  (cd "$prj" && gleam run --no-print-progress -m grkr/progress/cli -- "$@")
}

# shellcheck source=/dev/null
. "$tmpdir/lib/task_progress.sh"
# shellcheck source=/dev/null
. "$tmpdir/lib/linear_issue.sh"

task_dir="$tmpdir/.grkr/tasks/eng-123"
progress_file="$task_dir/progress.json"

# Seed Linear-shaped progress.json (post research/plan MVP)
jq -n \
  --arg started "2026-07-12T00:00:00Z" \
  '{
    provider: "linear",
    issue_identifier: "ENG-123",
    task_slug: "eng-123",
    branch: "linear-eng-123",
    status: "planning",
    decision: "undecided",
    stages: {
      research: {status: "done"},
      plan: {status: "done"},
      implement_or_refuse: {status: "pending"},
      test: {status: "pending"}
    },
    started_at: $started,
    updated_at: $started
  }' >"$progress_file"

PATH="$tmpdir/bin:$PATH" \
  GRKR_GLEAM_PROJECT_ROOT="$repo_root" \
  ensure_linear_refusal_checkpoint \
    "ENG-123" \
    "LIN-001" \
    "eng-123" \
    "$task_dir" \
    "$progress_file" \
    "underspecified" \
    "Acceptance criteria are not specific enough." \
    "STATE-BACKLOG-UUID"

[ -f "$task_dir/refusal.md" ]
grep -F '<!-- grkr:checkpoint stage=refusal task=eng-123 version=1 -->' "$task_dir/refusal.md" >/dev/null
grep -F 'underspecified' "$task_dir/refusal.md" >/dev/null
grep -F 'Acceptance criteria are not specific enough.' "$task_dir/refusal.md" >/dev/null

[ -f "$task_dir/refusal.linear-mutation.txt" ]
grep -F 'commentCreate' "$task_dir/refusal.linear-mutation.txt" >/dev/null
grep -F 'grkr-checkpoint-refusal-eng-123' "$task_dir/refusal.linear-mutation.txt" >/dev/null

[ -f "$task_dir/refusal.linear-state-mutation.txt" ]
grep -F 'issueUpdate' "$task_dir/refusal.linear-state-mutation.txt" >/dev/null
grep -F 'STATE-BACKLOG-UUID' "$task_dir/refusal.linear-state-mutation.txt" >/dev/null

[ -f "$task_dir/refusal.linear-plan.txt" ]
grep -F 'TARGET_STATE=Backlog' "$task_dir/refusal.linear-plan.txt" >/dev/null
grep -F 'STATE_MUTATION_PLANNED=1' "$task_dir/refusal.linear-plan.txt" >/dev/null

jq -e '.provider == "linear" and .issue_identifier == "ENG-123"' "$progress_file" >/dev/null
jq -e '.status == "refused" and .decision == "refuse"' "$progress_file" >/dev/null
jq -e '.stages.implement_or_refuse.status == "done"' "$progress_file" >/dev/null
jq -e '.stages.implement_or_refuse.reason_class == "underspecified"' "$progress_file" >/dev/null
jq -e '.stages.test.status == "skipped"' "$progress_file" >/dev/null
# comment_id may be string idempotency key until live mutate
jq -e '.stages.implement_or_refuse.comment_id != null' "$progress_file" >/dev/null

# Idempotent resume: second call reuses files
PATH="$tmpdir/bin:$PATH" \
  GRKR_GLEAM_PROJECT_ROOT="$repo_root" \
  ensure_linear_refusal_checkpoint \
    "ENG-123" \
    "LIN-001" \
    "eng-123" \
    "$task_dir" \
    "$progress_file" \
    "underspecified" \
    "Acceptance criteria are not specific enough." \
    "STATE-BACKLOG-UUID"

jq -e '.status == "refused"' "$progress_file" >/dev/null

# No GitHub project/issue mutations
if [ -s "$gh_log" ]; then
  echo "Unexpected gh invocations during linear refuse progress:" >&2
  cat "$gh_log" >&2
  exit 1
fi

# progress CLI surface for plan-linear-refusal
cli_out=$(cd "$repo_root" && gleam run --no-print-progress -m grkr/progress/cli -- \
  plan-linear-refusal LIN-001 eng-123 other "cli reason")
printf '%s\n' "$cli_out" | grep -F 'TARGET_STATE=Backlog' >/dev/null
printf '%s\n' "$cli_out" | grep -F 'COMMENT_IDEMPOTENCY_KEY=grkr-checkpoint-refusal-eng-123' >/dev/null
printf '%s\n' "$cli_out" | grep -F 'STATE_MUTATION_PLANNED=0' >/dev/null
printf '%s\n' "$cli_out" | grep -F -- '---BODY---' >/dev/null

# --- Apply invocation tests (BLOCKER fix verification) ---
# Use GRKR_LINEAR_APPLY_CMD stub to count exactly one apply per dump on refuse paths.
# Covers: shell ensure_linear_refusal_checkpoint, and Gleam linear_flow (refusal/cli + decision gate).

APPLY_LOG="$tmpdir/apply-invocations.log"
: >"$APPLY_LOG"
export APPLY_LOG

APPLY_STUB="$tmpdir/bin/linear-apply-stub"
cat >"$APPLY_STUB" <<'STUBSCRIPT'
#!/bin/bash
set -euo pipefail
dump="$1"
printf '%s\n' "$dump" >> "${APPLY_LOG:-/tmp/grkr-apply.log}"
sidecar="${dump}.linear-apply-result.txt"
key=$(tail -n1 "$dump" 2>/dev/null | tr -d '\n' || echo "k-stub")
if [[ "$dump" == *"state-mutation"* ]]; then
  echo "LINEAR_MUTATE=applied key=$key state_id=sid-stub"
  printf 'key=%s status=applied state_id=sid-stub\n' "$key" > "$sidecar"
else
  echo "LINEAR_MUTATE=applied key=$key comment_id=cid-stub"
  printf 'key=%s status=applied comment_id=cid-stub\n' "$key" > "$sidecar"
fi
exit 0
STUBSCRIPT
chmod +x "$APPLY_STUB"

# Fresh task dir for apply-counting runs (avoid resume early-out)
task_dir2="$tmpdir/.grkr/tasks/eng-apply1"
mkdir -p "$task_dir2"
progress2="$task_dir2/progress.json"
jq -n \
  --arg started "2026-07-14T00:00:00Z" \
  '{
    provider: "linear",
    issue_identifier: "ENG-APPLY1",
    task_slug: "eng-apply1",
    branch: "linear-eng-apply1",
    status: "planning",
    decision: "undecided",
    stages: { research: {status:"done"}, plan: {status:"done"}, implement_or_refuse: {status:"pending"}, test: {status:"pending"} },
    started_at: $started, updated_at: $started
  }' >"$progress2"

# Test 1: shell ensure path under stub -> exactly one apply per written dump (comment + state)
: >"$APPLY_LOG"
PATH="$tmpdir/bin:$PATH" \
  GRKR_GLEAM_PROJECT_ROOT="$repo_root" \
  GRKR_LINEAR_APPLY_CMD="$APPLY_STUB" \
  ensure_linear_refusal_checkpoint \
    "ENG-APPLY1" "LIN-XYZ" "eng-apply1" "$task_dir2" "$progress2" \
    "underspecified" "test single apply" "STATE-BACKLOG-UUID"

# Expect 2 lines in log (one for comment dump, one for state dump)
apply_count=$(wc -l < "$APPLY_LOG" | tr -d ' ')
if [ "$apply_count" -ne 2 ]; then
  echo "FAIL: shell refuse ensure expected 2 apply invocations, got $apply_count" >&2
  cat "$APPLY_LOG" >&2
  exit 1
fi
[ -f "$task_dir2/refusal.linear-mutation.txt.linear-apply-result.txt" ]
[ -f "$task_dir2/refusal.linear-state-mutation.txt.linear-apply-result.txt" ]
grep -q 'status=applied' "$task_dir2/refusal.linear-mutation.txt.linear-apply-result.txt"

# Test 2: Gleam linear refuse path (decision gate / refusal/cli) under stub + MUTATE
# Uses envs to avoid network/fetch; GRKR_ISSUE_PROVIDER=linear triggers linear_flow
task_dir3="$tmpdir/.grkr/tasks/eng-apply2"
mkdir -p "$task_dir3"
progress3="$task_dir3/progress.json"
jq -n \
  --arg started "2026-07-14T00:00:00Z" \
  '{
    provider: "linear",
    issue_identifier: "ENG-APPLY2",
    task_slug: "eng-apply2",
    branch: "linear-eng-apply2",
    status: "planning",
    decision: "undecided",
    stages: { research: {status:"done"}, plan: {status:"done"}, implement_or_refuse: {status:"pending"}, test: {status:"pending"} },
    started_at: $started, updated_at: $started
  }' >"$progress3"

: >"$APPLY_LOG"
# Run via direct gleam cli entry for linear provider (exercises run_refusal_linear + apply calls)
set +e
GRKR_GLEAM_PROJECT_ROOT="$repo_root" \
GRKR_ISSUE_PROVIDER=linear \
ISSUE_TITLE="Apply Test Refusal" \
ISSUE_ID="ENG-APPLY2" \
LINEAR_BACKLOG_STATE_ID="STATE-BACKLOG-UUID" \
TASKS_DIR="$tmpdir/.grkr/tasks" \
GRKR_LINEAR_MUTATE=1 \
GRKR_LINEAR_APPLY_CMD="$APPLY_STUB" \
  gleam run --no-print-progress -m grkr/refusal/cli -- "ENG-APPLY2" "underspecified" "gleam path single apply test" \
  >"$tmpdir/refusal-cli.out" 2>&1
gleam_cli_status=$?
set -e
if [ $gleam_cli_status -ne 0 ]; then
  echo "Gleam refusal cli failed (status=$gleam_cli_status); output:" >&2
  cat "$tmpdir/refusal-cli.out" >&2
  exit 1
fi

apply_count3=$(wc -l < "$APPLY_LOG" | tr -d ' ')
if [ "$apply_count3" -ne 2 ]; then
  echo "FAIL: Gleam linear refuse expected 2 apply invocations (comment+state), got $apply_count3" >&2
  echo "=== apply log ===" >&2; cat "$APPLY_LOG" >&2
  echo "=== cli out ===" >&2; cat "$tmpdir/refusal-cli.out" >&2
  exit 1
fi
[ -f "$task_dir3/refusal.linear-mutation.txt" ]
[ -f "$task_dir3/refusal.linear-state-mutation.txt" ]
[ -f "$task_dir3/refusal.linear-mutation.txt.linear-apply-result.txt" ]
grep -q 'status=applied' "$task_dir3/refusal.linear-mutation.txt.linear-apply-result.txt" || {
  echo "missing sidecar status on Gleam path" >&2; exit 1
}

# Verify default dry-run (no MUTATE, no APPLY_CMD stub) unchanged: no sidecar created by apply.
# (dry path returns marker without writing sidecar; only live/override paths write them via stub or do_apply)
task_dir4="$tmpdir/.grkr/tasks/eng-dry"
mkdir -p "$task_dir4"
progress4="$task_dir4/progress.json"
jq -n \
  --arg started "2026-07-14T00:00:00Z" \
  '{ provider: "linear", issue_identifier: "ENG-DRY", task_slug: "eng-dry", status: "planning", decision: "undecided",
     stages: { research: {status:"done"}, plan: {status:"done"}, implement_or_refuse: {status:"pending"}, test: {status:"pending"} },
     started_at: $started, updated_at: $started }' >"$progress4"

unset GRKR_LINEAR_MUTATE
unset GRKR_LINEAR_APPLY_CMD
GRKR_GLEAM_PROJECT_ROOT="$repo_root" \
GRKR_ISSUE_PROVIDER=linear \
ISSUE_TITLE="Dry Test" \
ISSUE_ID="ENG-DRY" \
LINEAR_BACKLOG_STATE_ID="STATE-BACKLOG-UUID" \
TASKS_DIR="$tmpdir/.grkr/tasks" \
  gleam run --no-print-progress -m grkr/refusal/cli -- "ENG-DRY" "other" "dry default test" \
  >"$tmpdir/refusal-dry.out" 2>&1 || true

dry_sidecar="$task_dir4/refusal.linear-mutation.txt.linear-apply-result.txt"
if [ -f "$dry_sidecar" ]; then
  echo "FAIL: default dry-run (no MUTATE) created apply sidecar: $dry_sidecar" >&2
  cat "$dry_sidecar" >&2
  exit 1
fi
# Also the state sidecar should not exist for this run
if [ -f "$task_dir4/refusal.linear-state-mutation.txt.linear-apply-result.txt" ]; then
  echo "FAIL: default dry-run created state sidecar unexpectedly" >&2
  exit 1
fi
# Confirm dumps were still written (plan side)
[ -f "$task_dir4/refusal.linear-mutation.txt" ] || { echo "dry path must still write dumps"; exit 1; }

printf 'grkr linear refuse progress test passed\n'
