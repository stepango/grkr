#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

marker=$(gleam run -m grkr/progress/cli -- marker research issue-71-progress-cli)
expected='<!-- grkr:checkpoint stage=research task=issue-71-progress-cli version=1 -->'
if [ "$marker" != "$expected" ]; then
  printf 'unexpected marker: %s\n' "$marker" >&2
  exit 1
fi

checkpoint=$(gleam run -m grkr/progress/cli -- render-checkpoint plan issue-71-progress-cli 'Plan body')
plan_expected='<!-- grkr:checkpoint stage=plan task=issue-71-progress-cli version=1 -->'
case "$checkpoint" in
  *"$plan_expected"*) ;;
  *)
    printf 'rendered checkpoint missing marker\n%s\n' "$checkpoint" >&2
    exit 1
    ;;
esac
case "$checkpoint" in
  *'## Plan checkpoint'*'Plan body'*) ;;
  *)
    printf 'rendered checkpoint missing plan body\n%s\n' "$checkpoint" >&2
    exit 1
    ;;
esac

if gleam run -m grkr/progress/cli -- marker not-a-stage issue-71-progress-cli >/tmp/grkr-progress-cli-invalid.$$ 2>&1; then
  printf 'invalid stage unexpectedly succeeded\n' >&2
  rm -f /tmp/grkr-progress-cli-invalid.$$
  exit 1
fi
if ! grep -q 'progress cli error:' /tmp/grkr-progress-cli-invalid.$$; then
  printf 'invalid stage output missing error prefix\n' >&2
  rm -f /tmp/grkr-progress-cli-invalid.$$
  exit 1
fi
rm -f /tmp/grkr-progress-cli-invalid.$$

printf 'grkr progress cli test passed\n'
