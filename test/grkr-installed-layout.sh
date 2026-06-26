#!/bin/bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/grkr-installed-layout.XXXXXX")
trap 'rm -rf "$tmpdir"' EXIT

pkg_bindir="$tmpdir/lib/node_modules/grkr/bin"
mkdir -p "$pkg_bindir" "$tmpdir/bin" "$tmpdir/.grkr"

cp bin/grkr "$pkg_bindir/grkr"
cp bin/grkr-issue-workflow.sh "$pkg_bindir/grkr-issue-workflow.sh"
cp bin/grkr-project-status.sh "$pkg_bindir/grkr-project-status.sh"
cp bin/grkr-task-slug.sh "$pkg_bindir/grkr-task-slug.sh"
cp bin/grkr-templates.sh "$pkg_bindir/grkr-templates.sh"
cp bin/doctor.sh "$pkg_bindir/doctor.sh"
chmod +x "$pkg_bindir/grkr" "$pkg_bindir/doctor.sh"
bash "$(dirname "$0")/test-copy-grkr-lib.sh" "$pkg_bindir"

ln -s "$pkg_bindir/grkr" "$tmpdir/bin/grkr"
ln -s "$pkg_bindir/doctor.sh" "$tmpdir/bin/doctor.sh"

real_git=$(command -v git)

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
  PATH="$tmpdir/bin:$PATH" HOME="$tmpdir/home" GRKR_GLEAM_PROJECT_ROOT="$repo_root" "$tmpdir/bin/grkr" init 42 >"$output_file" 2>&1
)

grep -F "✅ Created config: $tmpdir/.grkr/config.sh" "$output_file" >/dev/null
grep -F 'REPO="stepango/grkr"' "$tmpdir/.grkr/config.sh" >/dev/null
