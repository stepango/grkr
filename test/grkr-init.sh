#!/bin/bash
set -euo pipefail

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/grkr-init.XXXXXX")
trap 'rm -rf "$tmpdir"' EXIT

cp bin/grkr "$tmpdir/grkr.sh"
cp bin/doctor.sh "$tmpdir/doctor.sh"
chmod +x "$tmpdir/grkr.sh"
chmod +x "$tmpdir/doctor.sh"

real_git=$(command -v git)
mkdir -p "$tmpdir/bin"
mkdir -p "$tmpdir/.grkr"

cat > "$tmpdir/bin/git" <<EOF
#!/bin/bash
case "\$1 \$2" in
  'rev-parse --show-toplevel') printf '%s\n' "$tmpdir" ;;
  'remote get-url') printf 'git@github.com:stepango/grkr.git\n' ;;
  *) exec "$real_git" "\$@" ;;
esac
EOF

chmod +x "$tmpdir/bin/git"

output_file="$tmpdir/output.log"
(
  cd "$tmpdir"
  PATH="$tmpdir/bin:$PATH" HOME="$tmpdir/home" bash "$tmpdir/grkr.sh" init 42 >"$output_file" 2>&1
)

grep -F "✅ Created config: $tmpdir/.grkr/config.sh" "$output_file" >/dev/null
grep -F 'REPO="stepango/grkr"' "$tmpdir/.grkr/config.sh" >/dev/null
grep -F 'MAIN_BRANCH="main"' "$tmpdir/.grkr/config.sh" >/dev/null
grep -F 'PROJECT_OWNER="stepango"' "$tmpdir/.grkr/config.sh" >/dev/null
grep -F 'PROJECT_NUMBER="42"' "$tmpdir/.grkr/config.sh" >/dev/null
grep -F 'LOOP_INTERVAL_SECS="20"' "$tmpdir/.grkr/config.sh" >/dev/null
