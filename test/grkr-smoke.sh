#!/bin/bash
set -euo pipefail

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/grkr-smoke.XXXXXX")
trap 'rm -rf "$tmpdir"' EXIT

cp bin/grkr "$tmpdir/grkr.sh"
cp bin/grkr-issue-workflow.sh "$tmpdir/grkr-issue-workflow.sh"
cp bin/grkr-project-status.sh "$tmpdir/grkr-project-status.sh"
cp bin/grkr-templates.sh "$tmpdir/grkr-templates.sh"
cp bin/doctor.sh "$tmpdir/doctor.sh"
chmod +x "$tmpdir/grkr.sh"
chmod +x "$tmpdir/doctor.sh"

real_git=$(command -v git)
mkdir -p "$tmpdir/bin"
gh_log="$tmpdir/gh.log"
issue_comment_body="$tmpdir/issue-comment-body.log"
pr_body="$tmpdir/pr-body.log"
codex_prompt="$tmpdir/codex-prompt.log"
command_log="$tmpdir/commands.log"
comments_json="$tmpdir/comments.json"
next_comment_id="$tmpdir/next-comment-id"
mkdir -p "$tmpdir/.grkr"
printf '[]\n' > "$comments_json"
printf '1000\n' > "$next_comment_id"

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
TEST_COMMAND="mkdir -p .grkr && pwd > .grkr/test-pwd.txt && printf 'test command passed\n'"
BUILD_COMMAND="mkdir -p .grkr && pwd > .grkr/build-pwd.txt && printf 'build command passed\n'"
EOF

cat > "$tmpdir/bin/gh" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$gh_log"
printf 'gh %s\n' "\$*" >> "$command_log"
case "\${1-} \${2-}" in
  'auth status') exit 0 ;;
  'issue view')
    comments=\$(cat "$comments_json")
    jq -n --argjson comments "\$comments" '
      {
        title: "Test issue",
        body: "Body",
        url: "https://example.com",
        number: 1,
        projectItems: [{id: "ITEM_1", number: 1, status: {name: "Todo"}}],
        comments: \$comments
      }
    '
    ;;
  'issue comment')
    body=""
    shift 2
    while [ "\$#" -gt 0 ]; do
      case "\$1" in
        --body-file)
          body=\$(cat "\$2")
          shift 2
          ;;
        --body)
          body=\$2
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    printf '%s\n' "\$body" >> "$issue_comment_body"
    comment_id=\$(cat "$next_comment_id")
    printf '%s\n' "\$((comment_id + 1))" > "$next_comment_id"
    comments_tmp=\$(mktemp "${TMPDIR:-/tmp}/grkr-comments.XXXXXX")
    jq --arg body "\$body" --argjson id "\$comment_id" '. + [{id: \$id, body: \$body}]' "$comments_json" > "\$comments_tmp"
    mv "\$comments_tmp" "$comments_json"
    exit 0
    ;;
  'pr list') printf '[]\n' ;;
  'pr create')
    shift 2
    while [ "\$#" -gt 0 ]; do
      case "\$1" in
        --body-file)
          cat "\$2" >> "$pr_body"
          shift 2
          ;;
        --body)
          printf '%s\n' "\$2" >> "$pr_body"
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    echo 'https://example.com/pr/1'
    ;;
  'project view') printf '{"id":"PROJECT_1"}\n' ;;
  'project field-list') printf '[{"id":"FIELD_STATUS","name":"Status","options":[{"id":"OPTION_TODO","name":"Todo"},{"id":"OPTION_IN_PROGRESS","name":"In progress"},{"id":"OPTION_DONE","name":"Done"}]}]\n' ;;
  'project item-edit') exit 0 ;;
  'issue edit') exit 0 ;;
  *) exit 0 ;;
esac
EOF

cat > "$tmpdir/bin/codex" <<EOF
#!/bin/bash
prompt_file=\$(mktemp "${TMPDIR:-/tmp}/grkr-codex-prompt.XXXXXX")
cat > "\$prompt_file"
if grep -Fq "Reply with exactly one word on the first non-empty line: proceed or refuse." "\$prompt_file"; then
  printf 'proceed\n'
else
  cat "\$prompt_file" > "$codex_prompt"
  cat <<'OUT'
## Detailed description of the task

Implemented the requested issue workflow updates.

Issue: [#1](https://example.com)

## Implementation plan details

- Made focused script and test updates.

## Testing results

- Functional testing performed
OUT
fi
rm -f "\$prompt_file"
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
  'show-ref --verify')
    if [ "\${4-}" = "refs/heads/issue-1" ]; then
      exit 1
    fi
    if [ "\${4-}" = "refs/remotes/origin/main" ]; then
      exit 1
    fi
    exit 1
    ;;
  'ls-remote --heads') exit 1 ;;
  'worktree add')
    mkdir -p "\${5-}"
    exit 0
    ;;
  'reset ') exit 0 ;;
  'diff --name-only')
    printf 'README.md\n'
    ;;
  'diff --cached')
    case "\$3" in
      --name-only)
        if [ "\${4-}" = "--diff-filter=ACMR" ]; then
          exit 0
        fi
        exit 0
        ;;
      --quiet)
        exit 1
        ;;
    esac
    ;;
  'ls-files --others') exit 0 ;;
  'add -A') exit 0 ;;
  'diff --cached --quiet') exit 1 ;;
  'diff --cached') exit 1 ;;
  'commit -m') exit 0 ;;
  'push -u') exit 0 ;;
  *) exec "$real_git" "\$@" ;;
esac
EOF

chmod +x "$tmpdir/bin/gh" "$tmpdir/bin/codex" "$tmpdir/bin/git" "$tmpdir/bin/timeout" "$tmpdir/bin/flock"

output_file="$tmpdir/output.log"
(
  cd "$tmpdir"
  PATH="$tmpdir/bin:$PATH" HOME="$tmpdir/home" bash "$tmpdir/grkr.sh" --issue 1 >"$output_file" 2>&1
)

grep -F "✅ Startup validation passed." "$output_file" >/dev/null
grep -F "🚀 Running codex to decide whether to implement the issue..." "$output_file" >/dev/null
grep -F "🚀 Running codex to implement the issue..." "$output_file" >/dev/null
grep -F "✅ codex has finished implement the issue." "$output_file" >/dev/null
grep -F "✅ PR created: https://example.com/pr/1" "$output_file" >/dev/null
grep -F "🌿 Created issue worktree for branch: issue-1" "$output_file" >/dev/null
grep -F "🚧 Moved issue #1 to In Progress." "$output_file" >/dev/null
grep -F "🧪 Running verification command for issue #1: mkdir -p .grkr && pwd > .grkr/build-pwd.txt && printf 'build command passed\n'" "$output_file" >/dev/null
grep -F "🧪 Running verification command for issue #1: mkdir -p .grkr && pwd > .grkr/test-pwd.txt && printf 'test command passed\n'" "$output_file" >/dev/null
grep -F "📝 Posting research checkpoint for issue #1..." "$output_file" >/dev/null
grep -F "📝 Posting plan checkpoint for issue #1..." "$output_file" >/dev/null
grep -F "📝 Posting test checkpoint for issue #1..." "$output_file" >/dev/null
grep -F "✅ Moved issue #1 to Done." "$output_file" >/dev/null
grep -F "## Detailed description of the task" "$pr_body" >/dev/null
grep -F "## Implementation plan details" "$pr_body" >/dev/null
grep -F "## Testing results" "$pr_body" >/dev/null
grep -F "Functional testing performed" "$pr_body" >/dev/null
grep -F "Fixes #1" "$pr_body" >/dev/null
if [ "$(grep -c '^Fixes #1$' "$pr_body")" -ne 1 ]; then
  echo "expected a single Fixes footer in PR body"
  exit 1
fi
if grep -Fq "Issue: [#1](https://example.com)" "$pr_body"; then
  echo "unexpected duplicate issue mention in PR body"
  exit 1
fi
task_dir="$tmpdir/.grkr/tasks/issue-1-test-issue"
worktree_dir="$tmpdir/.grkr/worktrees/issue-1-test-issue"
worktree_realpath=$(cd "$worktree_dir" && pwd)
[ -d "$task_dir" ]
grep -F "<!-- grkr:checkpoint stage=research task=issue-1-test-issue version=1 -->" "$task_dir/research.md" >/dev/null
grep -F "### Problem statement" "$task_dir/research.md" >/dev/null
grep -F "### Current system behavior" "$task_dir/research.md" >/dev/null
grep -F "### Inferred acceptance criteria" "$task_dir/research.md" >/dev/null
grep -F "<!-- grkr:checkpoint stage=plan task=issue-1-test-issue version=1 -->" "$task_dir/plan.md" >/dev/null
grep -F "### Implementation plan" "$task_dir/plan.md" >/dev/null
grep -F "## Refusal assessment" "$task_dir/plan.md" >/dev/null
grep -F "<!-- grkr:checkpoint stage=test task=issue-1-test-issue version=1 -->" "$task_dir/test.md" >/dev/null
grep -F "### Commands run" "$task_dir/test.md" >/dev/null
grep -F "build command passed" "$task_dir/test.md" >/dev/null
grep -F "test command passed" "$task_dir/test.md" >/dev/null
grep -F "Overall result: PASS" "$task_dir/test.md" >/dev/null
grep -F "### Recommendation" "$task_dir/test.md" >/dev/null
grep -F "ready" "$task_dir/test.md" >/dev/null
[ -f "$task_dir/implementation.log" ]
[ -f "$worktree_dir/.grkr/build-pwd.txt" ]
[ -f "$worktree_dir/.grkr/test-pwd.txt" ]
grep -Fx "$worktree_realpath" "$worktree_dir/.grkr/build-pwd.txt" >/dev/null
grep -Fx "$worktree_realpath" "$worktree_dir/.grkr/test-pwd.txt" >/dev/null
jq -e '.task_slug == "issue-1-test-issue"' "$task_dir/progress.json" >/dev/null
jq -e '.status == "complete"' "$task_dir/progress.json" >/dev/null
jq -e '.stages.research.status == "done" and .stages.research.comment_id == 1000' "$task_dir/progress.json" >/dev/null
jq -e '.stages.plan.status == "done" and .stages.plan.comment_id == 1001' "$task_dir/progress.json" >/dev/null
jq -e '.stages.implement_or_refuse.status == "done"' "$task_dir/progress.json" >/dev/null
jq -e '.stages.test.status == "done" and .stages.test.comment_id == 1002' "$task_dir/progress.json" >/dev/null
jq -e '.decision == "proceed"' "$task_dir/progress.json" >/dev/null
jq -e '.branch_url == "https://github.com/stepango/grkr/tree/issue-1"' "$task_dir/progress.json" >/dev/null
jq -e '.pr_url == "https://example.com/pr/1"' "$task_dir/progress.json" >/dev/null
grep -F "<details>" "$issue_comment_body" >/dev/null
grep -F "<summary>Execution log</summary>" "$issue_comment_body" >/dev/null
grep -F '```text' "$issue_comment_body" >/dev/null
grep -F "<!-- grkr:checkpoint stage=research task=issue-1-test-issue version=1 -->" "$issue_comment_body" >/dev/null
grep -F "## Research checkpoint" "$issue_comment_body" >/dev/null
grep -F "<!-- grkr:checkpoint stage=plan task=issue-1-test-issue version=1 -->" "$issue_comment_body" >/dev/null
grep -F "## Plan checkpoint" "$issue_comment_body" >/dev/null
grep -F "<!-- grkr:checkpoint stage=test task=issue-1-test-issue version=1 -->" "$issue_comment_body" >/dev/null
grep -F "## Test checkpoint" "$issue_comment_body" >/dev/null
grep -F "## Completion summary" "$issue_comment_body" >/dev/null
grep -F "Branch: https://github.com/stepango/grkr/tree/issue-1" "$issue_comment_body" >/dev/null
grep -F "PR: https://example.com/pr/1" "$issue_comment_body" >/dev/null
grep -F "🚀 Running codex to implement the issue..." "$issue_comment_body" >/dev/null
grep -F "✅ PR created: https://example.com/pr/1" "$issue_comment_body" >/dev/null
grep -F "</details>" "$issue_comment_body" >/dev/null
grep -F "Detailed description of the task" "$codex_prompt" >/dev/null
grep -F "Implementation plan details" "$codex_prompt" >/dev/null
grep -F "Testing results" "$codex_prompt" >/dev/null
grep -F "Functional testing performed" "$codex_prompt" >/dev/null
grep -F "Apply code changes in the issue worktree only." "$codex_prompt" >/dev/null
grep -F "Stage only the files relevant to the issue." "$codex_prompt" >/dev/null
grep -F "Issue worktree: $tmpdir/.grkr/worktrees/issue-1-test-issue" "$codex_prompt" >/dev/null
grep -F "No file may exceed 1000 lines." "$codex_prompt" >/dev/null
grep -F "Keep every changed file within the repository's per-file line limit." "$codex_prompt" >/dev/null
grep -F "$tmpdir/.grkr/tasks/issue-1-test-issue/research.md" "$codex_prompt" >/dev/null
grep -F "$tmpdir/.grkr/tasks/issue-1-test-issue/plan.md" "$codex_prompt" >/dev/null

project_edit_line=$(grep -n 'gh project item-edit --id ITEM_1 --field-id FIELD_STATUS --project-id PROJECT_1 --single-select-option-id OPTION_IN_PROGRESS' "$command_log" | head -n1 | cut -d: -f1)
worktree_create_line=$(grep -n 'git worktree add -b issue-1' "$command_log" | head -n1 | cut -d: -f1)
done_edit_line=$(grep -n 'gh project item-edit --id ITEM_1 --field-id FIELD_STATUS --project-id PROJECT_1 --single-select-option-id OPTION_DONE' "$command_log" | head -n1 | cut -d: -f1)
[ -n "$project_edit_line" ]
[ -n "$worktree_create_line" ]
[ -n "$done_edit_line" ]
[ "$worktree_create_line" -lt "$project_edit_line" ]
[ "$project_edit_line" -lt "$done_edit_line" ]
