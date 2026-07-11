#!/bin/bash
set -euo pipefail

repo_root=$(pwd)
tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/grkr-robot-main-schedule.XXXXXX")
trap 'rm -rf "$tmpdir"' EXIT

cp bin/robot-main.sh "$tmpdir/robot-main.sh"
cp bin/doctor.sh "$tmpdir/doctor.sh"
chmod +x "$tmpdir/robot-main.sh" "$tmpdir/doctor.sh"

real_git=$(command -v git)
mkdir -p "$tmpdir/bin" "$tmpdir/.grkr/state" "$tmpdir/.grkr/locks"
runner_log="$tmpdir/grkr.log"

cat > "$tmpdir/bin/worker-sync-main.sh" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$tmpdir/bin/worker-sync-main.sh"

cat > "$tmpdir/.grkr/config.sh" <<'EOF'
REPO="stepango/grkr"
MAIN_BRANCH="main"
PROJECT_OWNER="stepango"
PROJECT_NUMBER="1"
STATUS_FIELD_NAME="Status"
TODO_VALUE="Todo"
BACKLOG_VALUE="Backlog"
PRIORITY_FIELD_NAME="Priority"
LOOP_INTERVAL_SECS="0"
EOF

printf '{}\n' > "$tmpdir/.grkr/state/active_jobs.json"

cat > "$tmpdir/grkr" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$runner_log"
exit 0
EOF

cat > "$tmpdir/bin/gh" <<'EOF'
#!/bin/bash
case "$1 $2" in
  'auth status') exit 0 ;;
  *) exit 0 ;;
esac
EOF

cat > "$tmpdir/bin/codex" <<'EOF'
#!/bin/bash
case "${1-}" in
  --help) exit 0 ;;
  *) exit 0 ;;
esac
EOF

cat > "$tmpdir/bin/timeout" <<'EOF'
#!/bin/bash
exit 0
EOF

cat > "$tmpdir/bin/flock" <<'EOF'
#!/bin/bash
exit 0
EOF

cat > "$tmpdir/bin/git" <<EOF
#!/bin/bash
case "\$*" in
  'rev-parse --show-toplevel') printf '%s\n' "$tmpdir" ;;
  'remote get-url origin') printf 'git@github.com:stepango/grkr.git\n' ;;
  *) exec "$real_git" "\$@" ;;
esac
EOF

chmod +x "$tmpdir/grkr" "$tmpdir/bin/gh" "$tmpdir/bin/codex" "$tmpdir/bin/git" "$tmpdir/bin/timeout" "$tmpdir/bin/flock"

output_file="$tmpdir/output.log"
(
  cd "$tmpdir"
  PATH="$tmpdir/bin:$PATH" HOME="$tmpdir/home" \
    GRKR_GLEAM_PROJECT_ROOT="$repo_root" \
    GITHUB_FIXTURE_PATH="$repo_root/test/fixtures/github-project-items.json" \
    GRKR_ACTIVE_JOBS_PATH="$tmpdir/.grkr/state/active_jobs.json" \
    BOT_LOGIN=robot \
    GRKR_ISSUE_PROVIDER=github \
    GRKR_MAX_TICKS=1 bash "$tmpdir/robot-main.sh" >"$output_file" 2>&1
)

sleep 0.2

grep -F 'scheduled_jobs=1' "$tmpdir/.grkr/logs/loop.log" | grep -F 'selected_issue=42' >/dev/null
grep -F 'task_slug=issue-42-fixture-pick-issue' "$tmpdir/.grkr/logs/loop.log" >/dev/null
jq -e '.["issue:42:execution"].entity_type == "issue"' "$tmpdir/.grkr/state/active_jobs.json" >/dev/null
jq -e '.["issue:42:execution"].entity_id == "42"' "$tmpdir/.grkr/state/active_jobs.json" >/dev/null
jq -e '.["issue:42:execution"].lock_name == "issue-42"' "$tmpdir/.grkr/state/active_jobs.json" >/dev/null
jq -e '.["issue:42:execution"].task_slug == "issue-42-fixture-pick-issue"' "$tmpdir/.grkr/state/active_jobs.json" >/dev/null
jq -e '.["issue:42:execution"].project_item_id == "PVTI_pick1"' "$tmpdir/.grkr/state/active_jobs.json" >/dev/null
[ -f "$tmpdir/.grkr/logs/jobs/issue-42-execution.log" ]
[ -f "$tmpdir/.grkr/locks/issue-42.lock" ]

for _ in {1..20}; do
  if grep -F -- '--issue 42' "$runner_log" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

grep -F -- '--issue 42' "$runner_log" >/dev/null

printf '{}\n' > "$tmpdir/.grkr/state/active_jobs.json"
: > "$runner_log"

(
  cd "$tmpdir"
  PATH="$tmpdir/bin:$PATH" HOME="$tmpdir/home" \
    GRKR_GLEAM_PROJECT_ROOT="$repo_root" \
    GRKR_ISSUE_PROVIDER=linear \
    LINEAR_ASSIGNEE_ID=u1 \
    LINEAR_FIXTURE_PATH="$repo_root/test/fixtures/linear-assigned-issues.json" \
    GRKR_ACTIVE_JOBS_PATH="$tmpdir/.grkr/state/active_jobs.json" \
    GRKR_MAX_TICKS=1 bash "$tmpdir/robot-main.sh" >"$output_file" 2>&1
)

sleep 0.2

grep -F 'scheduled_jobs=1' "$tmpdir/.grkr/logs/loop.log" | grep -F 'selected_issue=ENG-123' >/dev/null
grep -F 'task_slug=eng-123' "$tmpdir/.grkr/logs/loop.log" >/dev/null
jq -e '.["linear:ENG-123:execution"].entity_type == "issue_linear"' "$tmpdir/.grkr/state/active_jobs.json" >/dev/null
jq -e '.["linear:ENG-123:execution"].entity_id == "ENG-123"' "$tmpdir/.grkr/state/active_jobs.json" >/dev/null
jq -e '.["linear:ENG-123:execution"].lock_name == "eng-123"' "$tmpdir/.grkr/state/active_jobs.json" >/dev/null
jq -e '.["linear:ENG-123:execution"].task_slug == "eng-123"' "$tmpdir/.grkr/state/active_jobs.json" >/dev/null
[ -f "$tmpdir/.grkr/logs/jobs/linear-ENG-123-execution.log" ]
[ -f "$tmpdir/.grkr/locks/eng-123.lock" ]

for _ in {1..20}; do
  if grep -F -- '--linear-issue ENG-123' "$runner_log" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

grep -F -- '--linear-issue ENG-123' "$runner_log" >/dev/null