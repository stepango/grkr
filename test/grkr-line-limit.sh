#!/bin/bash
set -euo pipefail

repo_root=$(pwd)
tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/grkr-line-limit.XXXXXX")
trap 'rm -rf "$tmpdir"' EXIT

cp bin/grkr "$tmpdir/grkr.sh"
cp bin/grkr-issue-workflow.sh "$tmpdir/grkr-issue-workflow.sh"
cp bin/grkr-project-status.sh "$tmpdir/grkr-project-status.sh"
cp bin/grkr-task-slug.sh "$tmpdir/grkr-task-slug.sh"
cp bin/grkr-templates.sh "$tmpdir/grkr-templates.sh"
cp bin/doctor.sh "$tmpdir/doctor.sh"
chmod +x "$tmpdir/grkr.sh"
chmod +x "$tmpdir/doctor.sh"
bash "$(dirname "$0")/test-copy-grkr-lib.sh" "$tmpdir"

big_file="$tmpdir/big-file.md"
seq 1 1001 | sed 's/^/line /' > "$big_file"

real_git=$(command -v git)
mkdir -p "$tmpdir/bin"
mkdir -p "$tmpdir/.grkr"
codex_prompt_log="$tmpdir/codex-prompts.log"
codex_call_count="$tmpdir/codex-call-count"
printf '0\n' > "$codex_call_count"

cat > "$tmpdir/.grkr/config.sh" <<'EOF'
REPO="stepango/grkr"
PROJECT_OWNER="stepango"
PROJECT_NUMBER="1"
STATUS_FIELD_NAME="Status"
TODO_VALUE="Todo"
BACKLOG_VALUE="Backlog"
PRIORITY_FIELD_NAME="Priority"
ENABLE_PROJECT_STATUS_UPDATES="false"
TEST_COMMAND="printf 'test command passed\n'"
EOF

cat > "$tmpdir/bin/gh" <<'EOF'
#!/bin/bash
case "$1 $2" in
  'auth status') exit 0 ;;
  'issue list') printf '[{"number":1,"projectItems":[{"status":{"name":"Todo"}}]}]\n' ;;
  'issue view') printf '{"title":"Test issue","body":"Body","url":"https://example.com","number":1,"projectItems":[{"status":{"name":"Todo"}}],"comments":[]}\n' ;;
  'issue comment') exit 0 ;;
  'pr list') printf '[]\n' ;;
  'pr create') echo 'https://example.com/pr/1' ;;
  'issue edit') exit 0 ;;
  *) exit 0 ;;
esac
EOF

cat > "$tmpdir/bin/codex" <<EOF
#!/bin/bash
if [ "\${1-}" = "--help" ]; then
  exit 0
fi
calls=\$(cat "$codex_call_count")
calls=\$((calls + 1))
printf '%s\n' "\$calls" > "$codex_call_count"
prompt_file=\$(mktemp "${TMPDIR:-/tmp}/grkr-line-limit-prompt.XXXXXX")
cat > "\$prompt_file"
printf -- '--- prompt %s ---\n' "\$calls" >> "$codex_prompt_log"
cat "\$prompt_file" >> "$codex_prompt_log"
printf '\n' >> "$codex_prompt_log"
if grep -Fq "Reply with exactly one word on the first non-empty line: proceed or refuse." "\$prompt_file"; then
  printf 'proceed\n'
elif [ "\$calls" -eq 3 ]; then
  printf 'refactor pass complete\n'
  sed -n '1,999p' "$big_file" > "$big_file.fixed"
  mv "$big_file.fixed" "$big_file"
else
  printf '## Detailed description of the task\n'
  i=1
  while [ "\$i" -le 1005 ]; do
    printf 'implementation line %s\n' "\$i"
    i=\$((i + 1))
  done
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
  'diff --name-only') printf 'big-file.md\n' ;;
  'diff --cached')
    case "\$3" in
      --name-only)
        if [ "\${4-}" = "--diff-filter=ACMR" ]; then
          printf 'big-file.md\0'
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
  'show :big-file.md') cat "$big_file" ;;
  'commit -m') exit 0 ;;
  'push -u') exit 0 ;;
  *) exec "$real_git" "\$@" ;;
esac
EOF

chmod +x "$tmpdir/bin/gh" "$tmpdir/bin/codex" "$tmpdir/bin/git" "$tmpdir/bin/timeout" "$tmpdir/bin/flock"

output_file="$tmpdir/output.log"
task_dir="$tmpdir/.grkr/tasks/issue-1-test-issue"
(
  cd "$tmpdir"
  PATH="$tmpdir/bin:$PATH" HOME="$tmpdir/home" GRKR_GLEAM_PROJECT_ROOT="$repo_root" bash "$tmpdir/grkr.sh" --project 1 >"$output_file" 2>&1 &
  pid=$!

  for _ in $(seq 1 60); do
    if grep -Fq "✅ PR created: https://example.com/pr/1" "$output_file"; then
      break
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      break
    fi
    sleep 1
  done

  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
)

grep -F "has 1001 lines" "$output_file" >/dev/null
grep -F "Files must be 1000 lines or fewer." "$output_file" >/dev/null
grep -F "Asking coding agent to refactor before publish." "$output_file" >/dev/null
grep -F "✅ coding agent (codex/remediate) finished remediate file line-limit violations." "$output_file" >/dev/null
grep -F "✅ PR created: https://example.com/pr/1" "$output_file" >/dev/null
! grep -F "Commit aborted due to file size limit." "$output_file" >/dev/null
grep -F "No file may exceed 1000 lines." "$codex_prompt_log" >/dev/null
grep -F "still violates the repository file-size policy" "$codex_prompt_log" >/dev/null
[ -f "$task_dir/implementation.log" ]
grep -F "# Sharded Codex Output" "$task_dir/implementation.log" >/dev/null
grep -F 'codex/implementation.log.parts/part-0000' "$task_dir/implementation.log" >/dev/null
[ -f "$task_dir/codex/implementation.log.parts/part-0000" ]
[ -f "$task_dir/codex/implementation.log.parts/part-0001" ]
[ "$(wc -l < "$task_dir/codex/implementation.log.parts/part-0000" | tr -d '[:space:]')" = "1000" ]
[ "$(cat "$codex_call_count")" = "3" ]
