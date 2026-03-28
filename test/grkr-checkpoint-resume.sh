#!/bin/bash
set -euo pipefail

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/grkr-checkpoint-resume.XXXXXX")
trap 'rm -rf "$tmpdir"' EXIT

cp bin/grkr "$tmpdir/grkr.sh"
cp bin/doctor.sh "$tmpdir/doctor.sh"
chmod +x "$tmpdir/grkr.sh"
chmod +x "$tmpdir/doctor.sh"

real_git=$(command -v git)
mkdir -p "$tmpdir/bin"
gh_log="$tmpdir/gh.log"
issue_comment_body="$tmpdir/issue-comment-body.log"
comments_json="$tmpdir/comments.json"
next_comment_id="$tmpdir/next-comment-id"
mkdir -p "$tmpdir/.grkr/tasks/issue-1-test-issue"

cat > "$tmpdir/.grkr/config.sh" <<'EOF'
REPO="stepango/grkr"
PROJECT_OWNER="stepango"
PROJECT_NUMBER="1"
STATUS_FIELD_NAME="Status"
TODO_VALUE="Todo"
IN_PROGRESS_VALUE="In Progress"
BACKLOG_VALUE="Backlog"
PRIORITY_FIELD_NAME="Priority"
EOF

cat > "$comments_json" <<'EOF'
[
  {
    "id": 1111,
    "body": "<!-- grkr:checkpoint stage=research task=issue-1-test-issue version=1 -->\n\n## Research checkpoint\n\n### Problem statement\n\nExisting research.\n"
  },
  {
    "id": 1112,
    "body": "<!-- grkr:checkpoint stage=plan task=issue-1-test-issue version=1 -->\n\n## Plan checkpoint\n\n### Implementation plan\n\n1. Existing plan.\n\n## Refusal assessment\n\n- Is the issue implementable now? Yes.\n"
  }
]
EOF
printf '1113\n' > "$next_comment_id"

cat > "$tmpdir/.grkr/tasks/issue-1-test-issue/research.md" <<'EOF'
<!-- grkr:checkpoint stage=research task=issue-1-test-issue version=1 -->

## Research checkpoint

### Problem statement

Existing research.
EOF

cat > "$tmpdir/.grkr/tasks/issue-1-test-issue/plan.md" <<'EOF'
<!-- grkr:checkpoint stage=plan task=issue-1-test-issue version=1 -->

## Plan checkpoint

### Implementation plan

1. Existing plan.

## Refusal assessment

- Is the issue implementable now? Yes.
EOF

cat > "$tmpdir/bin/gh" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$gh_log"
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
  'pr create') echo 'https://example.com/pr/1' ;;
  'project view') printf '{"id":"PROJECT_1"}\n' ;;
  'project field-list') printf '[{"id":"FIELD_STATUS","name":"Status","options":[{"id":"OPTION_TODO","name":"Todo"},{"id":"OPTION_IN_PROGRESS","name":"In Progress"}]}]\n' ;;
  'project item-edit') exit 0 ;;
  'issue edit') exit 0 ;;
  *) exit 0 ;;
esac
EOF

cat > "$tmpdir/bin/codex" <<'EOF'
#!/bin/bash
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
case "\$1 \$2" in
  'rev-parse --show-toplevel') printf '%s\n' "$tmpdir" ;;
  'remote get-url') printf 'git@github.com:stepango/grkr.git\n' ;;
  'status --porcelain') exit 0 ;;
  'ls-remote --heads') exit 1 ;;
  'checkout -b') exit 0 ;;
  'add .') exit 0 ;;
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

grep -F "♻️ Reusing research checkpoint for issue #1 from comment 1111." "$output_file" >/dev/null
grep -F "♻️ Reusing plan checkpoint for issue #1 from comment 1112." "$output_file" >/dev/null
if grep -Fq "<!-- grkr:checkpoint stage=research task=issue-1-test-issue version=1 -->" "$issue_comment_body"; then
  exit 1
fi
if grep -Fq "<!-- grkr:checkpoint stage=plan task=issue-1-test-issue version=1 -->" "$issue_comment_body"; then
  exit 1
fi
grep -F "<summary>Execution log</summary>" "$issue_comment_body" >/dev/null
jq -e '.stages.research.comment_id == 1111' "$tmpdir/.grkr/tasks/issue-1-test-issue/progress.json" >/dev/null
jq -e '.stages.plan.comment_id == 1112' "$tmpdir/.grkr/tasks/issue-1-test-issue/progress.json" >/dev/null
