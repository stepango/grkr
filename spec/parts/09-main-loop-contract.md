## 7. Main loop contract

Each iteration performs these phases in order:

1. `sync_main`
2. `scan_and_schedule_pr_conflicts`
3. `scan_and_schedule_comment_commands`
4. `pick_and_schedule_issue_execution`
5. `reap_finished_jobs`
6. `cleanup_stale_worktrees`
7. `sleep_until_next_tick`

Pseudo-code:

```bash
while true; do
  tick_started_at=$(date +%s)

  run_phase sync_main || log_phase_error sync_main
  run_phase scan_prs || log_phase_error scan_prs
  run_phase scan_comments || log_phase_error scan_comments
  run_phase pick_issue || log_phase_error pick_issue
  run_phase reap || log_phase_error reap
  run_phase cleanup || log_phase_error cleanup

  sleep_remaining_time "$tick_started_at" "$LOOP_INTERVAL_SECS"
done
```

### 7.1 Resilience rules

- each phase must be wrapped in an error boundary,
- the supervisor must never exit just because a worker fails,
- workers may use `set -euo pipefail`,
- the supervisor must catch worker exit codes and continue.

---

