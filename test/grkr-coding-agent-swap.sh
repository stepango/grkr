#!/usr/bin/env bash
# Unit test: GRKR_CODING_AGENT dispatches codex vs grok backends.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/grkr-agent-swap.XXXXXX")
trap 'rm -rf "$tmpdir"' EXIT

mkdir -p "$tmpdir/bin" "$tmpdir/work"
export PATH="$tmpdir/bin:$PATH"
export SCRIPT_DIR="$root/bin"
# shellcheck source=/dev/null
. "$root/bin/lib/issue_shared.sh"

# Stub persist so we don't need Gleam task_log.
persist_task_log_output() {
  local src=$1 dest=$2
  cat "$src" >"$dest"
}

cat >"$tmpdir/bin/codex" <<'EOF'
#!/usr/bin/env bash
echo "CODEX_BACKEND $*"
cat
exit 0
EOF
chmod +x "$tmpdir/bin/codex"

cat >"$tmpdir/bin/grok" <<'EOF'
#!/usr/bin/env bash
echo "GROK_BACKEND $*"
# consume --prompt-file if present
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt-file) cat "$2"; shift 2 ;;
    *) shift ;;
  esac
done
exit 0
EOF
chmod +x "$tmpdir/bin/grok"

prompt="$tmpdir/prompt.txt"
echo "hello agent" >"$prompt"
out="$tmpdir/out.log"

unset GRKR_CODING_AGENT CODING_AGENT CODEX_ARGS GROK_ARGS || true

# Default → codex
run_codex_prompt "$prompt" "$out" "unit default" replace "$tmpdir/work" >/dev/null
grep -Fq "CODEX_BACKEND" "$out"
grep -Fq "hello agent" "$out"
grep -Fq "coding agent (codex)" <(GRKR_CODING_AGENT=codex run_codex_prompt "$prompt" "$out" "unit codex msg" replace "$tmpdir/work" 2>&1 | tee "$tmpdir/msg1.txt") || \
  grep -Fq "Running coding agent (codex)" "$tmpdir/msg1.txt"

# Explicit grok
rm -f "$out"
GRKR_CODING_AGENT=grok GROK_BIN="$tmpdir/bin/grok" \
  run_codex_prompt "$prompt" "$out" "unit grok" replace "$tmpdir/work" >/dev/null
grep -Fq "GROK_BACKEND" "$out"
grep -Fq "hello agent" "$out"

# Alias name
rm -f "$out"
CODING_AGENT=grok GROK_BIN="$tmpdir/bin/grok" \
  run_coding_agent_prompt "$prompt" "$out" "unit alias" replace "$tmpdir/work" >/dev/null
grep -Fq "GROK_BACKEND" "$out"

# Unknown agent fails
if GRKR_CODING_AGENT=nope run_codex_prompt "$prompt" "$out" "bad" replace "$tmpdir/work" >/dev/null 2>"$tmpdir/err.txt"; then
  echo "expected unknown agent to fail" >&2
  exit 1
fi
grep -Fq "Unknown GRKR_CODING_AGENT" "$tmpdir/err.txt"

# CODEX_ARGS passthrough
rm -f "$out"
CODEX_ARGS='-c model=test-model' \
  run_codex_prompt "$prompt" "$out" "args" replace "$tmpdir/work" >/dev/null
grep -Fq "model=test-model" "$out"

echo "grkr-coding-agent-swap: ok"
