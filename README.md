# grkr

AI-powered CLI that reads a GitHub issue and uses Codex to implement the changes.

## Usage

```bash
# Install globally
npm install -g .

# Run for an issue
grkr --issue 1
```

## How it works

1. Validates prerequisites (clean git state, gh auth)
2. Fetches issue details using `gh issue view`
3. Creates/switch to branch `issue-N`
4. Runs `codex exec` with a detailed prompt based on the issue
5. After Codex finishes implementing, you commit and create PR

## Requirements

- GitHub CLI (`gh`) installed and authenticated (`gh auth login`)
- Codex CLI available in PATH
- `jq` for JSON parsing
- Node.js (for global install)
- Clean working directory
