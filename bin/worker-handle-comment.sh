#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$SCRIPT_DIR/doctor.sh"

doctor_init

if [ -f "$GRKR_CONFIG_FILE" ]; then
  . "$GRKR_CONFIG_FILE"
fi

# Thin delegation wrapper for Gleam workflow/handle_comment (GitHub-only v2) per t_944f1214.
# Replaces full 296 LOC bash (now in .legacy-v1) with thin ~30 LOC per AGENTS.md + spec/parts/08 + 15.
# Preserves exact interface for supervisor scheduler (spawn with <comment_id>), bin tests, always exit 0 best-effort.
# Full logic (fetch context via gh, eyes/rocket reactions, worktree prep per spec/12 for issue vs PR, codex prompt build+dispatch+parse CLASS/REPLY/CHANGES, result comment, optional commit/push, cleanup) now in Gleam.
# Supports GRKR_GLEAM_PROJECT_ROOT override for tests.
GRKR_DIR="${GRKR_ROOT:-$PWD}/.grkr"
export GRKR_ROOT GRKR_CONFIG_FILE MAIN_BRANCH=${MAIN_BRANCH:-main} REPO=${REPO:-stepango/grkr}

PROJECT_ROOT=${GRKR_GLEAM_PROJECT_ROOT:-$(dirname "$SCRIPT_DIR")}
cd "$PROJECT_ROOT" || exit 1

if ! command -v gleam >/dev/null 2>&1; then
  echo "❌ gleam is required but not installed or not in PATH" >&2
  exit 1
fi

exec gleam run -m grkr/workflow/handle_comment -- "$@"
