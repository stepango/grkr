# grkr

AI-powered CLI that reads a GitHub issue and uses Codex to implement the changes.

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
4. `grkr --issue <n>` remains the focused single-issue helper that fetches issue details using `gh issue view`
5. Before it checks out or creates `issue-N`, the issue helper moves the configured project item to `In Progress` when it can resolve that project item
6. The issue helper reuses branch `issue-N` when it already exists locally or remotely, otherwise creates it
7. After Codex finishes implementing, `grkr` posts the local run log back to the issue inside a collapsed details block
8. `grkr` then commits, pushes, and opens a PR that links the issue
9. If the generated PR description is too large for GitHub, `grkr` replaces it with a compact summary before creating the PR

## Install Notes

- `npm install -g .` installs the local `bin/grkr` launcher into your PATH.
- `robot-main.sh` uses `MAIN_BRANCH` and `LOOP_INTERVAL_SECS` from `.grkr/config.sh`; `grkr init <id>` now writes both defaults into the generated config.
- `worker-sync-main.sh` is the phase-1 supervisor worker; it always returns the main checkout to the configured `MAIN_BRANCH` before later phases run.
- `grkr init <id>` also writes `IN_PROGRESS_VALUE="In Progress"` so issue execution can move a project item out of Todo before branching.
- `npm test` refreshes the spec index from the split files under `spec/parts/` and runs the mocked shell tests without needing GitHub access.
- `grkr --issue <id>` automatically shrinks oversized Codex-generated PR bodies so `gh pr create` stays under GitHub's 65536-character body limit.
- `grkr --issue <id>` warns when the working directory is dirty, then continues so intentionally staged or unstaged local changes can be included.
- `grkr --issue <id>` mirrors its launcher log to the GitHub issue as a collapsed details block so the thread stays readable by default.
- Copy `.grkr/config.sh.example` to `.grkr/config.sh` and edit the values for your repo if you want to manage config manually.
- `grkr init <id>` will create `.grkr/config.sh` for the current `origin` remote and project id you pass in.

## Requirements

- GitHub CLI (`gh`) installed and authenticated (`gh auth login`)
- Codex CLI available in PATH
- `jq` for JSON parsing
- Node.js (for global install)
- Git repository with an `origin` remote configured
