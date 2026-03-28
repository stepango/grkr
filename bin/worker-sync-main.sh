#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$SCRIPT_DIR/doctor.sh"

doctor_init

if [ -f "$GRKR_CONFIG_FILE" ]; then
  . "$GRKR_CONFIG_FILE"
fi

MAIN_BRANCH=${MAIN_BRANCH:-main}
GRKR_DIR="$GRKR_ROOT/.grkr"
LOCKS_DIR="$GRKR_DIR/locks"

mkdir -p "$LOCKS_DIR"

(
  flock -n 9 || exit 75
  git fetch origin "$MAIN_BRANCH" --prune
  git checkout "$MAIN_BRANCH"
  git reset --hard "origin/$MAIN_BRANCH"
) 9>"$LOCKS_DIR/main.lock"
