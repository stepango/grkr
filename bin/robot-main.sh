#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$SCRIPT_DIR/doctor.sh"

doctor_init

if [ -f "$GRKR_CONFIG_FILE" ]; then
  . "$GRKR_CONFIG_FILE"
fi

# Export all config + runtime vars for the child Gleam process (ffi.get_env)
# (mirrors load_runtime_config defaults + .grkr/config.sh)
export REPO=${REPO:-unknown/unknown}
export MAIN_BRANCH=${MAIN_BRANCH:-main}
export LOOP_INTERVAL_SECS=${LOOP_INTERVAL_SECS:-20}
export GRKR_ROOT=${GRKR_ROOT:-$PWD}
export GRKR_CONFIG_FILE
export PROJECT_OWNER=${PROJECT_OWNER:-}
export PROJECT_NUMBER=${PROJECT_NUMBER:-0}
export STATUS_FIELD_NAME=${STATUS_FIELD_NAME:-Status}
export TODO_VALUE=${TODO_VALUE:-Todo}
export BACKLOG_VALUE=${BACKLOG_VALUE:-Backlog}
export PRIORITY_FIELD_NAME=${PRIORITY_FIELD_NAME:-Priority}

# Test / control hooks (passed via env to this script or config)
export GRKR_MAX_TICKS GRKR_FAIL_PHASES GRKR_GLEAM_PROJECT_ROOT

# Run validation (populates VALIDATION_OK; prints ✅/❌ like before; ensures .grkr dir)
# doctor_validate also re-inits and checks tools/gh/codex/config/remote
doctor_validate
validate_status=$?
if [ "$validate_status" -eq 0 ]; then
  VALIDATION_OK=1
else
  VALIDATION_OK=0
fi
export VALIDATION_OK

# Support GRKR_GLEAM_PROJECT_ROOT override (used by tests to point at source tree)
PROJECT_ROOT=${GRKR_GLEAM_PROJECT_ROOT:-$(dirname "$SCRIPT_DIR")}
cd "$PROJECT_ROOT" || exit 1

# Gleam + node are required for the JS-targeted supervisor
if ! command -v gleam >/dev/null 2>&1; then
  echo "❌ gleam is required but not installed or not in PATH" >&2
  exit 1
fi
if ! command -v node >/dev/null 2>&1; then
  echo "❌ node is required but not installed or not in PATH" >&2
  exit 1
fi

# Thin delegation to Gleam supervisor (v2 GitHub-only)
# All loop logic, recovery, phases, logging, state now in src/grkr/supervisor/
exec gleam run -m grkr/supervisor/main "$@"
