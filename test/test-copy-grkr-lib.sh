#!/bin/bash
# Copy bin/lib/*.sh into a test fixture directory (grkr sources these via SCRIPT_DIR/lib/).
# Includes linear_issue_stages.sh facade + linear_issue_stages_*.sh siblings (refusal, research_plan, implement, test, publish).
# Also github_issue.sh facade + github_issue_stages_*.sh siblings (research_plan + test + publish now; implement later).
set -euo pipefail
dest=${1:?usage: test-copy-grkr-lib.sh DEST_DIR}
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mkdir -p "$dest/lib"
cp "$repo_root/bin/lib/"*.sh "$dest/lib/"
chmod +x "$dest/lib/"*.sh