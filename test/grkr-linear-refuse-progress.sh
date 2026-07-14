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

printf 'grkr linear refuse progress test passed\n'
