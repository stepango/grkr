# grkr

AI-powered CLI that reads a GitHub issue and uses Codex to implement the changes.

## Usage

```bash
# Install globally
npm install -g .

# Create the config for this repo and project
grkr init 42

# Run for an issue
grkr --issue 1

# Run the smoke test
npm test
```

## How it works

1. Validates prerequisites (clean git state, gh auth)
2. Fetches issue details using `gh issue view`
3. Creates/switch to branch `issue-N`
4. Runs `codex exec` with a detailed prompt based on the issue
5. After Codex finishes implementing, grkr commits, pushes, and opens a PR that links the issue

## Install Notes

- `npm install -g .` installs the local `bin/grkr` launcher into your PATH.
- `npm test` refreshes the split spec files under `spec/parts/` and runs the mocked shell tests without needing GitHub access.
- Copy `.grkr/config.sh.example` to `.grkr/config.sh` and edit the values for your repo if you want to manage config manually.
- `grkr init <id>` will create `.grkr/config.sh` for the current `origin` remote and project id you pass in.

## Requirements

- GitHub CLI (`gh`) installed and authenticated (`gh auth login`)
- Codex CLI available in PATH
- `jq` for JSON parsing
- Node.js (for global install)
- Clean working directory
