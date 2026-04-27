#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(dirname "$SCRIPT_DIR")

if [ ! -f "$PROJECT_ROOT/gleam.toml" ]; then
    echo "Error: gleam.toml not found at $PROJECT_ROOT" >&2
    exit 1
fi

cd "$PROJECT_ROOT"

if [ -f "$PROJECT_ROOT/.grkr/config.sh" ]; then
    set -a
    # shellcheck source=/dev/null
    source "$PROJECT_ROOT/.grkr/config.sh"
    set +a
fi

PR_NUMBER="${1:-}"

if [ -z "$PR_NUMBER" ]; then
    echo "Usage: worker-resolve-pr.sh <pr_number>" >&2
    exit 1
fi

if ! [[ "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "Error: PR number must be a positive integer" >&2
    exit 1
fi

if ! command -v gleam &> /dev/null; then
    echo "Error: gleam is not installed or not in PATH" >&2
    exit 1
fi

if ! command -v node &> /dev/null; then
    echo "Error: node is not installed or not in PATH" >&2
    exit 1
fi

exec gleam run -m grkr/resolve_pr/main -- "$PR_NUMBER"
