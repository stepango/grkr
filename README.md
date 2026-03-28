# grkr

AI-powered CLI that reads a GitHub issue and uses Codex to implement the changes.

Current implementation status: the checkpointed issue flow now runs research, plan, a decision gate, isolated implementation in a dedicated issue worktree, test, and completion, along with the supervisor skeleton, main-branch sync, and project issue selection. PR conflict automation, `@:robot:` comment handling, refusal flow, and the remaining worker worktree flows are still planned follow-up work.

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
6. The issue helper creates or reuses `.grkr/tasks/<issue-slug>/`, writes `research.md`, `plan.md`, and `progress.json`, and posts the research and plan checkpoints back to the issue
7. If matching checkpoint comments already exist, the issue helper reuses those comments and resumes without reposting duplicate research or plan checkpoints
8. The issue helper also creates or reuses `.grkr/worktrees/<issue-slug>/` so issue execution happens in a dedicated git worktree instead of the supervisor checkout
9. After research and plan, a separate Codex decision gate runs in the issue worktree and implementation continues only when that gate returns `proceed`
10. When the decision is `proceed`, the issue helper moves the configured project item to the configured in-progress status when it can resolve that project item; project status option matching is case-insensitive and whitespace-normalized
11. Codex implementation output is anchored at `.grkr/tasks/<issue-slug>/implementation.log`; when the transcript grows too large, `grkr` keeps that file as a manifest and shards the full log into `.grkr/tasks/<issue-slug>/codex/implementation.log.parts/` so every tracked file stays within the 1000-line limit
12. The configured build and test commands run in the same issue worktree, `grkr` writes `.grkr/tasks/<issue-slug>/test.md`, and posts the test checkpoint back to the issue
13. `grkr` stages only the relevant non-`.grkr` file changes from the issue worktree, commits, pushes the issue branch, creates or updates a PR that links the issue, records the branch and PR URLs in `progress.json`, and marks the issue workflow complete
14. On successful completion, the issue helper posts a short completion summary, optionally moves the project item to `Done`, and mirrors the local run log back to the issue inside a collapsed details block
15. If the generated PR description is too large for GitHub, `grkr` replaces it with a compact summary before creating the PR
16. In `grkr --project <id>` mode, a failed issue run is logged and the watcher continues with later issues and later loop iterations

## Install Notes

- `npm install -g .` installs the local `bin/grkr` launcher into your PATH.
- The installed `grkr` launcher resolves its real script path before loading helper files, so symlinked installs such as npm's global bin layout do not need `grkr-templates.sh` copied into the top-level bin directory.
- `robot-main.sh` uses `MAIN_BRANCH` and `LOOP_INTERVAL_SECS` from `.grkr/config.sh`; `grkr init <id>` now writes both defaults into the generated config.
- `worker-sync-main.sh` is the phase-1 supervisor worker; it always returns the main checkout to the configured `MAIN_BRANCH` before later phases run.
- `worker-pick-issue.sh` is the phase-4 selector; it emits shell-safe key/value output for the next Todo issue candidate, including `JOB_KEY` and `TASK_SLUG`.
- `grkr init <id>` also writes `IN_PROGRESS_VALUE="In Progress"` so issue execution can move a project item out of Todo before branching; status option lookup tolerates casing differences such as `In progress`.
- `grkr init <id>` also writes `DONE_VALUE="Done"` plus default `TEST_COMMAND` and `BUILD_COMMAND` entries so the test stage has explicit verification commands.
- `npm test` refreshes the spec index from the split files under `spec/parts/` and runs the mocked shell tests without needing GitHub access.
- `grkr --issue <id>` automatically shrinks oversized Codex-generated PR bodies so `gh pr create` stays under GitHub's 65536-character body limit.
- `grkr --issue <id>` includes the per-file 1000-line rule in the Codex prompt and will trigger one immediate Codex refactor pass when staged changes still violate that limit.
- `grkr --issue <id>` now runs issue execution in `.grkr/worktrees/<issue-slug>/`, uses a dedicated Codex decision gate before implementation, and only proceeds when that gate returns `proceed`.
- `grkr --issue <id>` stages only relevant non-`.grkr` files from the issue worktree and updates an existing branch PR when one is already open.
- `grkr --project <id>` treats per-issue failures as recoverable so the long-running watcher does not exit after one bad issue.
- `grkr --issue <id>` warns when the working directory is dirty, then continues so intentionally staged or unstaged local changes can be included.
- `grkr --issue <id>` now keeps per-issue checkpoint state under `.grkr/tasks/<issue-slug>/`, including `research.md`, `plan.md`, `implementation.log`, `test.md`, and `progress.json`; large implementation transcripts are sharded into `codex/implementation.log.parts/` with `implementation.log` left as the stable entrypoint.
- The issue helper posts the research, plan, and test checkpoint files as issue comments and reuses them on rerun when matching checkpoint markers already exist.
- On success, `progress.json` is updated to `complete` and records the branch URL plus PR URL for the finished issue workflow.
- `grkr --issue <id>` mirrors its launcher log to the GitHub issue as a collapsed details block so the thread stays readable by default.
- Copy `.grkr/config.sh.example` to `.grkr/config.sh` and edit the values for your repo if you want to manage config manually.
- `grkr init <id>` will create `.grkr/config.sh` for the current `origin` remote and project id you pass in.
- `.grkr/tasks/` is local runtime state and ignored by git; `.grkr/config.sh` and `.grkr/config.sh.example` stay tracked.

## Requirements

- GitHub CLI (`gh`) installed and authenticated (`gh auth login`)
- Codex CLI available in PATH
- `jq` for JSON parsing
- Node.js (for global install)
- Git repository with an `origin` remote configured
