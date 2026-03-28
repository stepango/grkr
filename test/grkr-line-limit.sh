#!/bin/bash
set -euo pipefail

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/grkr-line-limit.XXXXXX")
trap 'rm -rf "$tmpdir"' EXIT

cp bin/grkr "$tmpdir/grkr.sh"
chmod +x "$tmpdir/grkr.sh"

big_file="$tmpdir/big-file.md"
seq 1 1001 | sed 's/^/line /' > "$big_file"

real_git=$(command -v git)
mkdir -p "$tmpdir/bin"

cat > "$tmpdir/bin/gh" <<'EOF'
#!/bin/bash
case "$1 $2" in
  'auth status') exit 0 ;;
  'issue list') printf '[{"number":1,"projectItems":[{"status":{"name":"Todo"}}]}]\n' ;;
  'issue view') printf '{"title":"Test issue","body":"Body","url":"https://example.com","number":1}\n' ;;
  *) exit 0 ;;
esac
EOF

cat > "$tmpdir/bin/codex" <<'EOF'
#!/bin/bash
exit 0
EOF

cat > "$tmpdir/bin/git" <<EOF
#!/bin/bash
case "\$*" in
  'status --porcelain') exit 0 ;;
  'ls-remote --heads origin issue-1') exit 1 ;;
  'checkout -b issue-1') exit 0 ;;
  'add .') exit 0 ;;
  'diff --cached --name-only --diff-filter=ACMR -z') printf '%s\0' "$big_file" ;;
  'diff --cached --quiet') exit 1 ;;
  "show :$big_file") cat "$big_file" ;;
  *) exec "$real_git" "\$@" ;;
esac
EOF

chmod +x "$tmpdir/bin/gh" "$tmpdir/bin/codex" "$tmpdir/bin/git"

output_file="$tmpdir/output.log"
PATH="$tmpdir/bin:$PATH" HOME="$tmpdir/home" bash "$tmpdir/grkr.sh" --project 1 >"$output_file" 2>&1 &
pid=$!

for _ in 1 2 3 4 5; do
  if grep -Fq "Commit aborted due to file size limit." "$output_file"; then
    break
  fi
  if ! kill -0 "$pid" 2>/dev/null; then
    break
  fi
  sleep 1
done

kill "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true

grep -F "Commit aborted due to file size limit." "$output_file" >/dev/null
grep -F "has 1001 lines" "$output_file" >/dev/null
grep -F "Files must be 1000 lines or fewer." "$output_file" >/dev/null
