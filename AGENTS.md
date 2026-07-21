# Repo Instructions

- After any functional change, update `README.md` so the user-facing workflow stays accurate.
- Treat the split spec slices under `spec/parts/` as the canonical spec source.
- Keep `spec/spec.md` as a generated index over `spec/parts/`.
- Run the spec sync harness before finishing spec-related work so the index stays current.
- Prefer the split spec files for context-heavy tasks instead of loading the full spec blob.
- Preserve existing shell-script conventions in `bin/` and `test/`; keep changes small and explicit.
- Keep every file at 1000 lines or fewer. If a change would push a file over the limit, proactively split or extract helpers before finishing.

## Coding executor (Grok Build CLI + built-in skills)

Hermes Kanban workers and coding crons must **not** implement Gleam/product code with Hermes edit loops. Use headless **Grok Build CLI** with built-in skills/agents:

| Intent | Grok surface |
|--------|----------------|
| Design | `--mode design` / agent **`plan`** (architect design; not interactive `/plan` approval UI) |
| Goal tracking | **`/goal <objective>`** via `GROK_GOAL=1` |
| Implement | `--mode implement` or **`--mode full`** |
| Verify | **`--check`** → **`/check-work`** |
| Strict review | **`/code-review`** in the prompt |
| Explore | **`explore`** subagent |

```bash
~/.hermes/scripts/grok_build_exec.sh \
  --cwd /Users/claw/work/grkr-v2-cron \
  --prompt-file /tmp/grkr-grok-prompt.txt \
  --mode full \
  --model grok-4.5 \
  --max-turns 60 \
  --log /tmp/grkr-grok-last.log
```

Orchestrator (factory cron) still only creates/links Kanban cards. Implementer workers: write a self-contained prompt (spec parts + acceptance + AGENTS.md), run the CLI with skills above, then verify `gleam build` / tests and complete/block the card. Review cards should invoke `/code-review` rather than implementing.

## Linear Integration Notes
- Linear auth uses direct `client_credentials` grant from `~/.linear/secret.txt` (no browser or user interaction required).
- Use `curl -X POST https://api.linear.app/oauth/token` with `grant_type=client_credentials`, `client_id`, `client_secret`, and `scope=read write` to obtain the access token.
- Store the token in `~/.linear/token.txt` or via `GRKR_LINEAR_ACCESS_TOKEN`.
- Never treat raw app credentials as a bearer token in GraphQL calls.

## PR merge policy (owner / this machine)

When open PRs on `stepango/grkr` are **MERGEABLE**, checks green (or none required), and the only block is required approving review that same-author cannot satisfy:

- Squash-merge with admin override is allowed:
  `gh pr merge <N> --squash --admin --delete-branch`
- Prefer `gh pr merge <N> --auto --squash --admin --delete-branch` while CI is still pending if already mergeable.
- Report merged PR numbers + resulting tip. Do **not** force-push `main` / protected bases.
- This is for **owner-operated** automation only; do not bypass failing checks.
