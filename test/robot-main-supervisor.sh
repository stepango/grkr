#!/bin/bash
set -euo pipefail

repo_root=$(pwd)
tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/grkr-robot-main.XXXXXX")
trap 'rm -rf "$tmpdir"' EXIT

cp bin/robot-main.sh "$tmpdir/robot-main.sh"
mkdir -p "$tmpdir/bin"
cp bin/worker-sync-main.sh "$tmpdir/bin/worker-sync-main.sh"
cp bin/worker-pick-issue.sh "$tmpdir/bin/worker-pick-issue.sh"
cp bin/grkr-task-slug.sh "$tmpdir/grkr-task-slug.sh"
cp bin/doctor.sh "$tmpdir/doctor.sh"
cp bin/doctor.sh "$tmpdir/bin/doctor.sh"
chmod +x "$tmpdir/robot-main.sh" "$tmpdir/bin/worker-sync-main.sh" "$tmpdir/bin/worker-pick-issue.sh" "$tmpdir/doctor.sh" "$tmpdir/bin/doctor.sh"

real_git=$(command -v git)
mkdir -p "$tmpdir/bin" "$tmpdir/.grkr/state" "$tmpdir/.grkr/locks"
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
EOF

cat > "$tmpdir/.grkr/state/active_jobs.json" <<'EOF'
{
  "issue:77:execution": {
    "pid": 999999,
    "entity_type": "issue",
    "entity_id": "77",
    "lock_name": "issue-77"
  }
}
EOF

touch "$tmpdir/.grkr/locks/issue-77.lock"

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
  PATH="$tmpdir/bin:$PATH" HOME="$tmpdir/home" GRKR_ROOT="$tmpdir" GRKR_CONFIG_FILE="$tmpdir/.grkr/config.sh" GRKR_GLEAM_PROJECT_ROOT="$repo_root" GRKR_MAX_TICKS=1 GRKR_FAIL_PHASES=scan_comment_commands bash "$tmpdir/robot-main.sh" >"$output_file" 2>&1
)

[ -f "$tmpdir/.grkr/logs/main.log" ]
[ -f "$tmpdir/.grkr/logs/loop.log" ]

grep -F '{}' "$tmpdir/.grkr/state/active_jobs.json" >/dev/null
grep -F 'stale_job pid=999999 recovered=true' "$tmpdir/.grkr/logs/loop.log" >/dev/null
grep -F 'phase=sync_main' "$tmpdir/.grkr/logs/loop.log" >/dev/null
grep -F 'phase=scan_comment_commands' "$tmpdir/.grkr/logs/loop.log" >/dev/null
grep -F 'phase_failed:scan_comment_commands:64' "$tmpdir/.grkr/logs/loop.log" >/dev/null
grep -F 'phase=pick_and_schedule_issue_execution' "$tmpdir/.grkr/logs/loop.log" >/dev/null
grep -F 'no_candidate=true' "$tmpdir/.grkr/logs/loop.log" >/dev/null
grep -F 'sleep_secs=0' "$tmpdir/.grkr/logs/loop.log" >/dev/null

grep -F 'fetch' "$git_log" >/dev/null
grep -F 'checkout' "$git_log" >/dev/null
grep -F 'reset' "$git_log" >/dev/null
