## 1. Goal

Build a long-running shell-based AI agent that uses **Codex CLI** and **GitHub CLI (`gh`)** to continuously triage repository work, resolve PR conflicts, react to `@:robot:` comments, and execute assigned issues from a GitHub Project.

The agent runs inside a local clone of a single GitHub repository and loops every **20 seconds**. In each iteration it:

1. syncs local `main` to the latest remote commit,
2. scans open PRs for merge conflicts with `main` and resolves them using Codex,
3. scans GitHub comments for commands starting with `@:robot:` and processes them using Codex,
4. scans a specified GitHub Project for issues assigned to the agent in **Todo** state, chooses the highest-priority candidate, and executes it through a staged pipeline,
5. remains resilient to internal errors so the main loop continues even when any individual action fails.

The implementation must use **shell scripts** as the primary implementation language.

---

