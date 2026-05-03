#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [ "${GRKR_LINEAR_E2E:-}" != "1" ]; then
  echo "Linear live e2e skipped: set GRKR_LINEAR_E2E=1 to run against Linear."
  exit 0
fi

if ! command -v gleam >/dev/null 2>&1; then
  echo "Error: gleam is not installed or not in PATH" >&2
  exit 1
fi

cd "$PROJECT_ROOT"

echo "Running opt-in Linear live e2e via Gleam..."
echo "Credentials are loaded only from GRKR_LINEAR_SECRET_PATH or ~/.linear/secret.txt and are never printed."
echo "A derived OAuth/access token must be supplied via GRKR_LINEAR_ACCESS_TOKEN after completing the Linear app install/token exchange."

gleam run -m grkr/linear/e2e_main
