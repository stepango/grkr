# grkr

AI-powered CLI that reads a GitHub issue and uses Codex to implement the changes.

Current implementation status: the checkpointed issue flow, supervisor skeleton, main-branch sync, and project issue selection are implemented. PR conflict automation, `@:robot:` comment handling, refusal flow, test checkpoints, and full worktree isolation are still planned follow-up work.

## Usage

```bash
# Install globally
npm install -g .

# Create the config for this repo and project
grkr init 42

# Run the long-lived supervisor loop
robot-main.sh

# Run for an issue
grkr --issue 1

# Run the smoke test
npm test
```

## How it works

1. `robot-main.sh` creates the `.grkr` runtime layout, validates prerequisites, and runs the ordered supervisor phases on the configured interval
2. The first supervisor phase delegates to `worker-sync-main.sh`, which takes `.grkr/locks/main.lock`, fetches `origin/$MAIN_BRANCH` with pruning, checks out the configured main branch, and hard-resets the supervisor checkout to `origin/$MAIN_BRANCH`
3. The supervisor writes structured loop logs to `.grkr/logs/main.log` and `.grkr/logs/loop.log`, keeps per-job logs under `.grkr/logs/jobs/`, recovers stale jobs from `.grkr/state/active_jobs.json`, and keeps later phases running when an earlier phase fails
4. Phase 4 delegates to `worker-pick-issue.sh`, which reads the configured GitHub Project live, filters Todo issues assigned to the authenticated bot in the configured repo, excludes active issue jobs, orders candidates by priority and age, and emits the stable `issue:<n>:execution` job key plus task slug for the top match
5. `grkr --issue <n>` remains the focused single-issue helper that fetches issue details using `gh issue view`
6. Before it starts implementation, the issue helper creates `.grkr/tasks/<issue-slug>/`, writes `research.md`, `plan.md`, and `progress.json`, and posts the research and plan checkpoints back to the issue
7. If matching checkpoint comments already exist, the issue helper reuses those comments and resumes without reposting duplicate research or plan checkpoints
8. Before it checks out or creates `issue-N`, the issue helper moves the configured project item to `In Progress` when it can resolve that project item
9. The issue helper reuses branch `issue-N` when it already exists locally or remotely, otherwise creates it
10. After Codex finishes implementing, `grkr` posts the local run log back to the issue inside a collapsed details block
11. `grkr` then commits, pushes, and opens a PR that links the issue
12. If the generated PR description is too large for GitHub, `grkr` replaces it with a compact summary before creating the PR

## Install Notes

- `npm install -g .` installs the local `bin/grkr` launcher into your PATH.
- `robot-main.sh` uses `MAIN_BRANCH` and `LOOP_INTERVAL_SECS` from `.grkr/config.sh`; `grkr init <id>` now writes both defaults into the generated config.
- `worker-sync-main.sh` is the phase-1 supervisor worker; it always returns the main checkout to the configured `MAIN_BRANCH` before later phases run.
- `worker-pick-issue.sh` is the phase-4 selector; it emits shell-safe key/value output for the next Todo issue candidate, including `JOB_KEY` and `TASK_SLUG`.
- `grkr init <id>` also writes `IN_PROGRESS_VALUE="In Progress"` so issue execution can move a project item out of Todo before branching.
- `npm test` refreshes the spec index from the split files under `spec/parts/` and runs the mocked shell tests without needing GitHub access.
- `grkr --issue <id>` automatically shrinks oversized Codex-generated PR bodies so `gh pr create` stays under GitHub's 65536-character body limit.
- `grkr --issue <id>` warns when the working directory is dirty, then continues so intentionally staged or unstaged local changes can be included.
- `grkr --issue <id>` now keeps per-issue checkpoint state under `.grkr/tasks/<issue-slug>/`, including `research.md`, `plan.md`, and `progress.json`.
- The issue helper posts the research and plan checkpoint files as issue comments and reuses them on rerun when matching checkpoint markers already exist.
- `grkr --issue <id>` mirrors its launcher log to the GitHub issue as a collapsed details block so the thread stays readable by default.
- Copy `.grkr/config.sh.example` to `.grkr/config.sh` and edit the values for your repo if you want to manage config manually.
- `grkr init <id>` will create `.grkr/config.sh` for the current `origin` remote and project id you pass in.

## Requirements

- GitHub CLI (`gh`) installed and authenticated (`gh auth login`)
- Codex CLI available in PATH
- `jq` for JSON parsing
- Node.js (for global install)
- Git repository with an `origin` remote configured
