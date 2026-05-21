#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$SCRIPT_DIR/doctor.sh"
. "$SCRIPT_DIR/grkr-task-slug.sh"

doctor_init

if [ -f "$GRKR_CONFIG_FILE" ]; then
  . "$GRKR_CONFIG_FILE"
fi

# Ensure we run from the Gleam project root (supports GRKR_GLEAM_PROJECT_ROOT override for tests)
PROJECT_ROOT=${GRKR_GLEAM_PROJECT_ROOT:-$(dirname "$SCRIPT_DIR")}
cd "$PROJECT_ROOT"

# Gleam + node are now required (github_picker path uses them; linear too)
if ! command -v gleam >/dev/null 2>&1; then
  echo "❌ gleam is required but not installed or not in PATH" >&2
  exit 1
fi
if ! command -v node >/dev/null 2>&1; then
  echo "❌ node is required but not installed or not in PATH" >&2
  exit 1
fi

# Linear provider: delegate entirely to its Gleam module (keeps its own fetch + logic)
ISSUE_PROVIDER=${GRKR_ISSUE_PROVIDER:-github}
if [ "$ISSUE_PROVIDER" = "linear" ]; then
  exec gleam run -m grkr/issue_provider/main
fi

# GitHub path (default): thin wrapper - delegate EVERYTHING (config, gh fetch with pagination,
# decode, selector, emit) to Gleam github_picker/main. Supports GITHUB_FIXTURE_PATH env for
# tests. Preserves exact emitted KEY=val interface for supervisor/robot-main.
#
# The heavy GraphQL builders + fetch + jq logic moved to Gleam (query.gleam + client.gleam + gh_exec).
# Shell stays small and explicit per AGENTS.md (<100 lines).
exec gleam run -m grkr/github_picker/main
