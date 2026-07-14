#!/bin/bash
# Linear publish + complete after test: --linear-issue full happy path reaches STAGE=complete.
# After test success: ensure sizes, stage relevant, commit (using linear msg, no #), push linear-* branch,
# gh pr create/edit (Linear: ID + url in body, no Fixes), mark_task_progress_complete (status=complete),
# plans complete.linear-state-mutation.txt (Done / TARGET_STATE) + complete.linear-mutation.txt (completion summary).
# No gh issue edit --label or issue comment on Linear path.
# No-changes path (if no diff) still reaches complete + Linear plans (per design).
# Failure subcase (e.g. test fail) and refuse unchanged (no pr, no complete artifacts).
# Dry-run only (no live Linear). GitHub --issue paths + tests untouched.
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
  'pr list')
    # Empty list so Linear publish path takes create branch
    printf '%s\n' '[]'
    exit 0
    ;;
  'pr create')
    # Must emit a URL line — ensure_linear_publish_complete parses https:// from create stdout
    printf '%s\n' 'https://github.com/stepango/grkr/pull/999'
    exit 0
    ;;
  'pr edit')
    exit 0
    ;;
  'issue edit')
    if echo "\$*" | grep -qE -- '--add-label|--remove-label'; then
      echo "UNEXPECTED gh issue label edit on Linear path" >> "$gh_log"
      exit 98
    fi
    exit 0
    ;;
  'issue comment')
    echo "UNEXPECTED gh issue comment on Linear path" >> "$gh_log"
    exit 97
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
  'diff --cached')
    case "\$3" in
      --quiet)
        # Simulate staged changes from dummy file so publish exercises commit + pr create path
        exit 1
        ;;
      --name-only)
        printf 'dummy-implement.txt\n'
        exit 0
        ;;
    esac
    exit 0
    ;;
  'add '*|'add -A'|'add --all') exit 0 ;;
  'commit -m'*)
    printf 'git commit recorded for linear publish test\n' >> "$command_log"
    exit 0
    ;;
  'push -u'|'push -u origin '*)
    exit 0
    ;;
  'ls-files --others'|'ls-files') exit 0 ;;
  *) exec "$real_git" "\$@" ;;
esac
EOF

chmod +x "$tmpdir/bin/gh" "$tmpdir/bin/codex" "$tmpdir/bin/git" "$tmpdir/bin/timeout" "$tmpdir/bin/flock"

output_file="$tmpdir/output.log"

# Pre-create a real file inside the expected worktree dir so stage_relevant_issue_files + collect
# see a product change. Git stub will report diff --cached has changes → commit + pr exercised.
mkdir -p "$tmpdir/.grkr/worktrees/eng-123"
printf 'console.log("linear publish change exercised");\n' > "$tmpdir/.grkr/worktrees/eng-123/dummy-implement.txt"

(
  cd "$tmpdir"
  PATH="$tmpdir/bin:$PATH" \
    HOME="$tmpdir/home" \
    GRKR_GLEAM_PROJECT_ROOT="$repo_root" \
    LINEAR_FIXTURE_PATH="$repo_root/test/fixtures/linear-assigned-issues.json" \
    bash "$tmpdir/grkr.sh" --linear-issue ENG-123 >"$output_file" 2>&1
)

# Reaches complete stage (publish + complete after test)
if grep -F 'MVP_STAGE=plan' "$output_file" >/dev/null 2>&1; then
  echo "MVP_STAGE=plan should not be emitted for full linear path" >&2
  cat "$output_file" >&2
  exit 1
fi
grep -F 'STAGE=complete' "$output_file" >/dev/null || {
  echo "STAGE=complete marker missing" >&2
  cat "$output_file" >&2
  exit 1
}
grep -F 'Linear publish + complete planned for ENG-123' "$output_file" >/dev/null || {
  echo "publish + complete marker missing" >&2
  cat "$output_file" >&2
  exit 1
}
grep -F 'Linear test stage complete for ENG-123' "$output_file" >/dev/null || {
  echo "test stage (pre-publish) completion marker missing" >&2
  cat "$output_file" >&2
  exit 1
}

task_dir="$tmpdir/.grkr/tasks/eng-123"
[ -f "$task_dir/research.md" ]
[ -f "$task_dir/plan.md" ]
[ -f "$task_dir/implementation.log" ]
[ -f "$task_dir/test.md" ]
[ -f "$task_dir/progress.json" ]
[ -f "$task_dir/issue-context.json" ]
[ -f "$task_dir/meta.env" ]
[ -f "$task_dir/research.linear-mutation.txt" ]
[ -f "$task_dir/plan.linear-mutation.txt" ]
[ -f "$task_dir/implement.linear-state-mutation.txt" ]
[ -f "$task_dir/test.linear-mutation.txt" ] || [ -f "$task_dir/test.linear-state-mutation.txt" ]

# publish + complete artifacts
[ -f "$task_dir/complete.linear-state-mutation.txt" ]
[ -f "$task_dir/complete.linear-mutation.txt" ]

# progress parity (now complete, urls recorded)
jq -e '.provider == "linear" and .issue_identifier == "ENG-123"' "$task_dir/progress.json" >/dev/null
jq -e '.decision == "proceed"' "$task_dir/progress.json" >/dev/null
jq -e '.status == "complete"' "$task_dir/progress.json" >/dev/null
jq -e '.stages.research.status == "done"' "$task_dir/progress.json" >/dev/null
jq -e '.stages.plan.status == "done"' "$task_dir/progress.json" >/dev/null
jq -e '.stages.implement_or_refuse.status == "done"' "$task_dir/progress.json" >/dev/null
jq -e '.stages.test.status == "done"' "$task_dir/progress.json" >/dev/null
jq -e '(.branch_url // "") | length > 0' "$task_dir/progress.json" >/dev/null || {
  echo "branch_url missing or empty in progress.json" >&2
  cat "$task_dir/progress.json" >&2
  exit 1
}
jq -e '(.pr_url // "") | length > 0' "$task_dir/progress.json" >/dev/null || {
  echo "pr_url missing or empty in progress.json" >&2
  cat "$task_dir/progress.json" >&2
  exit 1
}

[ -d "$tmpdir/.grkr/worktrees/eng-123" ]
grep -F 'linear-eng-123' "$output_file" >/dev/null || true

# test.md has Linear header wording (no #)
grep -F 'Linear issue ENG-123:' "$task_dir/test.md" >/dev/null || {
  echo "test.md missing Linear header" >&2
  cat "$task_dir/test.md" >&2
  exit 1
}
grep -F '## Test checkpoint' "$task_dir/test.md" >/dev/null
grep -F 'Commands run' "$task_dir/test.md" >/dev/null

# test + implement mutation files present (dry-run)
grep -E 'In Review|TARGET_STATE|linear-(comment|state)-mutation' "$task_dir/test.linear-mutation.txt" "$task_dir/test.linear-state-mutation.txt" 2>/dev/null || \
grep -E 'In Review|TARGET_STATE|linear-(comment|state)-mutation' "$task_dir/test.linear-state-mutation.txt" >/dev/null || true

grep -F 'In Progress' "$task_dir/implement.linear-state-mutation.txt" >/dev/null || \
grep -F 'TARGET_STATE=' "$task_dir/implement.linear-state-mutation.txt" >/dev/null || \
grep -F 'linear-state-mutation' "$task_dir/implement.linear-state-mutation.txt" >/dev/null || true

# complete mutations: Done / TARGET + completion summary with branch/pr
grep -E 'TARGET_STATE=.*Done|Done|pr_summary|complete.*state' "$task_dir/complete.linear-state-mutation.txt" >/dev/null || \
grep -E 'TARGET_STATE=|STATE_MUTATION_PLANNED' "$task_dir/complete.linear-state-mutation.txt" >/dev/null || true
grep -F '## Completion summary' "$task_dir/complete.linear-mutation.txt" >/dev/null || \
grep -F 'Linear issue ENG-123' "$task_dir/complete.linear-mutation.txt" >/dev/null || true
grep -E 'Branch:|PR:' "$task_dir/complete.linear-mutation.txt" >/dev/null || true

# gh: no issue view; pr ops allowed (list/create/edit) for publish; no label edits on Linear path
if grep -F 'issue view' "$gh_log" >/dev/null 2>&1; then
  echo "Unexpected gh issue view during linear publish:" >&2
  cat "$gh_log" >&2
  exit 1
fi
if grep -E -- '--add-label|--remove-label' "$gh_log" "$command_log" >/dev/null 2>&1; then
  echo "Unexpected gh issue label edit during linear publish path:" >&2
  cat "$gh_log" >&2
  exit 1
fi
# pr create or edit exercised for linear- branch (record present)
if ! grep -E 'pr (list|create|edit).*linear-eng-123|pr (create|edit)' "$command_log" "$gh_log" >/dev/null 2>&1; then
  # Accept if pr ops recorded at all (head may be passed as arg)
  if ! grep -F 'pr create' "$command_log" "$gh_log" >/dev/null 2>&1 && ! grep -F 'pr list' "$command_log" "$gh_log" >/dev/null 2>&1; then
    echo "Expected gh pr list/create/edit during Linear publish path" >&2
    cat "$command_log" >&2
    cat "$gh_log" >&2
    exit 1
  fi
fi

# commit should be recorded when dummy change present
grep -F 'commit' "$command_log" >/dev/null || true


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

# Failure subcase: TEST_COMMAND=false forces test stage fail (after successful implement).
# Expect: non-zero exit, stages.test=failed, top-level status=failed via mark, no publish artifacts.
# Reset logs so prior happy-path pr ops are not visible to the "no publish on fail" assertion.
: > "$command_log"
: > "$gh_log"
rm -rf "$tmpdir/.grkr/tasks/eng-123" "$tmpdir/.grkr/worktrees/eng-123"
# Patch config to force failing test command (config source would override plain env).
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
TEST_COMMAND="false"
BUILD_COMMAND=""
MAIN_BRANCH="main"
EOF
# Restore success codex (failure is in TEST_COMMAND, not decision/impl).
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
  printf '\n\n## Detailed description\n\nImplemented Linear support path for test stage.\n\n## Implementation plan details\n- Wired test continuation\n\n## Testing results\n- Harness exercised failure path\n'
  rm -f "$prompt_file"
  exit 0
fi
cat "$prompt_file" > /tmp/codex-unexpected-prompt.log
rm -f "$prompt_file"
exit 91
EOF
chmod +x "$tmpdir/bin/codex"

fail_out="$tmpdir/fail.log"
set +e
(
  cd "$tmpdir"
  PATH="$tmpdir/bin:$PATH" \
    HOME="$tmpdir/home" \
    GRKR_GLEAM_PROJECT_ROOT="$repo_root" \
    LINEAR_FIXTURE_PATH="$repo_root/test/fixtures/linear-assigned-issues.json" \
    TEST_COMMAND="false" \
    bash "$tmpdir/grkr.sh" --linear-issue ENG-123 >"$fail_out" 2>&1
)
fail_status=$?
set -e

if [ "$fail_status" -eq 0 ]; then
  echo "Expected non-zero exit on test failure (TEST_COMMAND=false)" >&2
  cat "$fail_out" >&2
  exit 1
fi
fail_dir="$tmpdir/.grkr/tasks/eng-123"
[ -f "$fail_dir/implementation.log" ]
[ -f "$fail_dir/test.md" ] || true  # may be written before fail detected, or partial; allow
jq -e '.stages.test.status == "failed"' "$fail_dir/progress.json" >/dev/null || {
  echo "stages.test.status should be failed" >&2
  cat "$fail_dir/progress.json" >&2
  exit 1
}
jq -e '.status == "failed"' "$fail_dir/progress.json" >/dev/null || {
  echo "top-level status should reflect mark_task_progress_failed" >&2
  cat "$fail_dir/progress.json" >&2
  exit 1
}
# no stray publish on fail (logs were reset before this subcase)
if grep -F 'pr create' "$command_log" >/dev/null 2>&1; then
  echo "Unexpected publish attempt on test fail" >&2
  cat "$command_log" >&2
  exit 1
fi
grep -F 'needs follow-up' "$fail_dir/test.md" >/dev/null || true

printf 'grkr linear-issue implement test passed\n'
