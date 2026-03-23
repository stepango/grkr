# grkr

AI-powered CLI that reads a GitHub issue and uses opencode to implement the changes, then opens a PR.

## Usage

```bash
# Install
npm install -g .

# Run for an issue
grkr --issue 1
```

## How it works

1. Fetches issue details using `gh issue view`
2. Creates a feature branch
3. Runs opencode CLI with the issue description as prompt to implement the feature
4. Commits changes
5. Opens a PR using `gh pr create`

## Requirements

- GitHub CLI (`gh`) installed and authenticated
- opencode CLI available in PATH
- Node.js

