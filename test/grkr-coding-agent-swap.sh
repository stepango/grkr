#!/usr/bin/env bash
# Unit test: GRKR_CODING_AGENT + per-step overrides dispatch codex vs grok.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/grkr-agent-swap.XXXXXX")
trap 'rm -rf "$tmpdir"' EXIT

mkdir -p "$tmpdir/bin" "$tmpdir/work"
export PATH="$tmpdir/bin:$PATH"
export SCRIPT_DIR="$root/bin"
# shellcheck source=/dev/null
. "$root/bin/lib/issue_shared.sh"

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

unset GRKR_CODING_AGENT CODING_AGENT CODEX_ARGS GROK_ARGS \
  GRKR_AGENT_DECISION GRKR_AGENT_IMPLEMENT GRKR_AGENT_REMEDIATE || true

# Default → codex
run_codex_prompt "$prompt" "$out" "unit default" replace "$tmpdir/work" >/dev/null
grep -Fq "CODEX_BACKEND" "$out"
grep -Fq "hello agent" "$out"

# Explicit global grok
rm -f "$out"
GRKR_CODING_AGENT=grok GROK_BIN="$tmpdir/bin/grok" \
  run_codex_prompt "$prompt" "$out" "unit grok" replace "$tmpdir/work" >/dev/null
grep -Fq "GROK_BACKEND" "$out"

# Phase label maps decision step
msg=$(GRKR_CODING_AGENT=codex run_codex_prompt "$prompt" "$out" \
  "decide whether to implement the issue" replace "$tmpdir/work" 2>&1)
printf '%s\n' "$msg" | grep -Fq "coding agent (codex/decision)"

# Per-step override: decision=grok while default=codex
rm -f "$out"
unset GRKR_CODING_AGENT
export GRKR_AGENT_DECISION=grok GROK_BIN="$tmpdir/bin/grok"
run_codex_prompt "$prompt" "$out" "decide whether to implement the issue" replace "$tmpdir/work" >/dev/null
grep -Fq "GROK_BACKEND" "$out"
# implement still default codex
rm -f "$out"
run_codex_prompt "$prompt" "$out" "implement the issue" replace "$tmpdir/work" >/dev/null
grep -Fq "CODEX_BACKEND" "$out"
# remediate override
rm -f "$out"
export GRKR_AGENT_REMEDIATE=grok
run_codex_prompt "$prompt" "$out" "remediate file line-limit violations" replace "$tmpdir/work" >/dev/null
grep -Fq "GROK_BACKEND" "$out"
unset GRKR_AGENT_DECISION GRKR_AGENT_IMPLEMENT GRKR_AGENT_REMEDIATE

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
grep -Fq "Unknown coding agent" "$tmpdir/err.txt"

# CODEX_ARGS passthrough
rm -f "$out"
CODEX_ARGS='-c model=test-model' \
  run_codex_prompt "$prompt" "$out" "args" replace "$tmpdir/work" >/dev/null
grep -Fq "model=test-model" "$out"

echo "grkr-coding-agent-swap: ok"
