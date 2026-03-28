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
2. The supervisor writes structured loop logs to `.grkr/logs/main.log` and `.grkr/logs/loop.log`, keeps per-job logs under `.grkr/logs/jobs/`, and recovers stale jobs from `.grkr/state/active_jobs.json`
3. `grkr --issue <n>` remains the focused single-issue helper that fetches issue details using `gh issue view`
4. The issue helper reuses branch `issue-N` when it already exists locally or remotely, otherwise creates it
5. After Codex finishes implementing, `grkr` commits, pushes, and opens a PR that links the issue

## Install Notes

- `npm install -g .` installs the local `bin/grkr` launcher into your PATH.
- `robot-main.sh` uses `MAIN_BRANCH` and `LOOP_INTERVAL_SECS` from `.grkr/config.sh`; `grkr init <id>` now writes both defaults into the generated config.
- `npm test` refreshes the spec index from the split files under `spec/parts/` and runs the mocked shell tests without needing GitHub access.
- Copy `.grkr/config.sh.example` to `.grkr/config.sh` and edit the values for your repo if you want to manage config manually.
- `grkr init <id>` will create `.grkr/config.sh` for the current `origin` remote and project id you pass in.

## Requirements

- GitHub CLI (`gh`) installed and authenticated (`gh auth login`)
- Codex CLI available in PATH
- `jq` for JSON parsing
- Node.js (for global install)
- Clean working directory
