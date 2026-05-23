#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$SCRIPT_DIR/doctor.sh"
. "$SCRIPT_DIR/grkr-task-slug.sh"
. "$SCRIPT_DIR/grkr-project-status.sh"

doctor_init

if [ -f "$GRKR_CONFIG_FILE" ]; then
  . "$GRKR_CONFIG_FILE"
fi

# Export runtime config + paths for Gleam refusal (config.load + env FFI)
# doctor_init sets GRKR_ROOT + GRKR_CONFIG_FILE
GRKR_DIR="${GRKR_ROOT:-$PWD}/.grkr"
export TASKS_DIR="${TASKS_DIR:-$GRKR_DIR/tasks}"
export GITHUB_REPOSITORY="${REPO:-}"
export REPO
export MAIN_BRANCH=${MAIN_BRANCH:-main}
export GRKR_ROOT
export GRKR_CONFIG_FILE
export PROJECT_OWNER=${PROJECT_OWNER:-}
export PROJECT_NUMBER=${PROJECT_NUMBER:-0}
export STATUS_FIELD_NAME=${STATUS_FIELD_NAME:-Status}
export TODO_VALUE=${TODO_VALUE:-Todo}
export IN_PROGRESS_VALUE=${IN_PROGRESS_VALUE:-In Progress}
export DONE_VALUE=${DONE_VALUE:-Done}
export BACKLOG_VALUE=${BACKLOG_VALUE:-Backlog}
export PRIORITY_FIELD_NAME=${PRIORITY_FIELD_NAME:-Priority}
export ENABLE_PROJECT_STATUS_UPDATES=${ENABLE_PROJECT_STATUS_UPDATES:-true}
export REFUSAL_REQUIRES_BACKLOG_MOVE=${REFUSAL_REQUIRES_BACKLOG_MOVE:-true}

# Test/control hooks (passed to Gleam via env)
export GRKR_GLEAM_PROJECT_ROOT

# Ensure we run from Gleam project root (supports override for tests)
PROJECT_ROOT=${GRKR_GLEAM_PROJECT_ROOT:-$(dirname "$SCRIPT_DIR")}
cd "$PROJECT_ROOT" || exit 1

# Gleam + node required for JS-targeted refusal (GitHub-only v2)
if ! command -v gleam >/dev/null 2>&1; then
  echo "❌ gleam is required but not installed or not in PATH" >&2
  exit 1
fi
if ! command -v node >/dev/null 2>&1; then
  echo "❌ node is required but not installed or not in PATH" >&2
  exit 1
fi

# Thin delegation to Gleam refusal/cli (v2 GitHub-only)
# - fetch, task_slug, ensure checkpoint (refusal.md + gh comment idempotent), progress.json update, optional project move to Backlog
# - exact same emit interface (REFUSAL_PROCESSED=1 + ISSUE/TASK_SLUG/CLASS/COMMENT_ID/PROGRESS_FILE) + exit codes
# - status messages now emitted from cli (to stderr) for UX + test compat
# Replaces 500+ lines of duplicated bash logic per AGENTS.md / spec
exec gleam run -m grkr/refusal/cli -- "$@"
