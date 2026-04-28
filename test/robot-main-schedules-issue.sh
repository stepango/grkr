#!/bin/bash
set -euo pipefail

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/grkr-robot-main-schedule.XXXXXX")
trap 'rm -rf "$tmpdir"' EXIT

cp bin/robot-main.sh "$tmpdir/robot-main.sh"
cp bin/worker-sync-main.sh "$tmpdir/worker-sync-main.sh"
cp bin/doctor.sh "$tmpdir/doctor.sh"
chmod +x "$tmpdir/robot-main.sh" "$tmpdir/worker-sync-main.sh" "$tmpdir/doctor.sh"

real_git=$(command -v git)
mkdir -p "$tmpdir/bin" "$tmpdir/.grkr/state" "$tmpdir/.grkr/locks"
git_log="$tmpdir/git.log"
runner_log="$tmpdir/grkr.log"

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

cat > "$tmpdir/worker-pick-issue.sh" <<'EOF'
#!/bin/bash
cat <<'OUT'
SELECTED=1
ISSUE_NUMBER=5
JOB_KEY='issue:5:execution'
TASK_SLUG='issue-5-scheduled-by-supervisor'
PROJECT_ITEM_ID='ITEM_5'
ISSUE_TITLE='Scheduled issue'
ISSUE_UPDATED_AT='2026-03-30T00:00:00Z'
PRIORITY_NAME='P0'
PRIORITY_NUMBER=''
OUT
EOF

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
  'fetch origin main --prune') printf 'fetch\n' >> "$git_log" ;;
  'checkout main') printf 'checkout\n' >> "$git_log" ;;
  'reset --hard origin/main') printf 'reset\n' >> "$git_log" ;;
  *) exec "$real_git" "\$@" ;;
esac
EOF

chmod +x "$tmpdir/worker-pick-issue.sh" "$tmpdir/grkr" "$tmpdir/bin/gh" "$tmpdir/bin/codex" "$tmpdir/bin/git" "$tmpdir/bin/timeout" "$tmpdir/bin/flock"

output_file="$tmpdir/output.log"
(
  cd "$tmpdir"
  PATH="$tmpdir/bin:$PATH" HOME="$tmpdir/home" GRKR_MAX_TICKS=1 bash "$tmpdir/robot-main.sh" >"$output_file" 2>&1
)

sleep 0.1

grep -F 'scheduled_jobs=1 selected_issue=5 task_slug=issue-5-scheduled-by-supervisor' "$tmpdir/.grkr/logs/loop.log" >/dev/null
jq -e '.["issue:5:execution"].entity_type == "issue"' "$tmpdir/.grkr/state/active_jobs.json" >/dev/null
jq -e '.["issue:5:execution"].entity_id == "5"' "$tmpdir/.grkr/state/active_jobs.json" >/dev/null
jq -e '.["issue:5:execution"].lock_name == "issue-5"' "$tmpdir/.grkr/state/active_jobs.json" >/dev/null
jq -e '.["issue:5:execution"].task_slug == "issue-5-scheduled-by-supervisor"' "$tmpdir/.grkr/state/active_jobs.json" >/dev/null
[ -f "$tmpdir/.grkr/logs/jobs/issue-5-execution.log" ]
[ -f "$tmpdir/.grkr/locks/issue-5.lock" ]

grep -F 'fetch' "$git_log" >/dev/null
grep -F 'checkout' "$git_log" >/dev/null
grep -F 'reset' "$git_log" >/dev/null

cat > "$tmpdir/worker-pick-issue.sh" <<'EOF'
#!/bin/bash
cat <<'OUT'
SELECTED=1
ISSUE_IDENTIFIER='ENG-123'
JOB_KEY='linear:ENG-123:execution'
TASK_SLUG='eng-123'
ISSUE_TITLE='Linear issue'
OUT
EOF

printf '{}\n' > "$tmpdir/.grkr/state/active_jobs.json"
runner_lines_before=$(wc -l < "$runner_log" | tr -d ' ')

(
  cd "$tmpdir"
  PATH="$tmpdir/bin:$PATH" HOME="$tmpdir/home" GRKR_MAX_TICKS=1 bash "$tmpdir/robot-main.sh" >"$output_file" 2>&1
)

runner_lines_after=$(wc -l < "$runner_log" | tr -d ' ')
[ "$runner_lines_after" = "$runner_lines_before" ]
grep -F 'selected_issue_missing_number=true' "$tmpdir/.grkr/logs/loop.log" >/dev/null
jq -e 'length == 0' "$tmpdir/.grkr/state/active_jobs.json" >/dev/null
