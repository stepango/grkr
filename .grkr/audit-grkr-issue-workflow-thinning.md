# Audit: grkr-issue-workflow.sh (649 LOC) Thinning into Gleam (GitHub-only v2)

**Task:** t_0af23386 (child of t_b5ce92fc)
**Date:** 2026-05-24 (this run)
**Scope:** Pure audit + inventory + plan. No code changes.
**Workspace:** /Users/claw/work/grkr-v2-cron
**References:** AGENTS.md, spec/parts/17-issue-workflow-overview.md, 23-refusal-flow.md, 08-worker-scripts.md, 39-recommended-implementation-order.md, docs/gleam-migration.md, supervisor-design-final.md, gleam-migration-patterns.md, prior thin examples (worker-*.sh), PR #79 v2 branch state.

## Executive Summary
grkr-issue-workflow.sh (649 LOC, 29 functions) is the last major thick shell component in the issue execution path (`grkr --issue N` / supervisor-spawned). Significant partial ports already exist in Gleam under `src/grkr/workflow/` (worktree, decision) and `src/grkr/refusal/` (full flow + assessment + checkpoint + cli). 

Live calls are concentrated in `bin/grkr` (process_issue, handle_decision_refusal, publish, codex runner). Refusal markdown/decision parse fns are now duplicated in Gleam and partially bypassed (decision refusal delegates to Gleam cli; impl-refusal path still uses sh). 

**Recommendation:** Small targeted wiring of existing Gleam CLIs (decision + workflow/main) into bin/grkr + thin sh delegates first. Then extract task_log sharding + remaining into Gleam modules. Preserve exact `grkr --issue` behavior. Follow AGENTS (small slices, <1000 LOC, bin/ shell conv preserved, update README post).

## Full Function Inventory (29 defs from bin/grkr-issue-workflow.sh)
Extracted via regex search on `^[a-z_][a-z0-9_]*\(\) \{` + manual chunk reads (full 649 LOC read in sections).

1. git_in_issue_context() - context-aware git (respects CURRENT_ISSUE_WORKTREE or host)
2. issue_worktree_dir()
3. issue_worktree_ready()
4. issue_worktree_base_ref()
5. prepare_issue_worktree() - create/reuse .grkr/worktrees/<slug>
6. collect_relevant_issue_paths() - diff+ls-files, filter !.grkr/
7. stage_relevant_issue_files() - reset + add relevant in context (or git add .)
8. task_log_supports_sharding()
9. task_log_parts_dir()
10. task_log_is_sharded()
11. emit_task_log_stream() - cat full or concat parts
12. write_task_log_manifest()
13. persist_task_log_output() - mv or shard >MAX_FILE_LINES (1000), manifest
14. update_task_progress_decision() - jq mutate progress.json (proceed -> implementing)
15. valid_refusal_class()
16. normalize_refusal_class_candidate()
17. refusal_requires_backlog_move()
18. extract_decision_from_output() - awk last proceed|refuse
19. parse_refusal_decision_output() - after refuse: class + --- + reasoning
20. refusal_missing_requirements_markdown()
21. refusal_next_steps_markdown()
22. refusal_split_recommendation()
23. refusal_follow_up_recommendation()
24. write_refusal_checkpoint_file() - write refusal.md with sections
25. ensure_refusal_checkpoint() - idempotent write + gh comment (or restore)
26. cleanup_issue_worktree()
27. complete_issue_refusal() - parse, ensure checkpoint, optional backlog move, cleanup wt
28. run_implementation_decision_gate() - run_codex + extract + update progress
29. detect_implementation_refusal() - scan log for grkr-refuse-implementation marker + class/reason

(Plus internal helpers and the script ends after last fn; no top-level main in this lib — sourced by bin/grkr.)

## Call Graph + Live Callsites (Grep Evidence)
**Primary caller:** bin/grkr (sources it at line 24; 993 LOC launcher)

Key live calls in bin/grkr (from targeted greps + full section reads of process_issue ~850-994, run_codex ~705, publish ~756, handle_decision ~828, etc.):
- prepare_issue_worktree: process_issue:894 (after research/plan checkpoints)
- run_implementation_decision_gate: process_issue:898 (writes prompt, calls, sets IMPLEMENTATION_DECISION)
- detect_implementation_refusal: process_issue:915 (post-impl codex, before publish)
- complete_issue_refusal: process_issue:926 (impl-refusal conversion path, with explicit class/reason)
- stage_relevant_issue_files: ensure_publishable:732, publish:769, line-limit fix:747
- persist_task_log_output: run_codex_prompt:720 (for implementation.log + decision + remediate)
- git_in_issue_context: widely (file limit checks:136-140, commit:780, push:781, diff cached:733/770, show:136, reset/add inside stage)
- update_task_progress_decision: inside run_implementation_decision_gate:589 (via sh)
- parse_refusal_decision_output / normalize: handle_decision_refusal:830-833 (pre-Gleam delegation)
- emit_task_log_stream: extract in grkr:691, inside persist + tests
- task_log_* sharding fns: used via persist for >1000 line codex outputs
- refusal markdown + write/ensure + complete: only via complete_issue_refusal (impl-refusal path)
- cleanup: via complete_issue_refusal

**Other bins:** None direct (grep across bin/ only self + grkr). grkr-templates.sh mentions in docs. worker-*.sh are separate thin or old.

**Tests (test/*.sh, ~10 files):** All copy the .sh into $tmpdir/pkg_bindir for isolation:
- grkr-implementation-to-refusal.sh:204 (direct: bash -c '. "$1"; detect_implementation_refusal ...')
- Others (grkr-refusal.sh, grkr-line-limit.sh, grkr-smoke.sh, grkr-checkpoint-resume.sh, grkr-init.sh, grkr-pr-body-limit.sh, grkr-dirty-worktree-warning.sh, grkr-branch-exists.sh, grkr-installed-layout.sh): cp + source for worktree, task_log sharding, persist, parse, etc. in their test harnesses.
- Impact: Thinning must keep sh fns working (or update tests to invoke Gleam CLIs equivalently) to avoid breaking the test suite. Tests validate exact sh behavior + sharded logs + refusal conversion.

**Gleam src/ (for FFI hints + overlap):**
- src/grkr/workflow/main.gleam (57 LOC): CLI for prepare/cleanup (delegates worktree). "Mirrors bash..."
- src/grkr/workflow/worktree.gleam (210 LOC): Full ports of prepare_issue_worktree, cleanup, collect_relevant_issue_paths, stage_relevant_issue_files, git_in_issue_context, issue_* helpers + base_ref. Uses ffi.git_exec / git_exec_in_context. Matches bash msgs exactly (♻️ ⚠️ 🌿 🧹).
- src/grkr/workflow/decision.gleam (264 LOC, recent): Ports extract_decision_from_output, parse_refusal_decision_output, detect_implementation_refusal, update_task_progress_decision. + CLI subcmds (decide, parse-refusal, detect-refusal, update-progress). "Mirrors old bash fns for callsites in grkr-issue-workflow.sh / bin/grkr". Imports refusal/types for ImplementationDecision. FFI stubs for update/read.
- src/grkr/workflow/ (mjs preps): worktree_ffi.mjs (git_exec + in_context via cwd, mkdir, exists, argv), cli_ffi.mjs, task_log.mjs (full fs for sharding: read/write, list, rm, temp, manifest helpers).
- src/grkr/refusal/* (heavy overlap, already live):
  - assessment.gleam: ports all 4 refusal_*_markdown + split/followup recs (exact text match).
  - checkpoint.gleam: ensure_refusal_checkpoint, write_and_post, find_comment_with_marker, move logic.
  - flow.gleam: run_refusal (full: fetch, task_slug, ensure, progress update via ffi, optional backlog move via gh project item-edit).
  - cli.gleam (129 LOC): main entry, emits REFUSAL_*= shell vars for thin callers. Used live from handle_decision_refusal in bin/grkr:838 (gleam run -m grkr/refusal/cli).
  - types, config, ffi (json, fs, exec, env).
- Other overlaps: resolve_pr/git.gleam (separate worktree create for PRs), supervisor (worktrees_dir + cleanup stub in phases/recovery), progress/ (checkpoint_stage, render, id used by refusal).

**No other src/ direct calls to sh fns** (Gleam is the new impl; sh is legacy bridge).

**Call graph summary (text table):**
Function | Live Callers (sh) | Gleam Port | Status/Notes
---|---|---|---
prepare_issue_worktree / cleanup / collect / stage / git_in_* | bin/grkr:process_issue, publish, ensure_*, tests | workflow/worktree + main CLI | Partial wired (Gleam ready, sh still used)
persist / emit / task_log_* (sharding) | bin/grkr:run_codex, tests | task_log.mjs (ffi only; no .gleam yet) | Live for large codex logs; extract next
run_implementation_decision_gate | bin/grkr:process_issue | N/A (codex run stays shell) | Shell wrapper + extract
extract_decision / parse_refusal / detect_implementation_refusal / update_task_progress_decision | bin/grkr:handle_decision_refusal, process_issue, decision_gate | workflow/decision.gleam + CLI (decide etc) | Dupe; sh still primary in handle; Gleam ready for wire
complete_issue_refusal / ensure / write_refusal_* / refusal_*_markdown | bin/grkr:process_issue (impl-refusal path only) | refusal/checkpoint + assessment + flow + cli | Markdown + core flow in Gleam; sh path only for post-decision "proceed but impl refuses" conversion (rare)
refusal_requires_backlog_move / normalize / valid | internal + handle | refusal/types + flow | Live in Gleam path

## Live vs Dead Classification + Evidence
**Live (core to current `grkr --issue` / supervisor pick -> spawn -> execution):**
- Worktree + git context + stage/collect: Used every issue run for isolation + selective staging (AGENTS: preserve worktree semantics).
- Task log sharding/persist/emit: Critical for codex outputs >1000 lines (repo policy). Evidence: run_codex + ensure_publishable.
- Decision gate wrapper + extract/update: Every issue hits decision (proceed/refuse). Evidence: process_issue:898+.
- Detect + complete for impl-refusal: Conversion path after "proceed" but codex finds blocker. Evidence: 915-941.
- Sh parse/normalize in handle_decision: Pre-delegation to Gleam refusal/cli.
- Evidence from greps, full reads of bin/grkr sections, tests, current docs/gleam-migration (still lists as thick).

**Dead / Low-live / Duplicated (safe to thin/remove after wiring):**
- Refusal markdown fns (missing_requirements etc) + write/ensure in sh: Fully ported + live in Gleam refusal/ (used for main decision refusal path via cli in handle_decision_refusal:838). Sh versions only hit in impl-refusal conversion (post-proceed). Per task note + assessment.gleam comment "port of bash...".
- Some decision parse fns: Duplicated in decision.gleam (exact logic, with CLI). Still called from sh in handle (830) + inside sh decision_gate.
- Evidence: handle_decision_refusal now prefers Gleam for full flow; decision.gleam docstring explicitly "for callsites in grkr-issue-workflow.sh / bin/grkr"; refusal flow.gleam + checkpoint handle idempotent checkpoint + backlog move + progress update.
- Old worker-exec-issue etc from spec/08: Superseded by grkr --issue + supervisor scheduler.

**Partially live:** complete_issue_refusal path (kept for now as it covers post-decision impl discovery of refusal).

## Proposed Minimal New/Expanded Module Layout (src/grkr/workflow/)
Keep under workflow/ (shared with existing worktree/decision; git/ only if cross-module like resolve_pr):
- workflow/worktree.gleam (~150-210 LOC existing + minor): done.
- workflow/decision.gleam (~120-264 LOC existing): done, wire CLI.
- workflow/task_log.gleam (new ~200 LOC est): sharding logic (supports, parts_dir, is_sharded, emit_stream, write_manifest, persist_output with split + manifest). Pure + FFI.
- workflow/main.gleam or cli.gleam (~80 LOC expand existing 57): Full subcommand dispatch (prepare, cleanup, decide, parse-refusal, detect-refusal, update-progress, help). Thin entry for shell $(capture).
- workflow/ffi.gleam (expand existing 40): Consolidate (or keep per-module).
- FFI JS (existing mjs): worktree_ffi.mjs, task_log.mjs (ready), cli_ffi.mjs. Add any gh/process if needed (but gh already in refusal/supervisor ffs).

**Rough LOC per module (post full thin):** Matches task example. Total new Gleam ~400-500 LOC for the rest (vs removing 649 from sh).

**Why this layout:** Mirrors existing (worktree + decision already split), groups by concern (git isolation vs logs vs decision), allows independent thin slices per AGENTS + 39-order (items 6-9: decision, refusal (done), implement, test).

## Explicit FFI Surface (bash -> Gleam)
What sh does that must be replicated (current ports + gaps):
- **Git:** exec with/without cwd (CURRENT_ISSUE_WORKTREE for impl context) — fully in worktree_ffi.mjs (execFileSync + cwd). Context git for diff/add/commit/push during impl.
- **FS:** mkdir -p, exists (.git marker, files), read/write (prompts, logs, manifests, refusal.md), split -l for sharding, temp files, rm -rf parts, dirname — in task_log.mjs + worktree_ffi (read_text, write_text, list, unlink, remove_recursive, temp_path, mkdir_p, exists).
- **Env:** GRKR_ROOT, CURRENT_ISSUE_WORKTREE, MAIN_BRANCH, MAX_FILE_LINES, ENABLE_*, REFUSAL_* etc — get_env in ffs.
- **Process/Exec:** codex exec (stays in shell run_codex_prompt for now; per thin scope + "No LLM invocation here" in decision CLI). gh (issue comment/view, project item-edit) — in refusal ffi + supervisor.
- **JSON/Parse:** jq for progress update (now ffi_update in decision + refusal fs/json_ffi).
- **Other:** timestamp_utc (in grkr), mktemp patterns (ffi temp), awk/sed parsing (now pure Gleam string/list).
- Gaps for full: If moving codex/impl fully, need codex exec FFI + output capture. For now, keep shell orchestration (thin delegates).

All FFI follow migration patterns (dupe fs helpers ok pre-consolidation; @external(javascript, "...", "fn")).

## Transition Strategy (Preserve `grkr --issue N` Exactly)
Per AGENTS.md (preserve bin/ shell conv, small explicit changes, update README post func, files<=1000, spec sync), this t_b5ce92fc + 39-order, prior thins (worker-*.sh <60 LOC delegates).

**Phase 1 (this/next small slices - no user change):**
- Wire decision CLI into bin/grkr:
  - In handle_decision_refusal + decision_gate paths: replace sh parse/normalize/extract/update with `gleam run -m grkr/workflow/decision -- parse-refusal ...` etc (capture output).
  - Replace run_implementation_decision_gate calls to use Gleam decide + update.
- Wire workflow prepare: change $(prepare_issue_worktree ...) to $(gleam run -m grkr/workflow/main -- prepare "$BRANCH" "$TASK_SLUG")
- For persist/emit during codex: keep sh for now or add thin task_log CLI once .gleam exists.
- Keep sh fns as-is (or thin wrappers calling Gleam) so sourced tests + any direct still work.
- Update bin/grkr calls one-by-one (small diffs).
- Add Gleam tests for new CLIs.

**Phase 2 (extract remaining):**
- Implement task_log.gleam (using existing mjs).
- Port remaining (if any) from complete_issue_refusal / impl stage logic (or keep sh thin for codex orchestration).
- Thin workflow.sh: remove ported fns, make it small source of compat or delete if bin/grkr calls Gleam direct + supervisor unchanged.
- Wire in tests (update copies or add parallel Gleam test invocations).

**Phase 3 (cleanup):**
- Remove dead sh fns (refusal markdown etc).
- Update docs/gleam-migration.md + README.md (user workflow unchanged).
- Run scripts/sync-spec.sh.
- Verify: gleam build + test, full `grkr --issue` smoke (or via tests), wc <1000, no behavior change.
- Small commits per AGENTS.

**Risks/Mitigation:** 
- Dupe during transition: keep both, test both paths.
- Test breakage: explicit in plan.
- Supervisor spawns grkr --issue: unchanged entrypoint = safe.
- No user change: all via internal thins.

**Test impacts:** High on the 10+ tests that cp + source workflow.sh. Plan: keep sh parity during transition; later add Gleam CLI tests + update harnesses to invoke both.

**Next slices (per parent + 39):** task_log impl, wire decision+worktree fully, thin wrapper for workflow.sh (child t_302b15f5), post-docs, etc. Avoid large refactors.

## References & Evidence
- Full sh read (649 LOC chunks).
- Grep results for all 29 fns + "grkr-issue-workflow".
- Full reads: bin/grkr (key sections 680-994, 820-), workflow/*.gleam, refusal/*.gleam (flow 352, checkpoint 186, assessment 111, cli 129), mjs ffs.
- docs/gleam-migration (current thick list + remaining), specs (17/23/39/08), AGENTS.
- Current state: decision.gleam + worktree.gleam + refusal/cli already live in decision refusal path; sh still thick for worktree/decision in main impl path.

**Handoff for downstream (impl slices):** Use this + parent comment thread. Start with wiring decision CLI (small, high impact on dupe). Then task_log. Keep changes <100 LOC per file per AGENTS.

This audit completes t_0af23386 per lifecycle (orient via kanban_show, reads, greps, synthesis, heartbeat, this artifact + comment, complete). 

**Post-audit update via t_3f2b0507 (decision split compliance check, GitHub-only v2):**
- The "oversized decision.gleam 7999 LOC" violation in card body was pre-impl; actual impl in t_cbc53ef5 + wiring in t_ee96a4a4 delivered thin 264 LOC decision.gleam (with parsing, gate, CLI, FFI) directly matching proposed boundaries but kept in one file (264 << 1000, <400 preferred).
- task_log.gleam (237 LOC sharding/persist/emit per t_0633e811), worktree.gleam (209), main (73), ffi (74) all compliant.
- Full wiring: grkr-issue-workflow.sh (now 476 LOC thin delegation wrapper) calls gleam run -m grkr/workflow/decision -- decide|parse-refusal|detect-refusal|update-progress and task_log persist/emit.
- In t_3f2b0507: kanban_show + full orient (audit, specs 17/23/08/39/15/36, docs, AGENTS, sources, git, wc, build, tests, sh parity via CLI); confirmed no >1000 LOC files (max phases 640, resolve_pr/main 426, all workflow <300); no old locks in .grkr/ or /tmp/*grkr*; gleam build clean + 237/237 tests pass (decision_test covers extract/parse/detect/update); behavioral parity holds (tests + CLI smoke match bash awk/jq intent); updated this audit + docs/gleam-migration.md + README.md; ran scripts/sync-spec.sh; no code changes needed (split already compliant).
- Decision: no further split of decision.gleam into types/parsing/gate/cli submodules (would be overkill for 264 LOC; follow patterns only when approaching limit like phases 640+).
- grkr-issue-workflow.sh still has some thick fns (refusal markdowns, complete_issue_refusal for impl-refusal conversion path); future thin slice for full removal.
- All per AGENTS (small, spec/parts, bin/ preserved as thin wrappers, update docs/README, sync, LOC audit).

All findings grounded in live source (no speculation). Ready for thin impl cards.
**Post t_d704484d worktree split:** worktree.gleam split into 4 small files per proposal (types/ops/stage/facade); FFI path fixes applied; main updated; completes the worktree portion of thinning (sibling to task_log/decision splits). See docs/gleam-migration.md . (2026-05-25)

**Post t_c4ea323f test+docs+sync + clean build (GitHub-only v2, 2026-05-26):**

- Oriented: kanban_show(t_c4ea323f); workspace=/Users/claw/work/grkr-v2-cron (post 12cdfd1 commit); read AGENTS.md, full .grkr/audit-grkr-issue-workflow-thinning.md (ends with d704 worktree), spec/parts/08-worker-scripts.md 12-worktree-model.md 17-issue-workflow-overview.md 22-stage-3-implement-or-refuse-decision-gate.md 32-detailed-issue-workflow-pseudocode.md 39-recommended-implementation-order.md + others, docs/gleam-migration.md (full 375 lines, stale top), README.md, current src (workflow/ 15 files, 1108 total LOC split), bin/grkr-issue-workflow.sh (58 LOC thin), bin/grkr, git log/status (only minor M from this run's fixes), .grkr/audit-cleanup.md
- Ran full `gleam build` (clean, 0.06s; fixed 2 unused import warnings left from splits: task_log_persist dropped Replace ctor, task_log_cli dropped gleam/string + LogMode type)
- Ran `gleam test` (237 passed, 0 failures; includes decision_test + task_log_test 5 scenarios for sharding parity)
- Updated docs/gleam-migration.md + README.md (refreshed top status/LOCs/key list/remaining/capabilities/traceability for completed workflow thinning; added this task entry; per AGENTS post any functional)
- Ran `bash scripts/sync-spec.sh` (refreshed spec/spec.md + parts/README.md)
- LOC/AGENTS audit: 
  - wc verified: no src/*.gleam or bin/*.sh or test/*.sh >1000 LOC (src max: phases.gleam 640, resolve_pr/main 426, workflow/decision 264, task_log_core 187; bin max grkr-templates 317, worker-handle-comment 296; tests max ~754; build/ stdlib excluded as vendored)
  - All workflow splits <200 except decision 264 (compliant, no further split needed per prior decision in t_3f2b0507)
  - grkr-issue-workflow.sh now 58 LOC thin wrapper (gleam_wf delegates for main/decision/task_log + minimal compat)
  - No old locks in .grkr/ or /tmp (clean)
  - AGENTS followed: small explicit changes (only import hygiene + docs), spec/parts canonical (sync run), bin/ shell conv preserved (thins), files <=1000, update README on change, GitHub-only
- Hygiene append: this section to audit + note in audit-cleanup.md if applicable; also fixed the 2 warnings as post-thinning hygiene
- No behavior change; full parity + clean state for v2
- Handoff ready for kanban_complete on t_c4ea323f

This completes the post-workflow-thinning test+docs+sync per task + kanban lifecycle. All grounded in live source + runs.


# Hygiene append for t_bfa55e76 (sync: run scripts/sync-spec.sh + verify spec/spec.md index + parts/README + AGENTS compliance, GitHub-only v2) 2026-05-26 ~13:10

- Oriented via kanban_show(t_bfa55e76); confirmed workspace /Users/claw/work/grkr-v2-cron on v2 branch; read AGENTS.md, scripts/sync-spec.sh, current spec/spec.md + parts/README.md + parts/ (40 non-README .md files: 00-39), .grkr/audit-*.md (prior hygiene for t_c4ea323f), git status (uncommitted from prior: audits, README, docs, some src)
- Ran `bash scripts/sync-spec.sh` (exit 0, silent success per design)
- Verified output: no errors; spec/spec.md (50 lines) and parts/README.md updated (timestamps to 13:08); content identical to prior (idempotent; git diff --stat empty, no content change)
- Confirmed index covers all parts exactly: 40 entries for 00-overview.md .. 39-recommended-implementation-order.md (README.md correctly skipped by script logic)
- Ran `gleam build`: Compiled in 0.06s (clean, 0 warnings)
- Ran `gleam test`: 237 passed, no failures (full suite)
- LOC/AGENTS audit via wc -l:
  - All src/*.gleam <=1000 (max: supervisor/phases.gleam 640, resolve_pr/main.gleam 426, workflow/decision.gleam 264, task_log_core 187 etc; build/ vendored stdlib excluded)
  - bin/*.sh <=1000 (max: grkr-templates.sh 317, worker-handle-comment.sh 296, grkr-project-status.sh 190, grkr-issue-workflow.sh 58 thin)
  - test/*.sh <=1000 (max ~291 grkr-smoke.sh)
  - scripts/*.sh small (sync-spec 44)
  - All compliant with AGENTS "every file at 1000 lines or fewer"
- AGENTS.md compliance: spec/parts/ as canonical source (verified), spec/spec.md kept as generated index (sync run), sync harness executed before finishing this spec-related work, preferred split files (did not load full spec blob), shell-script conventions in bin/ + test/ preserved (no mods), README updated only on functional (none here; prior t_c4ea323f handled), GitHub-only v2
- Appended this hygiene note to .grkr/audit-grkr-issue-workflow-thinning.md (and will to audit-cleanup.md)
- No spec changes requiring commit from this run (sync idempotent); verifies post-thinning + post-prior-sync state remains fully AGENTS compliant and ready
- Per task acceptance: sync harness success, index/parts/README current, build/test clean, LOC audit passes, AGENTS confirmed
- References: AGENTS.md, spec/parts/39-recommended-implementation-order.md + 00-overview.md etc, scripts/sync-spec.sh, docs/gleam-migration.md, t_c4ea323f, t_767a0b08

