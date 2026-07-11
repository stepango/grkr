#!/bin/bash
# MVP smoke: grkr --linear-issue <identifier> loads Linear fixture context,
# writes research+plan checkpoints, plans linear-comment-mutation, prepares worktree.
# No GitHub gh issue view. Implement/test/PR stages are out of scope.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/grkr-linear-issue-mvp.XXXXXX")
trap 'rm -rf "$tmpdir"' EXIT

cp bin/grkr "$tmpdir/grkr.sh"
cp bin/grkr-issue-workflow.sh "$tmpdir/grkr-issue-workflow.sh"
cp bin/grkr-project-status.sh "$tmpdir/grkr-project-status.sh"
cp bin/grkr-task-slug.sh "$tmpdir/grkr-task-slug.sh"
cp bin/grkr-templates.sh "$tmpdir/grkr-templates.sh"
cp bin/doctor.sh "$tmpdir/doctor.sh"
chmod +x "$tmpdir/grkr.sh" "$tmpdir/doctor.sh"
bash "$(dirname "$0")/test-copy-grkr-lib.sh" "$tmpdir"

real_git=$(command -v git)
mkdir -p "$tmpdir/bin" "$tmpdir/.grkr" "$tmpdir/home"
command_log="$tmpdir/commands.log"
gh_log="$tmpdir/gh.log"
: >"$command_log"
: >"$gh_log"

cat > "$tmpdir/.grkr/config.sh" <<'EOF'
REPO="stepango/grkr"
PROJECT_OWNER="stepango"
PROJECT_NUMBER="1"
STATUS_FIELD_NAME="Status"
TODO_VALUE="Todo"
IN_PROGRESS_VALUE="In Progress"
DONE_VALUE="Done"
BACKLOG_VALUE="Backlog"
PRIORITY_FIELD_NAME="Priority"
TEST_COMMAND="true"
BUILD_COMMAND=""
MAIN_BRANCH="main"
EOF

cat > "$tmpdir/bin/gh" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$gh_log"
printf 'gh %s\n' "\$*" >> "$command_log"
case "\${1-} \${2-}" in
  'auth status') exit 0 ;;
  'issue view')
    echo "UNEXPECTED gh issue view during linear-issue MVP" >> "$gh_log"
    exit 99
    ;;
  *) exit 0 ;;
esac
EOF

cat > "$tmpdir/bin/codex" <<'EOF'
#!/bin/bash
case "${1-}" in
  --help) exit 0 ;;
esac
exit 0
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
printf 'git %s\n' "\$*" >> "$command_log"
case "\$1 \$2" in
  'rev-parse --show-toplevel') printf '%s\n' "$tmpdir" ;;
  'remote get-url') printf 'git@github.com:stepango/grkr.git\n' ;;
  'status --porcelain') exit 0 ;;
  'show-ref --verify') exit 1 ;;
  'ls-remote --heads') exit 1 ;;
  'worktree add')
    # forms: worktree add DIR BRANCH | worktree add -b BRANCH DIR BASE
    dir=""
    if [ "\${3-}" = "-b" ]; then
      dir="\${5-}"
    else
      dir="\${3-}"
    fi
    mkdir -p "\$dir"
    # mark ready for issue_worktree_ready(.git)
    printf 'gitdir: %s/.git\n' "$tmpdir" > "\$dir/.git"
    exit 0
    ;;
  *) exec "$real_git" "\$@" ;;
esac
EOF

chmod +x "$tmpdir/bin/gh" "$tmpdir/bin/codex" "$tmpdir/bin/git" "$tmpdir/bin/timeout" "$tmpdir/bin/flock"

# help recognizes --linear-issue
help_out=$("$tmpdir/grkr.sh" --help 2>&1 || true)
printf '%s\n' "$help_out" | grep -F -- '--linear-issue' >/dev/null

output_file="$tmpdir/output.log"
(
  cd "$tmpdir"
  PATH="$tmpdir/bin:$PATH" \
    HOME="$tmpdir/home" \
    GRKR_GLEAM_PROJECT_ROOT="$repo_root" \
    LINEAR_FIXTURE_PATH="$repo_root/test/fixtures/linear-assigned-issues.json" \
    bash "$tmpdir/grkr.sh" --linear-issue ENG-123 >"$output_file" 2>&1
)

# logs also tee to ~/.grkr/logs; primary assertions on files + output
grep -F 'Linear MVP complete for ENG-123' "$output_file" >/dev/null || {
  echo "MVP completion marker missing" >&2
  cat "$output_file" >&2
  exit 1
}
grep -F 'MVP_STAGE=plan' "$output_file" >/dev/null
grep -F 'Implement Linear integration' "$output_file" >/dev/null

task_dir="$tmpdir/.grkr/tasks/eng-123"
[ -f "$task_dir/research.md" ]
[ -f "$task_dir/plan.md" ]
[ -f "$task_dir/progress.json" ]
[ -f "$task_dir/issue-context.json" ]
[ -f "$task_dir/meta.env" ]
[ -f "$task_dir/research.linear-mutation.txt" ]
[ -f "$task_dir/plan.linear-mutation.txt" ]

grep -F 'PROVIDER=linear' "$task_dir/meta.env" >/dev/null
grep -F 'ISSUE_IDENTIFIER=ENG-123' "$task_dir/meta.env" >/dev/null || grep -F "ISSUE_IDENTIFIER=ENG-123" "$task_dir/meta.env" >/dev/null

jq -e '.provider == "linear" and .issue_identifier == "ENG-123"' "$task_dir/progress.json" >/dev/null
jq -e '.stages.research.status == "done" and .stages.plan.status == "done"' "$task_dir/progress.json" >/dev/null
jq -e '.identifier == "ENG-123" and .provider == "linear"' "$task_dir/issue-context.json" >/dev/null

grep -F 'commentCreate' "$task_dir/research.linear-mutation.txt" >/dev/null
grep -F 'commentCreate' "$task_dir/plan.linear-mutation.txt" >/dev/null
grep -F 'grkr:checkpoint stage=research' "$task_dir/research.md" >/dev/null
grep -F 'grkr:checkpoint stage=plan' "$task_dir/plan.md" >/dev/null

[ -d "$tmpdir/.grkr/worktrees/eng-123" ]

# Must not call GitHub issue view
if grep -F 'issue view' "$gh_log" >/dev/null 2>&1; then
  echo "Unexpected gh issue view during linear MVP:" >&2
  cat "$gh_log" >&2
  exit 1
fi

# empty identifier rejected
if PATH="$tmpdir/bin:$PATH" HOME="$tmpdir/home" GRKR_GLEAM_PROJECT_ROOT="$repo_root" \
  bash "$tmpdir/grkr.sh" --linear-issue '' >"$tmpdir/empty.log" 2>&1; then
  echo "empty identifier unexpectedly succeeded" >&2
  exit 1
fi

printf 'grkr linear-issue MVP test passed\n'
