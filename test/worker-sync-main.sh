#!/bin/bash
set -euo pipefail

if ! command -v flock >/dev/null 2>&1; then
  echo "⚠️ flock not available, skipping worker-sync-main test"
  exit 0
fi

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/grkr-worker-sync-main.XXXXXX")
trap 'rm -rf "$tmpdir"' EXIT

repo_root=$(pwd)
real_git=$(command -v git)
git_log="$tmpdir/git.log"
mkdir -p "$tmpdir/bin" "$tmpdir/.grkr"

cat > "$tmpdir/.grkr/config.sh" <<'CONFIG'
MAIN_BRANCH="main"
CONFIG

cat > "$tmpdir/bin/git" <<EOF
#!/bin/bash
case "\$*" in
  'rev-parse --show-toplevel') printf '%s\n' "$tmpdir" ;;
  'fetch origin main --prune') printf 'fetch\n' >> "$git_log" ;;
  'checkout main') printf 'checkout\n' >> "$git_log" ;;
  'reset --hard origin/main') printf 'reset\n' >> "$git_log" ;;
  *) exec "$real_git" "\$@" ;;
esac
EOF

chmod +x "$tmpdir/bin/git"

(
  cd "$tmpdir"
  GRKR_ROOT="$tmpdir" GRKR_GLEAM_PROJECT_ROOT="$repo_root" PATH="$tmpdir/bin:$PATH" HOME="$tmpdir/home" bash "$repo_root/bin/worker-sync-main.sh"
)

[ -f "$tmpdir/.grkr/locks/main.lock" ]
grep -F 'fetch' "$git_log" >/dev/null
grep -F 'checkout' "$git_log" >/dev/null
grep -F 'reset' "$git_log" >/dev/null

: > "$git_log"
(
  cd "$tmpdir"
  exec 9>"$tmpdir/.grkr/locks/main.lock"
  flock -n 9
  sleep 2
) &
lock_holder=$!

sleep 0.2
set +e
(
  cd "$tmpdir"
  GRKR_ROOT="$tmpdir" GRKR_GLEAM_PROJECT_ROOT="$repo_root" PATH="$tmpdir/bin:$PATH" HOME="$tmpdir/home" bash "$repo_root/bin/worker-sync-main.sh"
)
status=$?
set -e

wait "$lock_holder"

[ "$status" -eq 75 ]
[ ! -s "$git_log" ]
