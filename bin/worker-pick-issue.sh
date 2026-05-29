#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$SCRIPT_DIR/doctor.sh"
. "$SCRIPT_DIR/grkr-task-slug.sh"

doctor_init

if [ -f "$GRKR_CONFIG_FILE" ]; then
  . "$GRKR_CONFIG_FILE"
fi

# Thin wrapper per t_04af5d5f + AGENTS.md + spec/parts/08-worker-scripts.md + 16-phase-4...
# doctor + config + mkdir + cd + exec gleam .../main "$@"
GRKR_DIR="${GRKR_ROOT:-$PWD}/.grkr"
export TASKS_DIR="${TASKS_DIR:-$GRKR_DIR/tasks}"
mkdir -p "$TASKS_DIR" "$GRKR_DIR/state" "$GRKR_DIR/locks" 2>/dev/null || true

# Ensure we run from the Gleam project root (supports GRKR_GLEAM_PROJECT_ROOT override for tests)
PROJECT_ROOT=${GRKR_GLEAM_PROJECT_ROOT:-$(dirname "$SCRIPT_DIR")}
cd "$PROJECT_ROOT" || exit 1

# Gleam + node are now required (github_picker path uses them; linear too)
if ! command -v gleam >/dev/null 2>&1; then
  echo "❌ gleam is required but not installed or not in PATH" >&2
  exit 1
fi
if ! command -v node >/dev/null 2>&1; then
  echo "❌ node is required but not installed or not in PATH" >&2
  exit 1
fi

# Linear provider: delegate entirely to its Gleam module (keeps its own fetch + logic) - untouched
ISSUE_PROVIDER=${GRKR_ISSUE_PROVIDER:-github}
if [ "$ISSUE_PROVIDER" = "linear" ]; then
  exec gleam run -m grkr/issue_provider/main "$@"
fi

# GitHub path (default): thin wrapper - delegate EVERYTHING (config, gh fetch with pagination,
# decode, selector using priority, emit SELECTED/ISSUE_*/JOB_KEY/TASK_SLUG/PROJECT_ITEM_ID etc)
# to Gleam github_picker/main. Supports GITHUB_FIXTURE_PATH env for tests/fixtures.
# Preserves exact emitted interface for supervisor, bin/grkr, tests.
#
# Shell ~40 LOC explicit per AGENTS.md, no logic dupe. GitHub-only v2 slice.
exec gleam run -m grkr/github_picker/main "$@"
