# Supervisor Cleanup Policy Decision (spec/parts/36)

## Classification Rules for Worktrees under config.worktrees_dir

1. **Completed worktrees**: Remove if mtime > 1 hour (3600s) and no active job reference in state.active_jobs. Matches "remove completed worktrees older than 1 hour".

2. **Failed worktrees**: Remove if mtime > config.worktree_ttl_seconds (default 3600s) and job marked failed in state. Per "remove failed worktrees older than configured TTL".

3. **Refusal-safe handling** (per spec):
   - Task directories (under .grkr/tasks/ or equivalent) MUST be preserved for refused issues.
   - Refusal checkpoints in state (processed_comments, recovery checkpoints) MUST remain.
   - Worktrees for refused issues: removable ONLY after refusal is committed to state + comments (i.e., after run_scan_comment_commands_phase has processed the refusal). Worktree prune may happen immediately post-commit; task dir and checkpoints stay forever.

4. **Stale worktrees** (no matching job state): Prune if older than TTL, unless refusal checkpoint present.

5. **Active / in-progress**: Never touch (protected by active_jobs + lock checks in recovery).

## Implementation Notes
- Use ffi.stat_mtime + list_files in phases.gleam run_cleanup_stale_worktrees_phase (already partially wired in prior cards).
- recovery.gleam provides purge_stale_lock_files and refusal checkpoint helpers.
- state.gleam manages active_jobs, processed_comments, refusal markers.
- Criteria unambiguous from spec/parts/36-cleanup-policy.md; no human decision needed for classification.

This enables safe destructive prune in parent t_8f06d85c without risk to refusal state.
