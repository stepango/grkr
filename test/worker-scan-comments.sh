#!/bin/bash
set -euo pipefail

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/grkr-worker-scan-comments.XXXXXX")
trap 'rm -rf "$tmpdir"' EXIT

cp bin/worker-scan-comments.sh "$tmpdir/worker-scan-comments.sh"
cp bin/worker-handle-comment.sh "$tmpdir/worker-handle-comment.sh"
cp bin/grkr-comment-workflow.sh "$tmpdir/grkr-comment-workflow.sh"
cp bin/grkr-issue-workflow.sh "$tmpdir/grkr-issue-workflow.sh"
cp bin/grkr-templates.sh "$tmpdir/grkr-templates.sh"
cp bin/doctor.sh "$tmpdir/doctor.sh"
chmod +x "$tmpdir/worker-scan-comments.sh" "$tmpdir/worker-handle-comment.sh" "$tmpdir/doctor.sh"

mkdir -p "$tmpdir/bin" "$tmpdir/.grkr/state" "$tmpdir/.grkr/logs/jobs"
real_git=$(command -v git)
comments_json="$tmpdir/comments.json"
issue_comment_body="$tmpdir/issue-comment-body.log"
reaction_log="$tmpdir/reaction.log"
command_log="$tmpdir/command.log"
commit_log="$tmpdir/commit.log"
next_reaction_id="$tmpdir/next-reaction-id"
printf '1\n' > "$next_reaction_id"
export TEST_TMPDIR="$tmpdir"
export TEST_COMMAND_LOG="$command_log"
export TEST_COMMENTS_JSON="$comments_json"
export TEST_ISSUE_COMMENT_BODY="$issue_comment_body"
export TEST_REACTION_LOG="$reaction_log"
export TEST_COMMIT_LOG="$commit_log"
export TEST_NEXT_REACTION_ID="$next_reaction_id"

cat > "$tmpdir/.grkr/config.sh" <<'EOF'
REPO="stepango/grkr"
MAIN_BRANCH="main"
EOF

cat > "$comments_json" <<'EOF'
[
  {
    "id": 300,
    "body": "hello",
    "updated_at": "2026-03-27T12:00:00Z",
    "issue_url": "https://api.github.com/repos/stepango/grkr/issues/1"
  },
  {
    "id": 301,
    "body": "  @:robot: answer-only explain the docs",
    "updated_at": "2026-03-27T12:01:00Z",
    "issue_url": "https://api.github.com/repos/stepango/grkr/issues/1"
  },
  {
    "id": 302,
    "body": "@:robot: code-change add missing file",
    "updated_at": "2026-03-27T12:02:00Z",
    "issue_url": "https://api.github.com/repos/stepango/grkr/issues/2"
  },
  {
    "id": 303,
    "body": "@:robot: triage review the label",
    "updated_at": "2026-03-27T12:03:00Z",
    "issue_url": "https://api.github.com/repos/stepango/grkr/issues/1"
  },
  {
    "id": 304,
    "body": "@:robot: refuse nope",
    "updated_at": "2026-03-27T12:04:00Z",
    "issue_url": "https://api.github.com/repos/stepango/grkr/issues/2"
  },
  {
    "id": 305,
    "body": "@:robot: broken",
    "updated_at": "2026-03-27T12:05:00Z",
    "issue_url": "https://api.github.com/repos/stepango/grkr/issues/1"
  }
]
EOF

cat > "$tmpdir/bin/gh" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$TEST_COMMAND_LOG"
case "${1-} ${2-}" in
  'auth status') exit 0 ;;
  'api repos/stepango/grkr/issues/comments')
    cat "$TEST_COMMENTS_JSON"
    ;;
  'api repos/stepango/grkr/issues/comments/300')
    jq -n '{id: 300, body: "hello", updated_at: "2026-03-27T12:00:00Z", issue_url: "https://api.github.com/repos/stepango/grkr/issues/1"}'
    ;;
  'api repos/stepango/grkr/issues/comments/301')
    jq -n '{id: 301, body: "  @:robot: answer-only explain the docs", updated_at: "2026-03-27T12:01:00Z", issue_url: "https://api.github.com/repos/stepango/grkr/issues/1"}'
    ;;
  'api repos/stepango/grkr/issues/comments/302')
    jq -n '{id: 302, body: "@:robot: code-change add missing file", updated_at: "2026-03-27T12:02:00Z", issue_url: "https://api.github.com/repos/stepango/grkr/issues/2"}'
    ;;
  'api repos/stepango/grkr/issues/comments/303')
    jq -n '{id: 303, body: "@:robot: triage review the label", updated_at: "2026-03-27T12:03:00Z", issue_url: "https://api.github.com/repos/stepango/grkr/issues/1"}'
    ;;
  'api repos/stepango/grkr/issues/comments/304')
    jq -n '{id: 304, body: "@:robot: refuse nope", updated_at: "2026-03-27T12:04:00Z", issue_url: "https://api.github.com/repos/stepango/grkr/issues/2"}'
    ;;
  'api repos/stepango/grkr/issues/comments/305')
    jq -n '{id: 305, body: "@:robot: broken", updated_at: "2026-03-27T12:05:00Z", issue_url: "https://api.github.com/repos/stepango/grkr/issues/1"}'
    ;;
  'api https://api.github.com/repos/stepango/grkr/issues/1')
    jq -n '{
      title: "Issue one",
      body: "Issue body",
      url: "https://github.com/stepango/grkr/issues/1",
      number: 1,
      comments: [
        {id: 300, body: "hello", user: {login: "alice"}},
        {id: 301, body: "  @:robot: answer-only explain the docs", user: {login: "alice"}},
        {id: 303, body: "@:robot: triage review the label", user: {login: "bob"}},
        {id: 305, body: "@:robot: broken", user: {login: "bob"}}
      ]
    }'
    ;;
  'api https://api.github.com/repos/stepango/grkr/issues/2')
    jq -n '{
      title: "PR issue",
      body: "PR body",
      url: "https://github.com/stepango/grkr/pull/2",
      number: 2,
      pull_request: {url: "https://api.github.com/repos/stepango/grkr/pulls/2"},
      comments: [
        {id: 302, body: "@:robot: code-change add missing file", user: {login: "carol"}},
        {id: 304, body: "@:robot: refuse nope", user: {login: "carol"}}
      ]
    }'
    ;;
  'api https://api.github.com/repos/stepango/grkr/pulls/2')
    jq -n '{head: {sha: "feedface", ref: "feature/comment-2"}}'
    ;;
  'api https://api.github.com/repos/stepango/grkr/issues/1/comments')
    jq -n '[
      {id: 300, body: "hello", user: {login: "alice"}},
      {id: 301, body: "  @:robot: answer-only explain the docs", user: {login: "alice"}},
      {id: 303, body: "@:robot: triage review the label", user: {login: "bob"}},
      {id: 305, body: "@:robot: broken", user: {login: "bob"}}
    ]'
    ;;
  'api https://api.github.com/repos/stepango/grkr/issues/2/comments')
    jq -n '[
      {id: 302, body: "@:robot: code-change add missing file", user: {login: "carol"}},
      {id: 304, body: "@:robot: refuse nope", user: {login: "carol"}}
    ]'
    ;;
  'api repos/stepango/grkr/issues/comments/300/reactions') printf '{"id":1}\n' ;;
  'api repos/stepango/grkr/issues/comments/301/reactions')
    id=$(cat "$TEST_NEXT_REACTION_ID")
    printf '{"id":%s}\n' "$id"
    case "$*" in
      *content=rocket*)
        printf '%s\n' "reaction:$id:rocket:post" >> "$TEST_REACTION_LOG"
        ;;
      *)
        printf '%s\n' "reaction:$id:eyes:post" >> "$TEST_REACTION_LOG"
        ;;
    esac
    printf '%s\n' "$((id + 1))" > "$TEST_NEXT_REACTION_ID"
    ;;
  'api repos/stepango/grkr/issues/comments/301/reactions/'*)
    printf '%s\n' "reaction_delete:${2##*/}" >> "$TEST_REACTION_LOG"
    ;;
  'api repos/stepango/grkr/issues/comments/302/reactions')
    id=$(cat "$TEST_NEXT_REACTION_ID")
    printf '{"id":%s}\n' "$id"
    case "$*" in
      *content=rocket*)
        printf '%s\n' "reaction:$id:rocket:post" >> "$TEST_REACTION_LOG"
        ;;
      *)
        printf '%s\n' "reaction:$id:eyes:post" >> "$TEST_REACTION_LOG"
        ;;
    esac
    printf '%s\n' "$((id + 1))" > "$TEST_NEXT_REACTION_ID"
    ;;
  'api repos/stepango/grkr/issues/comments/302/reactions/'*)
    printf '%s\n' "reaction_delete:${2##*/}" >> "$TEST_REACTION_LOG"
    ;;
  'api repos/stepango/grkr/issues/comments/303/reactions')
    id=$(cat "$TEST_NEXT_REACTION_ID")
    printf '{"id":%s}\n' "$id"
    case "$*" in
      *content=rocket*)
        printf '%s\n' "reaction:$id:rocket:post" >> "$TEST_REACTION_LOG"
        ;;
      *)
        printf '%s\n' "reaction:$id:eyes:post" >> "$TEST_REACTION_LOG"
        ;;
    esac
    printf '%s\n' "$((id + 1))" > "$TEST_NEXT_REACTION_ID"
    ;;
  'api repos/stepango/grkr/issues/comments/303/reactions/'*)
    printf '%s\n' "reaction_delete:${2##*/}" >> "$TEST_REACTION_LOG"
    ;;
  'api repos/stepango/grkr/issues/comments/304/reactions')
    id=$(cat "$TEST_NEXT_REACTION_ID")
    printf '{"id":%s}\n' "$id"
    case "$*" in
      *content=rocket*)
        printf '%s\n' "reaction:$id:rocket:post" >> "$TEST_REACTION_LOG"
        ;;
      *)
        printf '%s\n' "reaction:$id:eyes:post" >> "$TEST_REACTION_LOG"
        ;;
    esac
    printf '%s\n' "$((id + 1))" > "$TEST_NEXT_REACTION_ID"
    ;;
  'api repos/stepango/grkr/issues/comments/304/reactions/'*)
    printf '%s\n' "reaction_delete:${2##*/}" >> "$TEST_REACTION_LOG"
    ;;
  'api repos/stepango/grkr/issues/comments/305/reactions')
    id=$(cat "$TEST_NEXT_REACTION_ID")
    printf '{"id":%s}\n' "$id"
    case "$*" in
      *content=rocket*)
        printf '%s\n' "reaction:$id:rocket:post" >> "$TEST_REACTION_LOG"
        ;;
      *)
        printf '%s\n' "reaction:$id:eyes:post" >> "$TEST_REACTION_LOG"
        ;;
    esac
    printf '%s\n' "$((id + 1))" > "$TEST_NEXT_REACTION_ID"
    ;;
  'api repos/stepango/grkr/issues/comments/305/reactions/'*)
    printf '%s\n' "reaction_delete:${2##*/}" >> "$TEST_REACTION_LOG"
    ;;
  'issue comment')
    body=""
    shift 2
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --body-file)
          body=$(cat "$2")
          shift 2
          ;;
        --body)
          body=$2
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    printf '%s\n' "$body" >> "$TEST_ISSUE_COMMENT_BODY"
    ;;
  *) exit 0 ;;
esac
EOF

cat > "$tmpdir/bin/codex" <<'EOF'
#!/bin/bash
workdir=$PWD
while [ "$#" -gt 0 ]; do
  case "$1" in
    --cd)
      workdir=$2
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

prompt_file=$(mktemp "${TMPDIR:-/tmp}/grkr-worker-prompt.XXXXXX")
cat > "$prompt_file"

if grep -Fq 'Command text: answer-only explain the docs' "$prompt_file"; then
  printf '{"outcome":"answer-only","response":"Answer-only response for comment 301."}\n'
elif grep -Fq 'Command text: code-change add missing file' "$prompt_file"; then
  mkdir -p "$workdir"
  printf 'changed by codex\n' > "$workdir/comment-change.txt"
  printf '{"outcome":"code-change","response":"Code-change response for comment 302.","commit_message":"feat(robot): comment 302 code change"}\n'
elif grep -Fq 'Command text: triage review the label' "$prompt_file"; then
  printf '{"outcome":"triage","response":"Triage response for comment 303."}\n'
elif grep -Fq 'Command text: refuse nope' "$prompt_file"; then
  printf '{"outcome":"refuse","response":"Refusal response for comment 304."}\n'
elif grep -Fq 'Command text: broken' "$prompt_file"; then
  printf 'not-json\n'
else
  printf '{"outcome":"answer-only","response":"Default response."}\n'
fi

rm -f "$prompt_file"
EOF

cat > "$tmpdir/bin/git" <<'EOF'
#!/bin/bash
printf 'git %s\n' "$*" >> "$TEST_COMMAND_LOG"
case "$1 $2" in
  'rev-parse --show-toplevel')
    printf '%s\n' "$TEST_TMPDIR"
    ;;
  'show-ref --verify')
    case "$4" in
      refs/remotes/origin/main) exit 0 ;;
      refs/heads/robot/comment-301|refs/heads/robot/comment-302|refs/heads/robot/comment-303|refs/heads/robot/comment-304|refs/heads/robot/comment-305) exit 1 ;;
      *) exit 1 ;;
    esac
    ;;
  'ls-remote --heads') exit 1 ;;
  'worktree add')
    worktree_dir="${4-}"
    if [ "${3-}" = "-b" ]; then
      worktree_dir="${5-}"
      mkdir -p "$worktree_dir"
      : > "$worktree_dir/.git"
      printf 'worktree:add:%s:%s\n' "${4-}" "${6-}" >> "$TEST_COMMAND_LOG"
    else
      mkdir -p "$worktree_dir"
      : > "$worktree_dir/.git"
      printf 'worktree:add:%s:%s\n' "${3-}" "${4-}" >> "$TEST_COMMAND_LOG"
    fi
    ;;
  'reset --hard') exit 0 ;;
  'reset') exit 0 ;;
  'add -A') exit 0 ;;
  'diff --cached')
    case "$3" in
      --quiet)
        if [ -f comment-change.txt ]; then
          exit 1
        fi
        exit 0
        ;;
      --name-only)
        exit 0
        ;;
    esac
    ;;
  'commit -m')
    printf 'commit:%s\n' "${3-}" >> "$TEST_COMMIT_LOG"
    exit 0
    ;;
  *) exit 0 ;;
esac
EOF

cat > "$tmpdir/bin/flock" <<'EOF'
#!/bin/bash
exit 0
EOF

chmod +x "$tmpdir/bin/gh" "$tmpdir/bin/codex" "$tmpdir/bin/git" "$tmpdir/bin/flock"

output_file="$tmpdir/output.log"
(
  cd "$tmpdir"
  PATH="$tmpdir/bin:$PATH" HOME="$tmpdir/home" bash "$tmpdir/worker-scan-comments.sh" >"$output_file" 2>&1
)

grep -F '✅ Processed 4 actionable comment(s).' "$output_file" >/dev/null
grep -F 'ℹ️ Skipped 1 comment(s).' "$output_file" >/dev/null
grep -F 'ℹ️ Failed 1 comment(s).' "$output_file" >/dev/null
grep -F 'SCHEDULED_COMMENTS=4' "$output_file" >/dev/null
grep -F 'ACTIONABLE_COMMENTS=5' "$output_file" >/dev/null
grep -F 'Answer-only response for comment 301.' "$issue_comment_body" >/dev/null
grep -F 'Code-change response for comment 302.' "$issue_comment_body" >/dev/null
grep -F 'Triage response for comment 303.' "$issue_comment_body" >/dev/null
grep -F 'Refusal response for comment 304.' "$issue_comment_body" >/dev/null
if grep -Fq 'broken' "$issue_comment_body"; then
  exit 1
fi

grep -F 'reaction:' "$reaction_log" >/dev/null
grep -F 'reaction_delete:' "$reaction_log" >/dev/null
[ "$(grep -c ':eyes:post' "$reaction_log")" -eq 5 ]
[ "$(grep -c ':rocket:post' "$reaction_log")" -eq 4 ]
[ "$(grep -c '^reaction_delete:' "$reaction_log")" -eq 5 ]

grep -F 'worktree:add:robot/comment-301:origin/main' "$command_log" >/dev/null
grep -F 'worktree:add:robot/comment-302:feedface' "$command_log" >/dev/null
grep -F 'worktree:add:robot/comment-303:origin/main' "$command_log" >/dev/null
grep -F 'worktree:add:robot/comment-304:feedface' "$command_log" >/dev/null
grep -F 'worktree:add:robot/comment-305:origin/main' "$command_log" >/dev/null
grep -F 'commit:feat(robot): comment 302 code change' "$commit_log" >/dev/null
grep -F 'changed by codex' "$tmpdir/.grkr/worktrees/comment-302/comment-change.txt" >/dev/null

jq -e '.["301"].status == "done" and .["301"].outcome == "answer-only"' "$tmpdir/.grkr/state/processed_comments.json" >/dev/null
jq -e '.["302"].status == "done" and .["302"].outcome == "code-change"' "$tmpdir/.grkr/state/processed_comments.json" >/dev/null
jq -e '.["303"].status == "done" and .["303"].outcome == "triage"' "$tmpdir/.grkr/state/processed_comments.json" >/dev/null
jq -e '.["304"].status == "done" and .["304"].outcome == "refuse"' "$tmpdir/.grkr/state/processed_comments.json" >/dev/null
if jq -e 'has("305")' "$tmpdir/.grkr/state/processed_comments.json" >/dev/null; then
  exit 1
fi

[ -f "$tmpdir/.grkr/state/last_comment_scan_at" ]
