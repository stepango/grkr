#!/bin/bash
set -euo pipefail

repo_root=$(pwd)
tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/grkr-implementation-refusal.XXXXXX")
trap 'rm -rf "$tmpdir"' EXIT

cp bin/grkr "$tmpdir/grkr.sh"
cp bin/grkr-issue-workflow.sh "$tmpdir/grkr-issue-workflow.sh"
cp bin/grkr-project-status.sh "$tmpdir/grkr-project-status.sh"
cp bin/grkr-templates.sh "$tmpdir/grkr-templates.sh"
cp bin/grkr-task-slug.sh "$tmpdir/grkr-task-slug.sh"
cp bin/doctor.sh "$tmpdir/doctor.sh"
chmod +x "$tmpdir/grkr.sh" "$tmpdir/doctor.sh"
bash "$(dirname "$0")/test-copy-grkr-lib.sh" "$tmpdir"

real_git=$(command -v git)
mkdir -p "$tmpdir/bin"
issue_comment_body="$tmpdir/issue-comment-body.log"
command_log="$tmpdir/commands.log"
comments_json="$tmpdir/comments.json"
next_comment_id="$tmpdir/next-comment-id"
printf '[]\n' > "$comments_json"
printf '3000\n' > "$next_comment_id"
mkdir -p "$tmpdir/.grkr"

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
EOF

cat > "$tmpdir/bin/gh" <<EOF
#!/bin/bash
printf 'gh %s\n' "\$*" >> "$command_log"
case "\${1-} \${2-}" in
  'auth status') exit 0 ;;
  'issue view')
    comments=\$(cat "$comments_json")
    jq -n --argjson comments "\$comments" '
      {
        title: "Missing dependency blocker",
        body: "This issue requires an API that does not exist yet.",
        url: "https://example.com/issues/2",
        number: 2,
        projectItems: [{id: "ITEM_2", number: 2, status: {name: "Todo"}}],
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
  'project view') printf '{"id":"PROJECT_1"}\n' ;;
  'project field-list') printf '[{"id":"FIELD_STATUS","name":"Status","options":[{"id":"OPTION_TODO","name":"Todo"},{"id":"OPTION_IN_PROGRESS","name":"In progress"},{"id":"OPTION_BACKLOG","name":"Backlog"},{"id":"OPTION_DONE","name":"Done"}]}]\n' ;;
  'project item-edit') exit 0 ;;
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
  printf '\n\n## Analysis\n\nThe issue requires implementing feature X, but during implementation I discovered that API Y does not exist yet. This is a missing dependency blocker.\n\ngrkr-refuse-implementation\nmissing_dependency\nThe required upstream API does not exist in the codebase yet.\n'
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
    mkdir -p "\${5-}"
    : > "\${5-}/.git"
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
  PATH="$tmpdir/bin:$PATH" HOME="$tmpdir/home" GRKR_GLEAM_PROJECT_ROOT="$repo_root" bash "$tmpdir/grkr.sh" --issue 2 >"$output_file" 2>&1
)

grep -F "✅ Startup validation passed." "$output_file" >/dev/null
grep -F "🚀 Running codex to decide whether to implement the issue..." "$output_file" >/dev/null
grep -F "🚀 Running codex to implement the issue..." "$output_file" >/dev/null
grep -F "⚠️ Implementation discovered blockers that require refusal." "$output_file" >/dev/null
grep -F "🔄 Converting implementation attempt to refusal for issue #2." "$output_file" >/dev/null
grep -F "📝 Posting refusal checkpoint for issue #2..." "$output_file" >/dev/null
grep -F "⏸️ Refused implementation for issue #2 (converted during implementation)." "$output_file" >/dev/null

if grep -Fq "PR created" "$output_file"; then
  echo "PR should not be created when implementation converts to refusal" >&2
  exit 1
fi

if grep -Fq "Test checkpoint" "$output_file"; then
  echo "Test checkpoint should not run when implementation converts to refusal" >&2
  exit 1
fi

task_dir="$tmpdir/.grkr/tasks/issue-2-missing-dependency-blocker"
worktree_dir="$tmpdir/.grkr/worktrees/issue-2-missing-dependency-blocker"
[ -d "$task_dir" ]
[ ! -e "$worktree_dir" ]
[ -f "$task_dir/refusal.md" ]
[ -f "$task_dir/codex/implementation-before-refusal.log" ]

grep -F "<!-- grkr:checkpoint stage=refusal task=issue-2-missing-dependency-blocker version=1 -->" "$task_dir/refusal.md" >/dev/null
grep -F "## Implementation refused" "$task_dir/refusal.md" >/dev/null
grep -F 'The issue was not implemented because implementation discovered a blocker after the decision gate returned `proceed`.' "$task_dir/refusal.md" >/dev/null
grep -F "missing_dependency" "$task_dir/refusal.md" >/dev/null

jq -e '.status == "refused"' "$task_dir/progress.json" >/dev/null
jq -e '.decision == "refuse"' "$task_dir/progress.json" >/dev/null
jq -e '.stages.implement_or_refuse.status == "done"' "$task_dir/progress.json" >/dev/null
jq -e '.stages.implement_or_refuse.reason_class == "missing_dependency"' "$task_dir/progress.json" >/dev/null
jq -e '.stages.test.status == "skipped"' "$task_dir/progress.json" >/dev/null

grep -F "<!-- grkr:checkpoint stage=refusal task=issue-2-missing-dependency-blocker version=1 -->" "$issue_comment_body" >/dev/null
grep -F 'git worktree remove --force' "$command_log" >/dev/null

if grep -Fq 'gh pr create' "$command_log"; then
  echo "PR creation should not happen when implementation converts to refusal" >&2
  exit 1
fi

prose_log="$tmpdir/prose.log"
cat > "$prose_log" <<'EOF'
## Implementation plan details
Refuse broad rewrites and keep the change focused.
## Testing results
- Functional testing performed
EOF

false_positive_output=$(bash -c '. "$1"; detect_implementation_refusal "$2"' bash "$tmpdir/grkr-issue-workflow.sh" "$prose_log")
if [ -n "$false_positive_output" ]; then
  echo "ordinary implementation prose should not trigger refusal conversion" >&2
  exit 1
fi

echo "✅ Implementation-to-refusal conversion test passed"
