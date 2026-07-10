#!/bin/bash
# Supervisor smoke: stale job recovery + phase fail injection + sync git mock.
# Isolated tmpdir fixture; scrub inherited GRKR_*/GLEAM_ENV so suite order / parallel
# cron workers cannot leak config into this script.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

# Drop kanban/cron/gleam overrides that npm-test parent (or worker shell) may export.
unset GLEAM_ENV 2>/dev/null || true
unset GRKR_ROOT GRKR_CONFIG_FILE GRKR_ACTIVE_JOBS_PATH GRKR_MAX_TICKS \
  GRKR_FAIL_PHASES GRKR_GLEAM_PROJECT_ROOT GRKR_ISSUE_PROVIDER \
  GITHUB_FIXTURE_PATH BOT_LOGIN 2>/dev/null || true

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/grkr-robot-main.XXXXXX")
trap 'rm -rf "$tmpdir"' EXIT

cp bin/robot-main.sh "$tmpdir/robot-main.sh"
mkdir -p "$tmpdir/bin" "$tmpdir/home" "$tmpdir/.grkr/state" "$tmpdir/.grkr/locks"
cp bin/worker-sync-main.sh "$tmpdir/bin/worker-sync-main.sh"
cp bin/worker-pick-issue.sh "$tmpdir/bin/worker-pick-issue.sh"
cp bin/grkr-task-slug.sh "$tmpdir/grkr-task-slug.sh"
cp bin/doctor.sh "$tmpdir/doctor.sh"
cp bin/doctor.sh "$tmpdir/bin/doctor.sh"
chmod +x "$tmpdir/robot-main.sh" "$tmpdir/bin/worker-sync-main.sh" \
  "$tmpdir/bin/worker-pick-issue.sh" "$tmpdir/doctor.sh" "$tmpdir/bin/doctor.sh"

real_git=$(command -v git)
git_log="$tmpdir/git.log"
output_file="$tmpdir/output.log"
loop_log="$tmpdir/.grkr/logs/loop.log"
active_jobs="$tmpdir/.grkr/state/active_jobs.json"

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

# Always-success flock so parallel host flock contention cannot fail this fixture.
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

chmod +x "$tmpdir/bin/gh" "$tmpdir/bin/codex" "$tmpdir/bin/git" \
  "$tmpdir/bin/timeout" "$tmpdir/bin/flock"

seed_fixture_state() {
  cat > "$active_jobs" <<'EOF'
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
  rm -rf "$tmpdir/.grkr/logs"
  : >"$git_log"
  : >"$output_file"
}

dump_failure() {
  local reason=$1
  {
    echo "robot-main-supervisor FAIL: $reason"
    echo "tmpdir=$tmpdir"
    echo "--- robot-main exit / output.log ---"
    cat "$output_file" 2>/dev/null || true
    echo "--- loop.log ---"
    cat "$loop_log" 2>/dev/null || true
    echo "--- active_jobs.json ---"
    cat "$active_jobs" 2>/dev/null || true
    echo "--- git.log ---"
    cat "$git_log" 2>/dev/null || true
  } >&2
}

# Run supervisor once; print exit code on stdout. Never aborts the outer script.
run_robot_main() {
  set +e
  (
    cd "$tmpdir"
    # Explicit env: avoid GLEAM_ENV=test short-circuit; pin github provider + paths.
    env -u GLEAM_ENV \
      PATH="$tmpdir/bin:$PATH" \
      HOME="$tmpdir/home" \
      GRKR_ROOT="$tmpdir" \
      GRKR_CONFIG_FILE="$tmpdir/.grkr/config.sh" \
      GRKR_GLEAM_PROJECT_ROOT="$repo_root" \
      GRKR_ACTIVE_JOBS_PATH="$active_jobs" \
      GRKR_ISSUE_PROVIDER=github \
      BOT_LOGIN=robot \
      GRKR_MAX_TICKS=1 \
      GRKR_FAIL_PHASES=scan_comment_commands \
      bash "$tmpdir/robot-main.sh" >"$output_file" 2>&1
  )
  local ec=$?
  set -e
  printf '%s\n' "$ec"
}

seed_fixture_state
robot_ec=$(run_robot_main)

# One retry for transient gleam compile/build lock contention under parallel workers.
if [ "$robot_ec" -ne 0 ]; then
  sleep 1
  seed_fixture_state
  robot_ec=$(run_robot_main)
fi

if [ "$robot_ec" -ne 0 ]; then
  dump_failure "robot-main exited $robot_ec after retry"
  exit "$robot_ec"
fi

assert_file() {
  if [ ! -f "$1" ]; then
    dump_failure "missing file: $1"
    exit 1
  fi
}

assert_grep() {
  local needle=$1
  local file=$2
  if ! grep -F "$needle" "$file" >/dev/null 2>&1; then
    dump_failure "missing grep -F $(printf %q "$needle") in $file"
    exit 1
  fi
}

assert_file "$tmpdir/.grkr/logs/main.log"
assert_file "$loop_log"

assert_grep '{}' "$active_jobs"
assert_grep 'stale_job pid=999999 recovered=true' "$loop_log"
assert_grep 'phase=sync_main' "$loop_log"
assert_grep 'phase=scan_comment_commands' "$loop_log"
assert_grep 'phase_failed:scan_comment_commands:64' "$loop_log"
assert_grep 'phase=pick_and_schedule_issue_execution' "$loop_log"
assert_grep 'no_candidate=true' "$loop_log"
assert_grep 'sleep_secs=0' "$loop_log"

assert_grep 'fetch' "$git_log"
assert_grep 'checkout' "$git_log"
assert_grep 'reset' "$git_log"
