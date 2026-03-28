## 25. Locking and concurrency

### 25.1 Locks

Use `flock` on:

- `main.lock`
- `comments.lock`
- `prs.lock`
- `issues.lock`
- `pr-<n>.lock`
- `issue-<n>.lock`
- `comment-<id>.lock`

### 25.2 Rules

- only one sync-main at a time
- only one worker per PR
- only one worker per comment version
- only one workflow per issue
- only one active issue execution by default

### 25.3 Dead process recovery

At the beginning of each loop:

- inspect `active_jobs.json`
- if recorded PID no longer exists:
  - mark job stale
  - release lock
  - optionally requeue the job

---

