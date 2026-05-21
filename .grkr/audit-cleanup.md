# Audit + Proposed Safe Cleanup for Stale .hermes / .claude Artifacts
# Task: t_4bb0bafc (2026-05-21, GitHub-only v2 prep)
# Status: NON-DESTRUCTIVE AUDIT ONLY - no rm executed

**Date:** 2026-05-21  
**Worker:** default (kanban-worker)  
**Workspace:** /Users/claw/work/grkr-v2-cron  
**References:** 
- Prior cards: t_980b7473 (clean .automation), t_9f56f7ed (audit .hermes/kanban+.claude), t_325483b3 (remove .hermes/*.lock), t_57ccc025 (propose), t_73669aac (approved), t_b7672222 (cleanup safe remove)
- AGENTS.md, spec/parts/36-cleanup-policy.md, kanban-worker skill (terminal safety for rm -rf)
- docs/gleam-migration.md, supervisor-design-final.md

## Execution Summary (Non-Destructive)
- Used terminal for: pwd, ls -lT, find, du -sh, ps aux, lsof, sqlite3 via python on /Users/claw/.hermes/kanban.db, grep
- Verified no active processes on stale items (only current gateway 61697 holds gateway.lock; gleam lsp 62280 holds current build/*.lock)
- Queried kanban.db for task status of workspace task-ids
- All proposed commands are prefixed with `# ` (commented, copy-paste safe after review)
- Total estimated reclaim: ~60-80MB (workspaces 0-27M each, claude worktrees ~10MB+)
- No files were modified or deleted in this run (per acceptance criteria)
- This card blocks for human review per kanban-worker "review-required" protocol

## Safety Verification
- **Active processes** (from ps aux | grep hermes|kanban|claude|gleam|node): current workers for several tasks (incl this t_4bb0bafc), gateway (61697), dashboard, gleam lsp (62280), pyright.
- **lsof on locks**: only gateway.lock held by 61697; auth.lock not open; no hits on old workspace paths or old claude dirs.
- **kanban.db task status** (selected old workspace ids):
  - Many "blocked" (v2 Gleam work: refusal, supervisor, github_picker, refusal/checkpoint etc.)
  - Some "done" (t_418d015f, t_41dbab7b, t_bc6f5e43)
  - t_980b7473 and t_b7672222 (prior cleanups) also blocked
  - Workspaces are historical snapshots from May 16-20; current work uses main /work/grkr-v2-cron + git. Safe to remove old workspaces.
- **Current active locks** (fresh dates): gateway, cron/.tick.lock (May21), current workspace/build/*.lock (May21 01:11)
- **.claude**: no claude processes running; main project dir has recent jsonl sessions; automation-worktrees are detached old clones.

## 1. Root .hermes Locks
Path: /Users/claw/.hermes/

- `auth.lock` (0B, May 20 19:08:49, not held by lsof) — stale, safe to remove
- `gateway.lock` (156B, May 19 10:31:35, **HELD** by gateway pid 61697) — **DO NOT REMOVE** while gateway running
- `gateway.pid` (156B, May 19 10:31:35) — current for running gateway
- `cron/.tick.lock` (0B, May 21 01:11:39) — current cron tick, leave

Other .lock files (internal, leave unless reviewed):
- hermes-agent/venv/* .lock (Apr 21, package/uv)
- memories/*.md.lock (Apr 21-24)
- skills/.usage.json.lock (May 10)
- lsp/node_modules/.../yarn.lock etc (package files)

**Proposed commands (root .hermes):**
```bash
# 1. root locks (only auth.lock is stale/unheld)
# rm -f /Users/claw/.hermes/auth.lock
# (gateway.* and cron/.* are active - do not touch)
```

## 2. Stale Kanban Workspaces
Path: /Users/claw/.hermes/kanban/workspaces/t_*

15 dirs, all created May 16-20 2026 (pre-current date), containing old grkr/ source snapshots + build/gleam*.lock + spec/ etc from prior worker runs.

Sizes (du -sh):
- t_980b7473: 0B (May 16 17:46)
- t_a0cbcd49: 0B (May 20 19:12)
- t_b7672222: 0B (May 17 18:06)
- t_f741839b: 0B (May 18 00:11)
- t_bc6f5e43: 27M (May 16 00:53)  [PR #91 review]
- t_d4950970: 1.2M (May 17 12:15)
- t_6ab2a573: 3.5M (May 18 00:19)
- t_418d015f: 4.0M (May 18 00:13)
- t_abdf8e23: 4.0M (May 18 00:19)
- t_b160db65: 4.0M (May 18 00:13)
- t_c350062c: 4.6M (May 20 19:14)
- t_41dbab7b: 6.3M (May 18 00:23)
- t_eef2b391: 6.9M (May 20 19:13)  [github_picker warnings + e2e]
- t_e924033c: 7.3M (May 18 00:18)
- t_dcf59c4e: 8.4M (May 20 19:17)  [supervisor modules]

**Task titles/status from kanban.db (examples of v2 work):**
- t_eef2b391: fix: address unused import/arg warnings in github_picker, supervisor, refusal Gleam... (blocked)
- t_b160db65: fix: refusal Gleam config... (blocked)
- t_dcf59c4e: fix: implement supervisor missing modules (phases.gleam...) (blocked)
- t_c350062c: fix: implement refusal/checkpoint.gleam... (blocked)
- t_6ab2a573: audit: harden project move logic... (blocked)
- t_980b7473: clean: remove stale .automation/... (blocked)
- t_b7672222: cleanup: safe remove stale kanban workspaces... (blocked)  [meta]
- done ones: t_418d015f, t_41dbab7b, t_bc6f5e43

**Proposed commands (kanban workspaces - remove all as stale historical):**
```bash
# 2. kanban workspaces (all 15; use after review; these are old worker copies)
# rm -rf /Users/claw/.hermes/kanban/workspaces/t_980b7473
# rm -rf /Users/claw/.hermes/kanban/workspaces/t_a0cbcd49
# rm -rf /Users/claw/.hermes/kanban/workspaces/t_b7672222
# rm -rf /Users/claw/.hermes/kanban/workspaces/t_f741839b
# rm -rf /Users/claw/.hermes/kanban/workspaces/t_bc6f5e43
# rm -rf /Users/claw/.hermes/kanban/workspaces/t_d4950970
# rm -rf /Users/claw/.hermes/kanban/workspaces/t_6ab2a573
# rm -rf /Users/claw/.hermes/kanban/workspaces/t_418d015f
# rm -rf /Users/claw/.hermes/kanban/workspaces/t_abdf8e23
# rm -rf /Users/claw/.hermes/kanban/workspaces/t_b160db65
# rm -rf /Users/claw/.hermes/kanban/workspaces/t_c350062c
# rm -rf /Users/claw/.hermes/kanban/workspaces/t_41dbab7b
# rm -rf /Users/claw/.hermes/kanban/workspaces/t_eef2b391
# rm -rf /Users/claw/.hermes/kanban/workspaces/t_e924033c
# rm -rf /Users/claw/.hermes/kanban/workspaces/t_dcf59c4e
```

(Alternative one-liner after review: `# rm -rf /Users/claw/.hermes/kanban/workspaces/t_{980b7473,a0cbcd49,...}` )

Note: removing these also cleans the embedded build/*.lock and grkr/ copies inside them.

## 3. .claude Worktrees / Projects
Path: /Users/claw/.claude/projects/

- Active/main: `-Users-claw-work-grkr-v2-cron` (May 13 13:05, 680K, contains .jsonl session logs up to May13) — **KEEP**
- `-Users-claw` (May 5 21:23, 12K, old) — stale
- 18+ automation worktree clones: all named `*-automation-worktrees-*` (Apr 26 22:57 to May 13 13:03, sizes 232K-2.1M each)
  These were created by prior claude/automation runs for specific issues (v2-issue-*, gleam-*, refusal-flow, linear-e2e, supervisor etc.)
  No active claude processes; no symlinks/refs from main project dir; old dates.

**Proposed commands (.claude):**
```bash
# 3. .claude stale worktrees (keep main -Users-claw-work-grkr-v2-cron and its sessions)
# rm -rf /Users/claw/.claude/projects/-Users-claw
# rm -rf "/Users/claw/.claude/projects/-Users-claw-work-grkr-v2-cron--automation-worktrees-issue-15-implement-or-refuse-gate"
# rm -rf "/Users/claw/.claude/projects/-Users-claw-work-grkr-v2-cron--automation-worktrees-v2-issue-16-refusal-flow"
# rm -rf "/Users/claw/.claude/projects/-Users-claw-work-grkr-v2-cron--automation-worktrees-v2-issue-20-resolve-pr"
# rm -rf "/Users/claw/.claude/projects/-Users-claw-work-grkr-v2-cron--automation-worktrees-v2-issue-69-gleam-linear-auth"
# rm -rf "/Users/claw/.claude/projects/-Users-claw-work-grkr-v2-cron--automation-worktrees-v2-issue-70-gleam-linear-query"
# rm -rf "/Users/claw/.claude/projects/-Users-claw-work-grkr-v2-cron--automation-worktrees-v2-issue-72-gleam-linear-e2e"
# rm -rf "/Users/claw/.claude/projects/-Users-claw-work-grkr-v2-cron--automation-worktrees-v2-issue-71-gleam-linear-progress"
# rm -rf "/Users/claw/.claude/projects/-Users-claw-work-grkr-v2-cron--automation-worktrees-v2-issue-77-gleam-sync-main"
# rm -rf "/Users/claw/.claude/projects/-Users-claw-work-grkr-v2-cron--automation-worktrees-v2-issue-72-gleam-linear-live-mutations-20260502222705"
# rm -rf "/Users/claw/.claude/projects/-Users-claw-work-grkr-v2-cron--automation-worktrees-v2-issue-69-gleam-linear-oauth-exchange-20260503115621"
# rm -rf "/Users/claw/.claude/projects/-Users-claw-work-grkr-v2-cron--automation-worktrees-v2-issue-70-gleam-linear-selection-20260503111557"
# rm -rf "/Users/claw/.claude/projects/-Users-claw-work-grkr-v2-cron--automation-worktrees-v2-issue-71-gleam-linear-progress-20260504132725"
# rm -rf "/Users/claw/.claude/projects/-Users-claw-work-grkr-v2-cron--automation-worktrees-v2-issue-70-gleam-linear-discovery-cli-202605050048"
# rm -rf "/Users/claw/.claude/projects/-Users-claw-work-grkr-v2-cron--automation-worktrees-v2-issue-86-gleam-task-slug"
# rm -rf "/Users/claw/.claude/projects/-Users-claw-work-grkr-v2-cron--automation-worktrees-v2-issue-15-gleam-decision-gate"
# rm -rf "/Users/claw/.claude/projects/-Users-claw-work-grkr-v2-cron--automation-worktrees-issue-72-linear-e2e-oauth"
# rm -rf "/Users/claw/.claude/projects/-Users-claw-work-grkr-v2-cron--automation-worktrees-v2-issue-88-gleam-project-status"
# (the May 13 issue-88 one is borderline recent but still automation-worktree; remove if not needed)
```

Optional extra (old sessions, empty):
```bash
# rm -rf /Users/claw/.claude/sessions
# rm -rf /Users/claw/.claude/session-env
# rm -rf /Users/claw/.claude/backups
```

## 4. build/ Locks and Related
- **Current active** (in workspace): /Users/claw/work/grkr-v2-cron/build/*.lock (0B, May 21 01:11:17), dev/, lsp/, packages/ (gleam_javascript etc May 18) — **DO NOT REMOVE** (gleam lsp active, recent builds)
- Stale build/ inside kanban workspaces (e.g. t_eef2b391/grkr/build/gleam-*.lock dated May 20, t_bc6f5e43/grkr/build/ etc) — removed as part of #2 above
- Internal package locks (hermes-agent/uv.lock, lsp/yarn.lock, node_modules) — leave (not our build)

**Proposed for build (none additional, covered by workspaces):**
```bash
# 4. build locks - only stale ones inside workspaces removed via section 2; current workspace/build/ is active
# (no direct rm for /Users/claw/work/grkr-v2-cron/build/ )
```

## Additional / Edge Cases
- No .automation/ or .automation-local/ found in workspace (prior t_980b7473 cleanup succeeded)
- ~/.grkr/ has logs/ (May 2) and this audit file — leave
- ~/.hermes/kanban/logs/ (May 21) — active, leave
- ~/.hermes/state* , kanban.db (active) — leave
- After cleanup, space reclaimed; recommend re-run audit or add to cron policy
- For future: kanban workspaces should use scratch kind more, or auto-prune on task complete

## Next Steps (After Human Review)
1. Human reviews this file + comment on t_4bb0bafc
2. If approved, unblock or spawn exec card (e.g. t_xxx) that actually runs the # rm commands (perhaps via terminal after explicit approve)
3. Update this file or kanban comment with "executed" note + new sizes
4. Re-audit to confirm clean
5. Update README.md or docs/gleam-migration.md if relevant (per AGENTS.md)

**End of audit. All rm commands above are ready-to-run but commented and non-destructive by design.**

# Generated by kanban task t_4bb0bafc worker
# Do not execute without review per kanban-worker skill guidelines
