#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$SCRIPT_DIR/doctor.sh"

usage() {
  printf '%s\n' \
    "Usage: worker-resolve-pr.sh <pr_number>" \
    "" \
    "Resolve PR conflicts using the Gleam workflow (GitHub-only v2)." \
    "Use --help, -h, or help to show this message."
}

case "${1:-}" in
  --help|-h|help)
    usage
    exit 0
    ;;
esac

doctor_init

if [ -f "$GRKR_CONFIG_FILE" ]; then
  . "$GRKR_CONFIG_FILE"
fi

# Thin delegation wrapper for Gleam resolve_pr/main (full PR conflict logic, GitHub-only v2) per t_49932a05 + spec/parts/14 + 39 item 11 (#20).
# Replaces prior thin calling workflow/resolve_pr skeleton (t_f4d7a801) with direct call to full main (~426 LOC impl of run: fetch, worktree, rebase/merge, codex, validate, push, cleanup).
# Shell does doctor + config + cd + gleam/node checks + exec (keeps ~39 LOC explicit per AGENTS.md + recent thins).
# Supports GRKR_GLEAM_PROJECT_ROOT override for tests. Preserves exact <pr_number> contract, exit codes, env (CONFLICT_STRATEGY, TEST_COMMAND, BUILD_COMMAND).
# Supervisor scan_pr_conflicts still uses resolve_pr/github for detection (unchanged).
# workflow/resolve_pr.gleam skeleton left for reference (no longer entry point).

GRKR_DIR="${GRKR_ROOT:-$PWD}/.grkr"
export GRKR_ROOT GRKR_CONFIG_FILE MAIN_BRANCH=${MAIN_BRANCH:-main} REPO=${REPO:-stepango/grkr}
export CONFLICT_STRATEGY=${CONFLICT_STRATEGY:-merge}
export BUILD_COMMAND=${BUILD_COMMAND:-} TEST_COMMAND=${TEST_COMMAND:-"npm test"}
export GRKR_GLEAM_PROJECT_ROOT

PROJECT_ROOT=${GRKR_GLEAM_PROJECT_ROOT:-$(dirname "$SCRIPT_DIR")}
cd "$PROJECT_ROOT" || exit 1

if ! command -v gleam >/dev/null 2>&1; then
  echo "❌ gleam is required but not installed or not in PATH" >&2
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  echo "❌ node is required but not installed or not in PATH" >&2
  exit 1
fi

exec gleam run -m grkr/resolve_pr/main -- "$@"
