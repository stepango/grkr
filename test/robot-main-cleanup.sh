#!/bin/bash
set -euo pipefail

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/grkr-robot-main-cleanup.XXXXXX")
trap 'rm -rf "$tmpdir"' EXIT

cp bin/robot-main.sh "$tmpdir/robot-main.sh"
cp bin/worker-sync-main.sh "$tmpdir/worker-sync-main.sh"
cp bin/worker-pick-issue.sh "$tmpdir/worker-pick-issue.sh"
cp bin/doctor.sh "$tmpdir/doctor.sh"
chmod +x "$tmpdir/robot-main.sh" "$tmpdir/worker-sync-main.sh" "$tmpdir/worker-pick-issue.sh" "$tmpdir/doctor.sh"

real_git=$(command -v git)
mkdir -p "$tmpdir/bin" "$tmpdir/.grkr/state" "$tmpdir/.grkr/locks" "$tmpdir/.grkr/logs/jobs" "$tmpdir/.grkr/tasks" "$tmpdir/.grkr/worktrees"
git_log="$tmpdir/git.log"

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
FAILED_WORKTREE_TTL_SECS="1"
COMPLETED_WORKTREE_TTL_SECS="1"
EOF

make_task() {
  local slug=$1
  local issue_number=$2
  local status=$3
  local updated_at=$4

  mkdir -p "$tmpdir/.grkr/tasks/$slug" "$tmpdir/.grkr/worktrees/$slug"
  cat > "$tmpdir/.grkr/tasks/$slug/progress.json" <<EOF
{"issue_number":$issue_number,"task_slug":"$slug","status":"$status","updated_at":"$updated_at","stages":{"research":{"status":"done"},"plan":{"status":"done"},"implement_or_refuse":{"status":"done"},"test":{"status":"done"}}}
EOF
  touch -t 202401010000 "$tmpdir/.grkr/tasks/$slug/progress.json" "$tmpdir/.grkr/worktrees/$slug"
  if [ "$issue_number" != "0" ]; then
    printf 'log for %s\n' "$slug" > "$tmpdir/.grkr/logs/jobs/issue-$issue_number-execution.log"
    touch -t 202401010000 "$tmpdir/.grkr/logs/jobs/issue-$issue_number-execution.log"
  fi
}

make_task issue-1-complete 1 complete 2024-01-01T00:00:00Z
make_task issue-2-refused 2 refused 2024-01-01T00:00:00Z
make_task issue-3-failed 3 failed 2024-01-01T00:00:00Z
mkdir -p "$tmpdir/.grkr/worktrees/orphan-task"
touch -t 202401010000 "$tmpdir/.grkr/worktrees/orphan-task"

cat > "$tmpdir/bin/gh" <<'EOF'
#!/bin/bash
case "$1 $2" in
  'auth status') exit 0 ;;
  'api user') printf 'robot\n' ;;
  'project item-list') printf '{"items":[]}\n' ;;
  'project field-list') printf '[]\n' ;;
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
  'fetch origin main --prune') printf 'fetch\n' >> "$git_log" ;;
  'checkout main') printf 'checkout\n' >> "$git_log" ;;
  'reset --hard origin/main') printf 'reset\n' >> "$git_log" ;;
  *) exec "$real_git" "\$@" ;;
esac
EOF

chmod +x "$tmpdir/bin/gh" "$tmpdir/bin/codex" "$tmpdir/bin/git" "$tmpdir/bin/timeout" "$tmpdir/bin/flock"

output_file="$tmpdir/output.log"
(
  cd "$tmpdir"
  PATH="$tmpdir/bin:$PATH" HOME="$tmpdir/home" GRKR_MAX_TICKS=10 bash "$tmpdir/robot-main.sh" >"$output_file" 2>&1
)

[ ! -d "$tmpdir/.grkr/worktrees/issue-1-complete" ]
[ ! -d "$tmpdir/.grkr/worktrees/issue-2-refused" ]
[ ! -d "$tmpdir/.grkr/worktrees/issue-3-failed" ]
[ ! -d "$tmpdir/.grkr/worktrees/orphan-task" ]
[ -f "$tmpdir/.grkr/tasks/issue-1-complete/progress.json" ]
[ -f "$tmpdir/.grkr/tasks/issue-2-refused/progress.json" ]
[ -f "$tmpdir/.grkr/tasks/issue-3-failed/progress.json" ]
grep -F 'purged_completed_worktrees=1' "$output_file" >/dev/null
grep -F 'purged_failed_worktrees=1' "$output_file" >/dev/null
grep -F 'purged_refused_worktrees=1' "$output_file" >/dev/null
grep -F 'purged_orphaned_worktrees=1' "$output_file" >/dev/null
grep -F 'purged_job_logs=3' "$output_file" >/dev/null

