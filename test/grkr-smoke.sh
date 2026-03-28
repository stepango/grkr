#!/bin/bash
set -euo pipefail

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/grkr-smoke.XXXXXX")
trap 'rm -rf "$tmpdir"' EXIT

cp bin/grkr "$tmpdir/grkr.sh"
chmod +x "$tmpdir/grkr.sh"

real_git=$(command -v git)
mkdir -p "$tmpdir/bin"
gh_log="$tmpdir/gh.log"

cat > "$tmpdir/bin/gh" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$gh_log"
case "\$1 \$2" in
  'auth status') exit 0 ;;
  'issue view') printf '{"title":"Test issue","body":"Body","url":"https://example.com","number":1}\n' ;;
  'pr create') echo 'https://example.com/pr/1' ;;
  'issue edit') exit 0 ;;
  *) exit 0 ;;
esac
EOF

cat > "$tmpdir/bin/codex" <<'EOF'
#!/bin/bash
exit 0
EOF

cat > "$tmpdir/bin/git" <<EOF
#!/bin/bash
case "\$1 \$2" in
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

chmod +x "$tmpdir/bin/gh" "$tmpdir/bin/codex" "$tmpdir/bin/git"

output_file="$tmpdir/output.log"
PATH="$tmpdir/bin:$PATH" HOME="$tmpdir/home" bash "$tmpdir/grkr.sh" --issue 1 >"$output_file" 2>&1

grep -F "✅ Prerequisites validated." "$output_file" >/dev/null
grep -F "🚀 Running codex to implement the issue..." "$output_file" >/dev/null
grep -F "✅ codex has finished implementing the changes." "$output_file" >/dev/null
grep -F "✅ PR created: https://example.com/pr/1" "$output_file" >/dev/null
grep -F "Fixes #1" "$gh_log" >/dev/null
grep -F "Issue: https://example.com" "$gh_log" >/dev/null
