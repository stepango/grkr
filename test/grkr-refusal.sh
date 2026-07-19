#!/bin/bash
set -euo pipefail

repo_root=$(pwd)
tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/grkr-refusal.XXXXXX")
# trap 'rm -rf "$tmpdir"' EXIT  # disabled for debug run of e2e task

cp bin/grkr "$tmpdir/grkr.sh"
cp bin/grkr-issue-workflow.sh "$tmpdir/grkr-issue-workflow.sh"
cp bin/grkr-project-status.sh "$tmpdir/grkr-project-status.sh"
cp bin/grkr-task-slug.sh "$tmpdir/grkr-task-slug.sh"
cp bin/grkr-templates.sh "$tmpdir/grkr-templates.sh"
cp bin/worker-refuse-issue.sh "$tmpdir/worker-refuse-issue.sh"
cp bin/doctor.sh "$tmpdir/doctor.sh"
mkdir -p "$tmpdir/lib"
cp bin/lib/*.sh "$tmpdir/lib/"
chmod +x "$tmpdir/grkr.sh" "$tmpdir/worker-refuse-issue.sh" "$tmpdir/doctor.sh" "$tmpdir/lib/"*.sh

real_git=$(command -v git)
mkdir -p "$tmpdir/bin"
issue_comment_body="$tmpdir/issue-comment-body.log"
command_log="$tmpdir/commands.log"
comments_json="$tmpdir/comments.json"
next_comment_id="$tmpdir/next-comment-id"
unexpected_prompt="$tmpdir/unexpected-implementation-prompt.log"
printf '[]\n' > "$comments_json"
printf '2000\n' > "$next_comment_id"
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
        title: "Clarify refusal handling",
        body: "The implementation details are intentionally missing.",
        url: "https://example.com/issues/1",
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
  'project view') printf '{"id":"PROJECT_1"}\n' ;;
  'project field-list') printf '[{"id":"FIELD_STATUS","name":"Status","options":[{"id":"OPTION_TODO","name":"Todo"},{"id":"OPTION_IN_PROGRESS","name":"In progress"},{"id":"OPTION_BACKLOG","name":"Backlog"},{"id":"OPTION_DONE","name":"Done"}]}]\n' ;;
  'project item-edit') exit 0 ;;
  *) exit 0 ;;
esac
EOF

cat > "$tmpdir/bin/codex" <<EOF
#!/bin/bash
if [ "\${1-}" = "--help" ]; then
  exit 0
fi
prompt_file=\$(mktemp "${TMPDIR:-/tmp}/grkr-codex-prompt.XXXXXX")
cat > "\$prompt_file"
if grep -Fq "Reply with exactly one word on the first non-empty line: proceed or refuse." "\$prompt_file"; then
  cat "\$prompt_file"
  printf '\nrefuse\nunderspecified\nAcceptance criteria are not specific enough to implement safely.\n'
  rm -f "\$prompt_file"
  exit 0
fi
cat "\$prompt_file" > "$unexpected_prompt"
rm -f "\$prompt_file"
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
  PATH="$tmpdir/bin:$PATH" HOME="$tmpdir/home" GRKR_GLEAM_PROJECT_ROOT="$repo_root" bash "$tmpdir/grkr.sh" --issue 1 >"$output_file" 2>&1
)

grep -F "✅ Startup validation passed (coding agent: codex)." "$output_file" >/dev/null
grep -F "🚀 Running coding agent (codex) to decide whether to implement the issue..." "$output_file" >/dev/null
grep -F "📝 Posting refusal checkpoint for issue #1..." "$output_file" >/dev/null
grep -F "📥 Moved issue #1 to Backlog." "$output_file" >/dev/null
grep -F "⏸️ Refused implementation for issue #1." "$output_file" >/dev/null
grep -F "🧹 Removed issue worktree:" "$output_file" >/dev/null

if grep -Fq "🚀 Running coding agent (codex) to implement the issue..." "$output_file"; then
  echo "implementation stage unexpectedly ran" >&2
  exit 1
fi

if grep -Fq "PR created" "$output_file"; then
  echo "PR should not be created for a refusal" >&2
  exit 1
fi

task_dir="$tmpdir/.grkr/tasks/issue-1-clarify-refusal-handling"
worktree_dir="$tmpdir/.grkr/worktrees/issue-1-clarify-refusal-handling"
[ -d "$task_dir" ]
[ ! -e "$worktree_dir" ]
[ -f "$task_dir/refusal.md" ]

grep -F "<!-- grkr:checkpoint stage=refusal task=issue-1-clarify-refusal-handling version=1 -->" "$task_dir/refusal.md" >/dev/null
grep -F "## Implementation refused" "$task_dir/refusal.md" >/dev/null
grep -F "underspecified" "$task_dir/refusal.md" >/dev/null
grep -F "Acceptance criteria are not specific enough to implement safely." "$task_dir/refusal.md" >/dev/null

jq -e '.status == "refused"' "$task_dir/progress.json" >/dev/null
jq -e '.decision == "refuse"' "$task_dir/progress.json" >/dev/null
jq -e '.stages.implement_or_refuse.status == "done"' "$task_dir/progress.json" >/dev/null
jq -e '.stages.implement_or_refuse.comment_id == 2002' "$task_dir/progress.json" >/dev/null
jq -e '.stages.implement_or_refuse.reason_class == "underspecified"' "$task_dir/progress.json" >/dev/null
jq -e '.stages.test.status == "skipped"' "$task_dir/progress.json" >/dev/null

grep -F "<!-- grkr:checkpoint stage=refusal task=issue-1-clarify-refusal-handling version=1 -->" "$issue_comment_body" >/dev/null
grep -F "<summary>Execution log</summary>" "$issue_comment_body" >/dev/null

grep -F 'gh project item-edit --id ITEM_1 --field-id FIELD_STATUS --project-id PROJECT_1 --single-select-option-id OPTION_BACKLOG' "$command_log" >/dev/null
grep -F 'git worktree remove --force' "$command_log" >/dev/null

if grep -Fq 'gh pr create' "$command_log"; then
  echo "PR creation should not happen for refusals" >&2
  exit 1
fi

if [ -f "$unexpected_prompt" ]; then
  echo "implementation prompt should not be generated for refusals" >&2
  exit 1
fi

cat >> "$tmpdir/.grkr/config.sh" <<'EOF'
REFUSAL_REQUIRES_BACKLOG_MOVE="false"
EOF
printf '' > "$command_log"

(
  cd "$tmpdir"
  PATH="$tmpdir/bin:$PATH" HOME="$tmpdir/home" GRKR_GLEAM_PROJECT_ROOT="$repo_root" bash "$tmpdir/worker-refuse-issue.sh" 1 underspecified "Still missing acceptance criteria." >>"$output_file" 2>&1
)

jq -e '.status == "refused"' "$task_dir/progress.json" >/dev/null
jq -e '.stages.implement_or_refuse.reason_class == "underspecified"' "$task_dir/progress.json" >/dev/null
if grep -Fq 'gh project item-edit' "$command_log"; then
  echo "standalone refusal worker should respect REFUSAL_REQUIRES_BACKLOG_MOVE=false" >&2
  exit 1
fi
