#!/bin/bash
# Full npm test chain. Unset GRKR_* / GLEAM_ENV inherited from kanban/cron workers
# so isolated tmpdir fixtures use mocked git roots instead of the live repo, and
# suite order cannot leak provider/fail-phase hooks into later scripts.
set -euo pipefail

unset GLEAM_ENV 2>/dev/null || true
unset GRKR_ROOT GRKR_CONFIG_FILE GRKR_ACTIVE_JOBS_PATH GRKR_MAX_TICKS \
  GRKR_FAIL_PHASES GRKR_GLEAM_PROJECT_ROOT GRKR_ISSUE_PROVIDER \
  GITHUB_FIXTURE_PATH BOT_LOGIN 2>/dev/null || true

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

bash scripts/sync-spec.sh
bash test/grkr-init.sh
bash test/grkr-installed-layout.sh
bash test/grkr-smoke.sh
bash test/grkr-checkpoint-resume.sh
bash test/grkr-branch-exists.sh
bash test/grkr-refusal.sh
bash test/grkr-implementation-to-refusal.sh
bash test/grkr-progress-cli.sh
bash test/grkr-linear-issue-mvp.sh
bash test/grkr-linear-refuse-progress.sh
bash test/grkr-linear-issue-implement.sh
bash test/grkr-line-limit.sh
bash test/grkr-pr-body-limit.sh
bash test/grkr-dirty-worktree-warning.sh
bash test/worker-sync-main.sh
bash test/worker-pick-issue.sh
bash test/worker-help.sh
bash test/robot-main-supervisor.sh
bash test/robot-main-schedules-issue.sh
bash test/robot-main-phase-failure.sh
bash test/worker-resolve-pr.sh