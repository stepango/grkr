## 28. Cleanup policy

At least every 10 loops:

- remove completed worktrees older than 1 hour,
- remove failed worktrees older than configured TTL,
- prune stale worktrees,
- purge stale locks,
- compact processed comment state.

For refused issues:

- task folders must remain,
- refusal checkpoints must remain,
- worktrees may be removed immediately after refusal is committed to state and comments.

---

