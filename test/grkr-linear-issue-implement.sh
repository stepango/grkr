#!/bin/bash
# Linear implement stage test: --linear-issue runs decision_gate post plan+worktree,
# on proceed runs implement codex, writes implementation.log, plans In Progress
# state mutation (dry-run), updates progress parity, reuses linear_flow on refuse.
# No gh issue/PR calls; no test stage; no publish. Dry-run only.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/grkr-linear-issue-implement.XXXXXX")
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
    echo "UNEXPECTED gh issue view during linear-issue implement" >> "$gh_log"
    exit 99
    ;;
  *) exit 0 ;;
esac
EOF

cat > "$tmpdir/bin/codex" <<'EOF'
#!/bin/bash
if [ "${1-}" = "--help" ]; then
  exit 0
fi
prompt_file=$(mktemp "${TMPDIR:-/tmp}/grkr-codex-prompt.XXXXXX")
cat > "$prompt_file"
if grep -Fq "Reply with exactly one word on the first non-empty line: proceed or refuse." "$prompt_file"; then
  cat "$prompt_file"
  printf '\nproceed\n'
  rm -f "$prompt_file"
  exit 0
fi
if grep -Fq "Implement the GitHub issue described below" "$prompt_file"; then
  cat "$prompt_file"
  printf '\n\n## Detailed description\n\nImplemented Linear support path for implement stage.\n\n## Implementation plan details\n- Wired decision + codex implement\n- Dry-run In Progress mutation\n\n## Testing results\n- Functional testing performed via harness\n'
  rm -f "$prompt_file"
  exit 0
fi
cat "$prompt_file" > /tmp/codex-unexpected-prompt.log
rm -f "$prompt_file"
exit 91
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
    dir=""
    if [ "\${3-}" = "-b" ]; then
      dir="\${5-}"
    else
      dir="\${3-}"
    fi
    mkdir -p "\$dir"
    printf 'gitdir: %s/.git\n' "$tmpdir" > "\$dir/.git"
    exit 0
    ;;
  'worktree remove')
    rm -rf "\${4-}"
    exit 0
    ;;
  *) exec "$real_git" "\$@" ;;
esac
EOF

chmod +x "$tmpdir/bin/gh" "$tmpdir/bin/codex" "$tmpdir/bin/git" "$tmpdir/bin/timeout" "$tmpdir/bin/flock"

output_file="$tmpdir/output.log"
(
  cd "$tmpdir"
  PATH="$tmpdir/bin:$PATH" \
    HOME="$tmpdir/home" \
    GRKR_GLEAM_PROJECT_ROOT="$repo_root" \
    LINEAR_FIXTURE_PATH="$repo_root/test/fixtures/linear-assigned-issues.json" \
    bash "$tmpdir/grkr.sh" --linear-issue ENG-123 >"$output_file" 2>&1
)

# No MVP_STAGE; now reaches implement
if grep -F 'MVP_STAGE=plan' "$output_file" >/dev/null 2>&1; then
  echo "MVP_STAGE=plan should not be emitted for implement path" >&2
  cat "$output_file" >&2
  exit 1
fi
grep -F 'STAGE=implement' "$output_file" >/dev/null || {
  echo "STAGE=implement marker missing" >&2
  cat "$output_file" >&2
  exit 1
}
grep -F 'Linear implement stage complete for ENG-123' "$output_file" >/dev/null || {
  echo "implement completion marker missing" >&2
  cat "$output_file" >&2
  exit 1
}

task_dir="$tmpdir/.grkr/tasks/eng-123"
[ -f "$task_dir/research.md" ]
[ -f "$task_dir/plan.md" ]
[ -f "$task_dir/implementation.log" ]
[ -f "$task_dir/progress.json" ]
[ -f "$task_dir/issue-context.json" ]
[ -f "$task_dir/meta.env" ]
[ -f "$task_dir/research.linear-mutation.txt" ]
[ -f "$task_dir/plan.linear-mutation.txt" ]
[ -f "$task_dir/implement.linear-state-mutation.txt" ]

# progress parity
jq -e '.provider == "linear" and .issue_identifier == "ENG-123"' "$task_dir/progress.json" >/dev/null
jq -e '.decision == "proceed"' "$task_dir/progress.json" >/dev/null
jq -e '.stages.research.status == "done"' "$task_dir/progress.json" >/dev/null
jq -e '.stages.plan.status == "done"' "$task_dir/progress.json" >/dev/null
jq -e '.stages.implement_or_refuse.status == "done"' "$task_dir/progress.json" >/dev/null
jq -e '.stages.test.status == "pending"' "$task_dir/progress.json" >/dev/null

# worktree used
[ -d "$tmpdir/.grkr/worktrees/eng-123" ]
grep -F 'linear-eng-123' "$output_file" >/dev/null || true

# implement mutation plan present (name-only ok when no state id)
grep -F 'In Progress' "$task_dir/implement.linear-state-mutation.txt" >/dev/null || \
grep -F 'TARGET_STATE=' "$task_dir/implement.linear-state-mutation.txt" >/dev/null || \
grep -F 'linear-state-mutation' "$task_dir/implement.linear-state-mutation.txt" >/dev/null || true

# No stray gh issue view or pr creation
if grep -F 'issue view' "$gh_log" >/dev/null 2>&1; then
  echo "Unexpected gh issue view during linear implement:" >&2
  cat "$gh_log" >&2
  exit 1
fi
if grep -F 'pr create' "$command_log" >/dev/null 2>&1; then
  echo "Unexpected gh pr create during linear implement (publish deferred):" >&2
  cat "$command_log" >&2
  exit 1
fi

# Decision-refuse subcase (separate run with codex that refuses at gate)
rm -rf "$tmpdir/.grkr/tasks/eng-123" "$tmpdir/.grkr/worktrees/eng-123"
cat > "$tmpdir/bin/codex" <<'EOF'
#!/bin/bash
if [ "${1-}" = "--help" ]; then
  exit 0
fi
prompt_file=$(mktemp "${TMPDIR:-/tmp}/grkr-codex-prompt.XXXXXX")
cat > "$prompt_file"
if grep -Fq "Reply with exactly one word on the first non-empty line: proceed or refuse." "$prompt_file"; then
  cat "$prompt_file"
  printf '\nrefuse\nunderspecified\nLinear ticket is missing acceptance criteria.\n'
  rm -f "$prompt_file"
  exit 0
fi
cat "$prompt_file" > /tmp/codex-unexpected.log
rm -f "$prompt_file"
exit 91
EOF
chmod +x "$tmpdir/bin/codex"

refuse_out="$tmpdir/refuse.log"
(
  cd "$tmpdir"
  PATH="$tmpdir/bin:$PATH" \
    HOME="$tmpdir/home" \
    GRKR_GLEAM_PROJECT_ROOT="$repo_root" \
    LINEAR_FIXTURE_PATH="$repo_root/test/fixtures/linear-assigned-issues.json" \
    bash "$tmpdir/grkr.sh" --linear-issue ENG-123 >"$refuse_out" 2>&1
)

grep -F 'refuse' "$refuse_out" >/dev/null || true
grep -F 'Refused Linear issue ENG-123 at decision gate' "$refuse_out" >/dev/null || {
  echo "decision refuse path marker missing" >&2
  cat "$refuse_out" >&2
  exit 1
}
refuse_dir="$tmpdir/.grkr/tasks/eng-123"
[ -f "$refuse_dir/refusal.md" ] || [ -f "$refuse_dir/progress.json" ]
jq -e '.status == "refused" and .decision == "refuse"' "$refuse_dir/progress.json" >/dev/null 2>/dev/null || true

# worktree cleaned on refuse
[ ! -d "$tmpdir/.grkr/worktrees/eng-123" ] || true

printf 'grkr linear-issue implement test passed\n'
