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

linear_state=$(LINEAR_STATE_RESEARCH='Planning Review' gleam run -m grkr/progress/cli -- linear-state research)
if [ "$linear_state" != "Planning Review" ]; then
  printf 'unexpected Linear state: %s\n' "$linear_state" >&2
  exit 1
fi

linear_mutation=$(gleam run -m grkr/progress/cli -- linear-comment-mutation LIN-71 'Linear checkpoint body' plan issue-71-progress-cli)
case "$linear_mutation" in
  *'commentCreate'*'grkr:checkpoint'*'Linear checkpoint body'*'grkr-checkpoint-plan-issue-71-progress-cli'*) ;;
  *)
    printf 'Linear comment mutation output missing expected planning details\n%s\n' "$linear_mutation" >&2
    exit 1
    ;;
esac

linear_debug=$(gleam run -m grkr/progress/cli -- mutation-debug LIN-71 'secret=do-not-print' plan issue-71-progress-cli)
case "$linear_debug" in
  *'[redacted]'*) ;;
  *)
    printf 'mutation debug output missing redaction marker\n%s\n' "$linear_debug" >&2
    exit 1
    ;;
esac
case "$linear_debug" in
  *'do-not-print'*)
    printf 'mutation debug output leaked variables\n%s\n' "$linear_debug" >&2
    exit 1
    ;;
esac

token_status=$(env -u GRKR_LINEAR_ACCESS_TOKEN gleam run -m grkr/progress/cli -- check-token)
if [ "$token_status" != "Token unavailable" ]; then
  printf 'unexpected Linear token status: %s\n' "$token_status" >&2
  exit 1
fi

completion=$(gleam run -m grkr/progress/cli -- render-github-completion-summary 77 "Test title" "https://ex/tree/b" "https://ex/pr/9")
case "$completion" in
  *'## Completion summary'*'Issue #77: Test title'*'Recommendation: ready'*'Branch: https://ex/tree/b'*'PR: https://ex/pr/9'*) ;;
  *)
    printf 'render-github-completion-summary missing expected content\n%s\n' "$completion" >&2
    exit 1
    ;;
esac

printf 'grkr progress cli test passed\n'
