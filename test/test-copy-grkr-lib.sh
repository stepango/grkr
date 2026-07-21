#!/bin/bash
# Copy bin/lib/*.sh into a test fixture directory (grkr sources these via SCRIPT_DIR/lib/).
# Includes linear_issue_stages.sh facade + linear_issue_stages_*.sh siblings (refusal, test, publish, etc.).
set -euo pipefail
dest=${1:?usage: test-copy-grkr-lib.sh DEST_DIR}
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mkdir -p "$dest/lib"
cp "$repo_root/bin/lib/"*.sh "$dest/lib/"
chmod +x "$dest/lib/"*.sh