#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$SCRIPT_DIR/doctor.sh"

doctor_init

if [ -f "$GRKR_CONFIG_FILE" ]; then
  set -a
  # shellcheck source=/dev/null
  . "$GRKR_CONFIG_FILE"
  set +a
fi

# Thin wrapper: doctor/config (set -a for exports) + cd + exec gleam refusal/cli (GitHub v2)
# Per AGENTS.md + spec/parts/08-worker-scripts.md + 23-refusal-flow.md + 24-implementation-refused.md + t_b610c14c
# All logic (fetch, task_slug, checkpoint/refusal.md, progress.json, optional Backlog move, exact REFUSAL_* emits + exit 0/1) now in Gleam cli+flow+checkpoint+project.
# Legacy grkr-task-slug.sh + grkr-project-status.sh sources removed (Gleam owned).
# Supports GRKR_GLEAM_PROJECT_ROOT override for tests. ~45 LOC core, explicit per AGENTS.
GRKR_DIR="${GRKR_ROOT:-$PWD}/.grkr"
export TASKS_DIR="${TASKS_DIR:-$GRKR_DIR/tasks}" GITHUB_REPOSITORY="${REPO:-}" REPO
export MAIN_BRANCH=${MAIN_BRANCH:-main} GRKR_ROOT GRKR_CONFIG_FILE
export PROJECT_OWNER=${PROJECT_OWNER:-} PROJECT_NUMBER=${PROJECT_NUMBER:-0}
export STATUS_FIELD_NAME=${STATUS_FIELD_NAME:-Status} TODO_VALUE=${TODO_VALUE:-Todo}
export IN_PROGRESS_VALUE=${IN_PROGRESS_VALUE:-In Progress} DONE_VALUE=${DONE_VALUE:-Done}
export BACKLOG_VALUE=${BACKLOG_VALUE:-Backlog} PRIORITY_FIELD_NAME=${PRIORITY_FIELD_NAME:-Priority}
export ENABLE_PROJECT_STATUS_UPDATES=${ENABLE_PROJECT_STATUS_UPDATES:-true}
export REFUSAL_REQUIRES_BACKLOG_MOVE=${REFUSAL_REQUIRES_BACKLOG_MOVE:-true}
export GRKR_GLEAM_PROJECT_ROOT

# Ensure we run from Gleam project root (supports override for tests)
PROJECT_ROOT=${GRKR_GLEAM_PROJECT_ROOT:-$(dirname "$SCRIPT_DIR")}
cd "$PROJECT_ROOT" || exit 1

if ! command -v gleam >/dev/null 2>&1 || ! command -v node >/dev/null 2>&1; then
  echo "❌ gleam+node required" >&2; exit 1
fi

exec gleam run --no-print-progress -m grkr/refusal/cli -- "$@"
