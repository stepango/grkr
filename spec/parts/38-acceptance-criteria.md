## 30. Acceptance criteria

The system is complete when all are true:

1. the supervisor runs continuously and survives worker failures,
2. each 20-second loop continues even when one phase fails,
3. actionable comments get `eyes` at start and `rocket` on success,
4. assigned Todo issues can be discovered and prioritized,
5. research, plan, and test generate local Markdown checkpoints and post them to the issue,
6. PR merge conflicts against `main` can be resolved in isolated worktrees,
7. issue execution can resume from checkpoint files,
8. issue execution may validly end in **refusal**,
9. refusal posts a reasoned comment,
10. refusal moves the issue from **Todo** to **Backlog**,
11. refusal is checkpointed locally in `refusal.md`,
12. refusal is treated as a valid terminal state rather than a worker failure.

---

