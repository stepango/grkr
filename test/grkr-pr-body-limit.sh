#!/bin/bash
set -euo pipefail

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/grkr-pr-body-limit.XXXXXX")
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
pr_body="$tmpdir/pr-body.log"
mkdir -p "$tmpdir/.grkr"

cat > "$tmpdir/.grkr/config.sh" <<'EOF'
REPO="stepango/grkr"
PROJECT_OWNER="stepango"
PROJECT_NUMBER="1"
STATUS_FIELD_NAME="Status"
TODO_VALUE="Todo"
BACKLOG_VALUE="Backlog"
PRIORITY_FIELD_NAME="Priority"
TEST_COMMAND="printf 'test command passed\n'"
EOF

cat > "$tmpdir/bin/gh" <<EOF
#!/bin/bash
case "\${1-} \${2-}" in
  'auth status') exit 0 ;;
  'issue view') printf '{"title":"Large body issue","body":"Body","url":"https://example.com/issues/1","number":1}\n' ;;
  'pr list') printf '[]\n' ;;
  'pr create')
    shift 2
    while [ "\$#" -gt 0 ]; do
      case "\$1" in
        --body-file)
          cat "\$2" > "$pr_body"
          if [ "\$(wc -m < "$pr_body" | tr -d '[:space:]')" -gt 65536 ]; then
            printf 'GraphQL: Body is too long, Body is too long (maximum is 65536 characters) (createPullRequest)\n' >&2
            exit 1
          fi
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    echo 'https://example.com/pr/1'
    ;;
  'issue edit') exit 0 ;;
  'issue comment') exit 0 ;;
  *) exit 0 ;;
esac
EOF

cat > "$tmpdir/bin/codex" <<'EOF'
#!/bin/bash
prompt_file=$(mktemp "${TMPDIR:-/tmp}/grkr-pr-limit-prompt.XXXXXX")
cat > "$prompt_file"
if grep -Fq "Reply with exactly one word on the first non-empty line: proceed or refuse." "$prompt_file"; then
  printf 'proceed\n'
else
  printf '## Detailed description of the task\n\n'
  awk 'BEGIN { for (i = 0; i < 70000; i++) printf "A"; printf "\n\n## Implementation plan details\n\n- Step\n\n## Testing results\n\n- Functional testing performed\n" }'
fi
rm -f "$prompt_file"
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
  'show-ref --verify') exit 1 ;;
  'ls-remote --heads') exit 1 ;;
  'worktree add')
    mkdir -p "\${5-}"
    exit 0
    ;;
  'reset ') exit 0 ;;
  'diff --name-only') printf 'README.md\n' ;;
  'diff --cached')
    case "\$3" in
      --quiet) exit 1 ;;
      --name-only) exit 0 ;;
    esac
    ;;
  'ls-files --others') exit 0 ;;
  'add -A') exit 0 ;;
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

grep -F "✅ PR created: https://example.com/pr/1" "$output_file" >/dev/null
grep -F "exceeded GitHub's PR body size limit" "$pr_body" >/dev/null
grep -F "Fixes #1" "$pr_body" >/dev/null
if grep -Fq "Issue: [#1](https://example.com/issues/1)" "$pr_body"; then
  echo "unexpected duplicate issue mention in PR body"
  exit 1
fi
[ "$(wc -m < "$pr_body" | tr -d '[:space:]')" -le 65536 ]
