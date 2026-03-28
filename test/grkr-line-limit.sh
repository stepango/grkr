#!/bin/bash
set -euo pipefail

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/grkr-line-limit.XXXXXX")
trap 'rm -rf "$tmpdir"' EXIT

cp bin/grkr "$tmpdir/grkr.sh"
cp bin/grkr-templates.sh "$tmpdir/grkr-templates.sh"
cp bin/doctor.sh "$tmpdir/doctor.sh"
chmod +x "$tmpdir/grkr.sh"
chmod +x "$tmpdir/doctor.sh"

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
if [ "\$calls" -eq 2 ]; then
  sed -n '1,999p' "$big_file" > "$big_file.fixed"
  mv "$big_file.fixed" "$big_file"
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
case "\$*" in
  'rev-parse --show-toplevel') printf '%s\n' "$tmpdir" ;;
  'remote get-url origin') printf 'git@github.com:stepango/grkr.git\n' ;;
  'status --porcelain') exit 0 ;;
  'ls-remote --heads origin issue-1') exit 1 ;;
  'checkout -b issue-1') exit 0 ;;
  'add .') exit 0 ;;
  'diff --cached --name-only --diff-filter=ACMR -z') printf '%s\0' "$big_file" ;;
  'diff --cached --quiet') exit 1 ;;
  "show :$big_file") cat "$big_file" ;;
  'commit -m feat: implement #1 - Test issue') exit 0 ;;
  'push -u origin issue-1') exit 0 ;;
  *) exec "$real_git" "\$@" ;;
esac
EOF

chmod +x "$tmpdir/bin/gh" "$tmpdir/bin/codex" "$tmpdir/bin/git" "$tmpdir/bin/timeout" "$tmpdir/bin/flock"

output_file="$tmpdir/output.log"
(
  cd "$tmpdir"
  PATH="$tmpdir/bin:$PATH" HOME="$tmpdir/home" bash "$tmpdir/grkr.sh" --project 1 >"$output_file" 2>&1 &
  pid=$!

  for _ in 1 2 3 4 5 6; do
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
grep -F "Asking codex to refactor before publish." "$output_file" >/dev/null
grep -F "✅ codex has finished remediate file line-limit violations." "$output_file" >/dev/null
grep -F "✅ PR created: https://example.com/pr/1" "$output_file" >/dev/null
! grep -F "Commit aborted due to file size limit." "$output_file" >/dev/null
grep -F "No file may exceed 1000 lines." "$codex_prompt_log" >/dev/null
grep -F "still violates the repository file-size policy" "$codex_prompt_log" >/dev/null
[ "$(cat "$codex_call_count")" = "2" ]
