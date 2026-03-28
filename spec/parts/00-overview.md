# AI Agent Specification for Codex + GitHub CLI Shell Automation

This split spec remains the canonical design target for the project.

Current implementation status as of 2026-03-27:

- Implemented: `doctor.sh`, the `robot-main.sh` supervisor skeleton, `worker-sync-main.sh`, `worker-pick-issue.sh`, and the checkpointed `research` and `plan` stages in `bin/grkr`
- Still planned: worktree-isolated execution, the implement-or-refuse decision gate, refusal handling, test checkpoints, `@:robot:` comment automation, and PR conflict resolution

Use the later sections as the target behavior, and compare them against the tracked follow-up issues before assuming the code already satisfies every requirement below.
