# grkr

AI-powered CLI that reads a GitHub issue and uses Codex to implement the changes.

Current implementation status: the checkpointed issue flow through research, plan, implementation, test, and completion is implemented, along with the supervisor skeleton, main-branch sync, and project issue selection. PR conflict automation, `@:robot:` comment handling, refusal flow, and full worktree isolation are still planned follow-up work.

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
8. Before it checks out or creates `issue-N`, the issue helper moves the configured project item to the configured in-progress status when it can resolve that project item; project status option matching is case-insensitive and whitespace-normalized
9. The issue helper reuses branch `issue-N` when it already exists locally or remotely, otherwise creates it
10. Codex output is stored in `.grkr/tasks/<issue-slug>/implementation.log`; if the staged diff would leave any file over the 1000-line limit, `grkr` immediately runs one Codex refactor pass before moving on
11. After the implementation is publishable, `grkr` runs the configured build and test commands, writes `.grkr/tasks/<issue-slug>/test.md`, and posts the test checkpoint back to the issue
12. `grkr` then commits, pushes, opens a PR that links the issue, records the branch and PR URLs in `progress.json`, and marks the issue workflow complete
13. On successful completion, the issue helper posts a short completion summary, optionally moves the project item to `Done`, and mirrors the local run log back to the issue inside a collapsed details block
14. If the generated PR description is too large for GitHub, `grkr` replaces it with a compact summary before creating the PR
15. In `grkr --project <id>` mode, a failed issue run is logged and the watcher continues with later issues and later loop iterations

## Install Notes

- `npm install -g .` installs the local `bin/grkr` launcher into your PATH.
- `robot-main.sh` uses `MAIN_BRANCH` and `LOOP_INTERVAL_SECS` from `.grkr/config.sh`; `grkr init <id>` now writes both defaults into the generated config.
- `worker-sync-main.sh` is the phase-1 supervisor worker; it always returns the main checkout to the configured `MAIN_BRANCH` before later phases run.
- `worker-pick-issue.sh` is the phase-4 selector; it emits shell-safe key/value output for the next Todo issue candidate, including `JOB_KEY` and `TASK_SLUG`.
- `grkr init <id>` also writes `IN_PROGRESS_VALUE="In Progress"` so issue execution can move a project item out of Todo before branching; status option lookup tolerates casing differences such as `In progress`.
- `grkr init <id>` also writes `DONE_VALUE="Done"` plus default `TEST_COMMAND` and `BUILD_COMMAND` entries so the test stage has explicit verification commands.
- `npm test` refreshes the spec index from the split files under `spec/parts/` and runs the mocked shell tests without needing GitHub access.
- `grkr --issue <id>` automatically shrinks oversized Codex-generated PR bodies so `gh pr create` stays under GitHub's 65536-character body limit.
- `grkr --issue <id>` includes the per-file 1000-line rule in the Codex prompt and will trigger one immediate Codex refactor pass when staged changes still violate that limit.
- `grkr --project <id>` treats per-issue failures as recoverable so the long-running watcher does not exit after one bad issue.
- `grkr --issue <id>` warns when the working directory is dirty, then continues so intentionally staged or unstaged local changes can be included.
- `grkr --issue <id>` now keeps per-issue checkpoint state under `.grkr/tasks/<issue-slug>/`, including `research.md`, `plan.md`, `implementation.log`, `test.md`, and `progress.json`.
- The issue helper posts the research, plan, and test checkpoint files as issue comments and reuses them on rerun when matching checkpoint markers already exist.
- On success, `progress.json` is updated to `complete` and records the branch URL plus PR URL for the finished issue workflow.
- `grkr --issue <id>` mirrors its launcher log to the GitHub issue as a collapsed details block so the thread stays readable by default.
- Copy `.grkr/config.sh.example` to `.grkr/config.sh` and edit the values for your repo if you want to manage config manually.
- `grkr init <id>` will create `.grkr/config.sh` for the current `origin` remote and project id you pass in.

## Requirements

- GitHub CLI (`gh`) installed and authenticated (`gh auth login`)
- Codex CLI available in PATH
- `jq` for JSON parsing
- Node.js (for global install)
- Git repository with an `origin` remote configured
