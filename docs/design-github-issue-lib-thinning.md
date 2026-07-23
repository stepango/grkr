# Design: GitHub `github_issue.sh` Thinning (Gleam/shell slices)

**Status**: Design-only (plan agent). No product code edits.  
**Reference tip**: origin/main @ **9a1b8f6** (docs tip-sync PR #145 after product **c801967** / PR #144 shared helpers fifth extract).  
**Prior design artifacts**: `docs/design-grkr-shared-helpers-extract.md` (shared complete @ c801967 / #144; design d90fbaf / #135), `docs/design-github-process-issue-thinning.md` (GitHub process_issue thinning complete @ a3d9702 / #121).  
**Gap addressed**: After shared helpers extraction and thin `process_issue` sequencer, `bin/lib/github_issue.sh` (545 LOC) is the largest remaining GitHub-specific shell vertical. It owns research/plan/test/publish/completion + bootstrap/decision/implement stage orchestration for the `--issue` GitHub path. Linear paths and shared helpers are out of scope except for non-regression. Design-only — no product shell/Gleam implementation.  
**Date**: 2026-07-18

---

## 1. Goal / non-goals

### Goal
Produce `docs/design-github-issue-lib-thinning.md` that:

- Re-measures (by reading files) the current state at tip 9a1b8f6 / product c801967 and inventories **every function** in `bin/lib/github_issue.sh` (name, approx LOC, callers, Gleam overlap / already-delegated).
- Produces a **target module map** for remaining GitHub vertical (keep GitHub-specific gh/exec/loop bodies in focused shell per conventions; extract pure formatting/selection helpers to `src/grkr/workflow/*` or progress/ where they fit existing patterns; ownership vs `issue_shared.sh` and Linear).
- Defines an **ordered slice table** of shippable PRs (smallest first) with per-slice acceptance: files stay ≤1000 LOC, `gleam build` + `gleam test` + `npm test` green, GitHub smoke suite green, Linear regression matrix green (non-regression when shared boundary touched), zero intentional behavior change.
- Documents **LOC risk rules** for files approaching 1000 (supervisor/phases.gleam 688, progress/main.gleam 621, linear_issue_stages.sh 727) — proactive split hygiene before growth.
- Explicitly states **non-goals**.
- Cites AGENTS.md, relevant `spec/parts/`, and prior designs.
- Provides a ready-to-spawn **first implement slice** recommendation + follow-up card titles (do not implement).
- Lists the **regression surface** (tests that must stay green).

Preserve (per AGENTS + prior designs):
- Thin shell conventions in `bin/` and `test/`.
- Every file ≤ 1000 LOC (extract/split proactively).
- `spec/parts/` as canonical source; no spec content edits in design-only (sync optional for index only).
- GitHub remains the default `GRKR_ISSUE_PROVIDER`.
- `process_issue` stays thin sequencer in `bin/grkr`.
- Shared stays in `bin/lib/issue_shared.sh`; do not re-extract or duplicate.
- Heavy orchestration (gh CLI loops, worktree exec, codex context) may stay shell; pure decision/render/message selection/formatting already largely in Gleam (workflow/*, progress/*, templates).
- Provider call sites and external contracts (logs, artifacts, exit codes, gh calls, progress.json) remain identical.

### Non-goals (explicitly out of scope for this design and its children)
- No behavior change to `--issue`, user flags, or GitHub contract.
- `GRKR_ISSUE_PROVIDER` default remains GitHub; no picker/supervisor rewrite.
- No live Linear mutation changes (`GRKR_LINEAR_MUTATE=1` default OFF semantics unchanged).
- Do not touch or grow `linear_issue.sh`, `linear_issue_stages.sh`, or Linear paths except non-regression when a shared boundary is unavoidably exercised.
- Do not re-extract helpers already in `bin/lib/issue_shared.sh`.
- Do not move `process_issue` (thin sequencer) out of `bin/grkr`.
- Do not grow `github_issue.sh` as a dumping ground; slice pure pieces out.
- Do not edit product Gleam or shell logic in the design phase.
- No new public flags or provider switches.
- No smoke e2e creation beyond listing the regression surface.

---

## 2. Current state (cite files + tip)

**What is already Gleam (do not re-port blindly; wire/thin only)**:
- `src/grkr/workflow/`: `decision_gate.gleam`, `implement_stage.gleam`, `test_stage.gleam`, `worktree*`, `task_log*` (core/persist/emit/shard), `decision.gleam`, `main.gleam`, `ffi.gleam`, `handle_comment.gleam`, `resolve_pr.gleam`.
- `src/grkr/progress/`: `checkpoint_*`, `linear_*`, `templates.gleam` (research/plan/decision/issue prompts + default/compact pr bodies + footers + line-limit), `cli.gleam`, `main.gleam`.
- `src/grkr/refusal/*`, `github_picker/*`, `supervisor/*` (phases 688, pick, scheduler, etc), `issue_provider/*`, `task_slug*`, `project_status/*`.
- Thin shell precedent: `bin/grkr-issue-workflow.sh` (68 LOC), `bin/grkr-templates.sh` (62 LOC delegating to progress/templates), `bin/grkr-project-status.sh` (81 LOC), `bin/lib/task_progress.sh`, `bin/lib/refusal_paths.sh`.
- Shared neutral: `bin/lib/issue_shared.sh` (249 LOC) — test-write, line-limit/ensure_publishable, run_codex_prompt, run_progress_cli + marker, attach_issue_logs (complete per design d90fbaf / PR #135–144).
- GitHub path: `bin/grkr` (198 LOC thin launcher + thin `process_issue` sequencer + trap/dispatch); `bin/lib/github_issue.sh` (545 LOC: comment json helpers + ensure_checkpoint + test + publish + pr body + completion + bootstrap + decision/implement stages + finalize).
- Linear path: `bin/lib/linear_issue.sh` (329 LOC thin sequencer); `bin/lib/linear_issue_stages.sh` (727 LOC); `bin/lib/linear_mutate.sh` (guarded).

**Current state of GitHub vertical at tip (re-verified by reading the files)**:
- `bin/grkr`: 198 LOC. Sources doctor + project-status + issue-workflow + refusal_paths + task_progress + **issue_shared** (before providers) + linear_issue + **github_issue** + task-slug + templates. `process_issue` is a thin sequencer delegating to `bootstrap_github_issue_task`, `ensure_checkpoint_stage`, `run_github_decision_stage`, `handle_github_decision_refuse`, `run_github_implement_stage`, `ensure_publishable_file_sizes` (shared), `ensure_test_checkpoint`, `publish_issue_changes`, `finalize_github_issue_complete`.
- `bin/lib/github_issue.sh`: 545 LOC (header documents slices 1–6 of prior GitHub process_issue thinning; now the home of the full GitHub vertical). All gh issue view/comment/edit, "Issue #N: title" headers, "Fixes #N" footers, project moves (via thin grkr-project-status), label "implemented"/"todo", worktree test exec, PR create/edit.
- `bin/lib/issue_shared.sh`: 249 LOC (do not touch for this work).
- GitHub remains default. `GRKR_LINEAR_MUTATE` default OFF.

**Related sizes at tip (re-measured by reading files + prior measurement notes)**:
- `bin/grkr`: 198 LOC
- `bin/lib/github_issue.sh`: 545 LOC ← target
- `bin/lib/issue_shared.sh`: 249 LOC
- `bin/lib/linear_issue.sh`: 329 LOC
- `bin/lib/linear_issue_stages.sh`: 727 LOC (near limit)
- `bin/lib/linear_mutate.sh`: ~62 LOC
- `bin/lib/task_progress.sh`: ~176 LOC (prior)
- `bin/lib/refusal_paths.sh`: ~125 LOC (prior)
- `bin/grkr-issue-workflow.sh`: 68 LOC
- `bin/grkr-templates.sh`: 62 LOC
- `bin/grkr-project-status.sh`: 81 LOC
- `bin/doctor.sh`: 51 LOC (thin)
- `src/grkr/supervisor/phases.gleam`: 688 LOC
- `src/grkr/progress/main.gleam`: 621 LOC

**Source order implications**: `issue_shared.sh` is sourced before `linear_issue.sh` and `github_issue.sh`. Call-time bash resolution continues to work for ambient helpers.

---

## 3. Inventory: every function defined in `bin/lib/github_issue.sh`

Re-verified via direct file read (full 1–540+) + grep for `^name\(\)` definitions + cross-file caller search (primarily self + `bin/grkr` thin sequencer). Numbers approximate body LOC (excludes header comments, blank lines, aliases). Callers listed by surface.

| approx LOC | Function | lines (approx) | Callers (GitHub / Linear / both / launcher) | Gleam overlap / already-delegated? | Notes |
|------------|----------|----------------|---------------------------------------------|------------------------------------|-------|
| 10 | `fetch_issue_comments_json` | 28-36 | internal (ensure_*) | None (gh + jq) | GitHub-only gh comment fetch for resume/restore. |
| 13 | `checkpoint_comment_id_from_json` | 37-51 | internal (ensure_*) | Uses `checkpoint_marker` (shared) | jq marker find; GitHub comment reuse. |
| 12 | `checkpoint_comment_body_from_json` | 52-66 | internal (ensure_*) | Uses `checkpoint_marker` (shared) | jq body restore. |
| 53 | `ensure_checkpoint_stage` | 67-119 | `process_issue` (via grkr) | write_* via `grkr-templates.sh` (Gleam progress/templates); marker + update from shared/task_progress | research/plan reuse/restore/post via gh. GitHub headers only. |
| 28 | `write_test_checkpoint_file` | 121-148 | internal (ensure_test_checkpoint) | Calls `write_test_checkpoint_with_header` (shared) | Thin GitHub wrapper ("Issue #N: title"). |
| ~100 | `ensure_test_checkpoint` | 149-264 | `process_issue` (via grkr) | `run_test_stage_hook` (Gleam via grkr-issue-workflow), `build_command_list` (shared), `write_*_with_header` (shared), marker/progress (shared), worktree exec via `CURRENT_ISSUE_WORKTREE` | Test exec loop + gh post + failed handling. Heavy shell (bash -lc in worktree); command list + header shared. |
| ~40 | `publish_issue_changes` | 267-323 | `process_issue` (via grkr) | `stage_relevant...` / `git_in...` (workflow), `generate_implement_commit_message` (Gleam implement_stage), `check_file_line_limit` (shared), `extract_codex_pr_body` (self), task_log emit (Gleam) | Stage/commit/push/PR/labels. GitHub "Fixes #N" + labels. |
| 2 | `publish_github_issue_changes` | 324-326 | alias | — | Naming parity only. |
| 15 | `ensure_pr_body_limit` | 328-345 | internal (extract_*) | Calls `write_compact_pr_body` / `append_issue_footer` (grkr-templates.sh → Gleam progress/templates) | 60k char + "Fixes #N" footer. |
| 25 | `extract_codex_pr_body` | 346-372 | `publish_issue_changes` | `task_log_is_sharded` + `emit_task_log_stream` (Gleam task_log); falls back to default + limit | PR body from ## section of codex log or default. |
| 15 | `post_completion_comment` | 374-391 | `finalize...` (via grkr) | None (simple heredoc) | GitHub completion summary comment. |
| 2 | `post_github_completion_comment` | 392-394 | alias | — | Naming parity. |
| 30 | `bootstrap_github_issue_task` | 402-433 | `process_issue` (via grkr) | `task_slug_for_issue` (grkr-task-slug thin), `issue_project_item_id` (grkr-project-status thin), `write_task_meta_env` / `write_issue_context_file` / `ensure_task_progress_file` (task_progress) | gh view + globals (TITLE/BODY/URL/BRANCH/CURRENT_ISSUE) + TASK_DIR + progress + meta. |
| 25 | `run_github_decision_stage` | 437-465 | `process_issue` (via grkr) | `prepare_issue_worktree` (workflow), `write_decision_prompt_file` (templates), `run_codex_prompt` (shared), `run_decision_gate` (Gleam workflow/decision_gate) | prepare + codex + gate; sets IMPLEMENTATION_DECISION. |
| 15 | `handle_github_decision_refuse` | 466-480 | `process_issue` (via grkr) | `cleanup_issue_worktree` (workflow), `attach_issue_logs` (shared) | Worktree cleanup + attach when refuse. |
| ~50 | `run_github_implement_stage` | 481-533 | `process_issue` (via grkr) | `move_issue_to_in_progress` (project-status), `write_issue_prompt_file` (templates), `run_codex_prompt` (shared), `detect_implementation_refusal` / `normalize...` / `extract...` / `handle_implementation_refusal` (refusal_paths + decision), `mark_task_progress_refused` (task_progress) | in-progress + implement codex + full impl-to-refusal conversion path (sets GITHUB_IMPL_REFUSED). |
| 10 | `finalize_github_issue_complete` | 534-541 | `process_issue` (via grkr) | `mark_task_progress_complete` (task_progress), `move_issue_to_done` (project-status), `post_completion_comment` (self), attach (shared) | mark + optional move warn + post + attach. |

**Top-level launcher-only surface (stays in grkr)**:
- `process_issue` (thin sequencer), `resolve_script_path`, `usage`, `cleanup_on_exit` + trap, flag/MODE parse, --project watcher loop, sourcing, logging pipe.

**Call graph notes (GitHub happy path post shared + thin sequencer)**:
`process_issue` → bootstrap (lib) → ensure research/plan (lib, gh comments) → run_decision (shared codex + Gleam gate) → (proceed) run_implement (lib + codex + refusal conversion if needed) → ensure_publishable (shared) → ensure_test (lib + shared write/header + worktree exec + gh) → publish (lib + Gleam commit hook + task_log + templates) → finalize (mark + move + post + attach shared).

Refusal and impl-refusal paths route through refusal_paths + decision_gate (Gleam) + attach (shared).

**Gleam overlap notes**:
- Heavy reuse of existing: `run_codex_prompt` / marker / progress / attach now shared; decision_gate / implement_stage commit msg / test_stage hook / task_log emit / worktree / templates / task_progress / project-status all Gleam or thin delegates.
- PR body path is hybrid: extract/limit in shell, but default/compact/footer + sharded emit already delegate to Gleam.
- Pure-ish candidates for next extract: PR body limit + codex section selection logic; completion summary render; possibly comment json marker selection if a pure decoder is justified.
- gh CLI, jq comment parsing, bash worktree exec loops, label/project moves via thin sh, and ambient globals (CURRENT_*, BRANCH, etc) stay shell by pattern.

---

## 4. Target module map + ownership boundaries

**Guiding principle**: `github_issue.sh` remains the focused **GitHub vertical** (mirrors `linear_issue*.sh` pattern). Keep gh-exec, comment jq, test exec loops, publish orchestration, GitHub-specific headers/footers/labels, bootstrap globals, and thin stage sequencers here. Extract only **pure or near-pure** formatting/selection helpers to Gleam (following templates + workflow precedent). Never grow provider files as shared dumping grounds. `process_issue` stays thin in grkr. `issue_shared.sh` is frozen for this work.

**Preferred locations**:
- `bin/lib/github_issue.sh` (keep, focused): all current fns that are gh-specific or orchestrate gh + shared/Gleam. Add thin aliases or one-line delegates only when extracting pure body.
- `src/grkr/workflow/` or `src/grkr/progress/`: pure helpers for PR body construction (ensure limit + extract logic, selection of ## section), completion summary render, or future github_process facade. Extend `progress/templates.gleam` or add `workflow/publish.gleam` / `pr_body.gleam` if a CLI entry + thin sh (or direct gleam run) fits the established pattern (see grkr-templates.sh, grkr-issue-workflow.sh).
- Keep forever in launcher (`bin/grkr`): thin `process_issue` sequencer + launcher surface + trap.
- Existing correct: `issue_shared.sh` (all cross-provider already extracted), `grkr-issue-workflow.sh`, `grkr-templates.sh`, `task_progress.sh`, `refusal_paths.sh`.
- Provider ownership:
  - GitHub owns: gh issue/pr ops, "Issue #N"/"Fixes #N", labels, project status via thin adapter, comment json jq for GitHub resume, test exec in CURRENT_ISSUE_WORKTREE context for GitHub path, all ensure_*/run_github_*/finalize_* + publish_* in this file.
  - Linear owns: its identifier wording, no-labels PR body, linear-* branch, mutation planning (in stages + mutate), its ensure_linear_*.
  - Shared (already extracted; header-param or provider-agnostic): write_test..._with_header, build_command_list, ensure_publishable..., run_codex..., run_progress..., checkpoint_marker, attach_issue_logs, stage_*/git_in_*, persist_task_log, generate_*_commit_message, run_*_stage_hook, mark_*, etc.
- Proposed concrete new / extension files (only when a slice justifies; small):
  - Extend `src/grkr/progress/templates.gleam` or `src/grkr/workflow/publish.gleam` (or pr_body helpers) for GitHub PR body limit + codex extract logic (pure String → String after log content).
  - Thin delegate update in `bin/grkr-templates.sh` or a small new `bin/grkr-github-publish.sh` only if needed for CLI surface (prefer direct reuse or minimal addition).
- LOC discipline: if any file would exceed ~950, split/extract first. Shared that both providers use must already be in issue_shared (it is).

---

## 5. Ordered slice table (smallest first)

Each slice acceptance:
- Files ≤1000 LOC (block if any touched file would exceed ~950 without prior extract/split).
- `gleam build` + `gleam test` + `npm test` green.
- GitHub smoke suite green (`grkr-smoke.sh`, `checkpoint-resume`, `refusal`, `implementation-to-refusal`, `line-limit`, `pr-body-limit`, `progress-cli`, dirty/branch/init/installed).
- Linear regression green as non-regression (implement, refuse-progress, mvp, apply-matrix) when shared boundary exercised.
- Zero intentional behavior change (identical logs, gh calls, artifacts, PR bodies with Fixes, progress stages, exit codes, worktree state).
- README + docs/gleam-migration "Next product thinning" pointer updated (per AGENTS) on functional slices.
- GitHub vertical only; no Linear feature work.

| Title | Primary files | Deps / shared ambient | Acceptance | Est. LOC delta (net) |
|-------|---------------|-----------------------|------------|----------------------|
| PR body helpers thinning (ensure_pr_body_limit + extract_codex_pr_body) | `src/grkr/progress/templates.gleam` (extend) or new `workflow/pr_body.gleam`, thin delegate in `bin/grkr-templates.sh` or direct, `bin/lib/github_issue.sh` (replace bodies with delegate) | task_log emit (already), write_default/compact + append (already in templates), MAX_PR_BODY_CHARS | GitHub PR body (compact + Fixes #N) identical for happy + oversized paths; `grkr-pr-body-limit.sh` + smoke + publish path green; no behavior change; Linear untouched | +30–60 Gleam; –20–30 in github_issue.sh |
| Checkpoint comment json helpers (optional; low-ROI) | **NO-GO** — leave shell jq; see [`docs/design-checkpoint-json-gleam.md`](design-checkpoint-json-gleam.md) (t_556cf107) | `checkpoint_marker` (shared) | Resume/restore for research/plan/test unchanged; no product extract | 0 |
| Test checkpoint exec surface polish (if blast justifies) | `github_issue.sh` (internal split) | shared build/write + run_test_stage_hook | Test.md + failed/pass paths + gh post identical; line-limit + smoke green | 0 net (refactor only) |
| Completion surface polish (post + summary render) | Gleam render + thin in github_issue | templates pattern | Completion comment identical; smoke green | small |
| (Hygiene parallel) Supervisor/phases + progress/main LOC split risk | `src/grkr/supervisor/phases.gleam` (split e.g. by phase or scan/reap/cleanup), progress/main if grows | none for pure hygiene | No behavior change; build/test green; files stay <<1000 with headroom | hygiene only |
| Later pure Gleam github_process facade (after above) | `src/grkr/workflow/github_process.gleam` or publish, thin call from github_issue | existing hooks | Parity proven on shell thin first; optional | later |

Slices are independent where possible; PR body slice has dedicated test coverage and reuses existing Gleam template surface, making it smallest high-signal first.

---

## 6. LOC risk plan (files ≥600)

- `src/grkr/supervisor/phases.gleam` (688): Approaching limit. Propose parallel hygiene slice (not mixed into first GitHub product extract): split by concern (e.g. `phases/sync.gleam`, `phases/scan_comment.gleam`, `phases/pick_schedule.gleam`, `phases/reap.gleam`, `phases/cleanup.gleam`, keep thin dispatcher in phases.gleam). Do before any growth. Include in follow-up card titles.
- `src/grkr/progress/main.gleam` (was 621/644): hygiene split landed (this PR): 63 thin facade + checkpoint_plan/linear_plan/templates_cli/linear_apply (all <<250); see gleam-migration update.
- `bin/lib/linear_issue_stages.sh` (727): Explicitly out of scope for GitHub work. If any unavoidable shared touch forces growth, extract first per prior rules (neutral before provider). GitHub slices must not touch it.
- `bin/lib/github_issue.sh` (545): Target remains well under 500 after slices; split internal large fns (e.g. ensure_test_checkpoint) if a slice would push it near 600.
- Rule (AGENTS + priors): extract/split before landing any change that would exceed ~950. Prefer concern-split modules over monoliths.

---

## 7. Regression surface (tests that must stay green)

All must pass with identical behavior after every slice:

**GitHub-specific / smoke (must)**:
- `test/grkr-smoke.sh` (happy path to PR + complete comment)
- `test/grkr-checkpoint-resume.sh` (research/plan/test resume from markers)
- `test/grkr-refusal.sh` (decision-gate refusal + checkpoint + progress)
- `test/grkr-implementation-to-refusal.sh` (during-impl refusal conversion)
- `test/grkr-line-limit.sh` (remediation + publish abort)
- `test/grkr-pr-body-limit.sh` (compact PR body + Fixes footer)
- `test/grkr-progress-cli.sh` (marker + progress)
- `test/grkr-dirty-worktree-warning.sh`, `test/grkr-branch-exists.sh`, `test/grkr-init.sh`, `test/grkr-installed-layout.sh`

**Cross-cutting**:
- `npm test` (shell harness)
- `gleam test` + `gleam build` clean on every slice

**Linear (non-regression only; untouched unless shared boundary)**:
- `test/grkr-linear-issue-implement.sh`, `grkr-linear-refuse-progress.sh`, `grkr-linear-issue-mvp.sh`, `grkr-linear-apply-matrix.sh`

No new e2e; reuse fixtures + gh stubs. Zero behavior change on gh calls, PR bodies, test.md, progress.json, exit codes.

---

## 8. Spec refs + AGENTS constraints

**Must read for implementers**:
- `spec/parts/17-issue-workflow-overview.md`
- `spec/parts/22-stage-3-implement-or-refuse-decision-gate.md`
- `spec/parts/23-refusal-flow.md`
- `spec/parts/25-stage-4-implement.md`
- `spec/parts/26-stage-5-test.md`
- `spec/parts/31-test-checkpoint.md`
- `spec/parts/32-detailed-issue-workflow-pseudocode.md`
- `spec/parts/08-worker-scripts.md`
- `spec/parts/15-phase-3-detect-and-process-robot-comments.md` (if comment path touched)
- `spec/parts/38-acceptance-criteria.md`
- `spec/parts/39-recommended-implementation-order.md`
- AGENTS.md (≤1000 LOC, thin bin/, update README after func change, spec/parts canonical, GitHub default, shared delegates, preserve shell conventions, run sync-spec only if parts touched)
- Prior designs: `docs/design-grkr-shared-helpers-extract.md`, `docs/design-github-process-issue-thinning.md` (+ Linear thinning designs for pattern)

Existing design style to mirror: goal/non-goals, current state with tip + LOC table, full function inventory + callers + Gleam notes, target module map + ownership, ordered slice table with acceptance, LOC risk, explicit non-goals, regression surface, paste-ready card brief.

---

## 9. Recommended first implement slice + rationale

**First slice**: Thin PR body helpers (`ensure_pr_body_limit` + `extract_codex_pr_body`) from `bin/lib/github_issue.sh` into Gleam (extend `progress/templates.gleam` or add focused `workflow/publish_helpers.gleam` / pr body logic) + thin delegate (or direct gleam run pattern) + replace bodies in github_issue.sh.

**Rationale**:
- Smallest, high-signal, dedicated regression test (`grkr-pr-body-limit.sh`).
- Already hybrid: default/compact/footer + sharded emit live in Gleam templates + task_log. The limit check + codex ## selection + footer append are the remaining shell glue.
- Matches prior forward-looking "pure Gleam github process surface" in design-github-process-issue-thinning.md.
- Zero gh side-effects in the extracted surface; publish path exercised safely.
- GitHub regressions (smoke, pr-body, line-limit, checkpoint-resume) cover it fully; Linear untouched.
- Creates precedent for further pure extracts without touching shared or Linear.
- Leaves heavy gh loops and test exec in github_issue.sh (appropriate).

See §11 for paste-ready card title + `/goal` brief.

Follow-up slices follow the ordered table (comment helpers if value, completion polish, hygiene splits for phases.gleam etc).

---

## 10. Follow-up implement card titles (ready to spawn; do not implement here)

- "Thin checkpoint comment json helpers (fetch + id/body from json) if pure surface justified"
- "Polish completion surface (post + summary render) to Gleam + thin in github_issue.sh"
- "Internal hygiene split of large fns inside github_issue.sh (e.g. ensure_test_checkpoint)"
- "LOC hygiene: split supervisor/phases.gleam (688) before 1000 (parallel, non-mixed)"
- "Optional: pure Gleam github_process / publish facade after shell vertical is thin"

Factory can spawn in order after first lands and is verified.

---

## 11. Paste-ready first implement card brief with /goal

```
/goal Thin PR body helpers (ensure_pr_body_limit + extract_codex_pr_body) from bin/lib/github_issue.sh to Gleam (extend progress/templates or focused workflow publish helper) + thin delegate while keeping external contract 100% identical for --issue (compact PR body + Fixes #N footer, oversized handling). GitHub pr-body-limit + smoke + publish regressions green; Linear untouched. github_issue.sh net thinner; no behavior change.

Context: tip 9a1b8f6 (docs #145 after product c801967 / PR #144 shared complete). bin/grkr 198 thin launcher; github_issue.sh 545 largest remaining GitHub vertical after process_issue thin (a3d9702 / #121) + shared helpers (d90fbaf design + slices 136–144). PR body already delegates to Gleam templates (write_default/compact/append) + task_log emit; limit + codex ## selection remain in shell. grkr-pr-body-limit.sh dedicated coverage. github_issue.sh owns GitHub vertical (gh + "Fixes #N" + labels); issue_shared frozen; Linear untouched.

Read (must):
- AGENTS.md (≤1000, thin bin/, shared delegates, GitHub default, update README on func change, spec canonical)
- spec/parts/17-issue-workflow-overview.md, 25-implement.md, 26-test.md, 31-test-checkpoint.md, 32-pseudocode, 38-acceptance, 39-recommended..., 08-worker-scripts.md
- docs/design-grkr-shared-helpers-extract.md + docs/design-github-process-issue-thinning.md + this design
- bin/grkr (thin process_issue call to publish + finalize)
- bin/lib/github_issue.sh (full publish/extract/ensure_pr_body + call sites + header)
- bin/grkr-templates.sh + src/grkr/progress/templates.gleam (existing default/compact/footer renders)
- src/grkr/workflow/task_log* (emit_task_log_stream + is_sharded)
- test/grkr-pr-body-limit.sh, grkr-smoke.sh, grkr-line-limit.sh, grkr-checkpoint-resume.sh + other GitHub smokes (must stay green)
- src/grkr/progress/cli.gleam + main (pattern for CLI bridges)

Acceptance (one PR):
- GitHub --issue publish path produces identical PR body (default or compact + "Fixes #N" footer exactly once) and handles >60k the same way.
- grkr-pr-body-limit.sh + smoke + refusal/implement-to-refusal + line-limit + checkpoint-resume all green with zero diff in artifacts/calls/exit codes.
- New Gleam surface + thin delegate (or direct) in github_issue.sh; provider call site unchanged.
- No file >1000 LOC; github_issue.sh net thinner or neutral; headroom preserved.
- gleam build + gleam test + npm test green.
- README + docs/gleam-migration "Next product thinning" note added (per AGENTS).
- Zero behavior change to user flags, contracts, PRs, or mutate defaults.
- No Linear / supervisor / picker changes.

Non-goals: comment json extract, test exec loop, completion, any Linear work, new flags, spec edits, process_issue move, shared re-touch.

Use Grok Build CLI --mode implement (or full). After changes run gleam build + relevant tests + the listed regression shells. Follow AGENTS exactly.
```

---

## 12. Acceptance for THIS design card

- Design doc exists at `docs/design-github-issue-lib-thinning.md` with:
  - Full current-tip SHAs + LOC table for bin/grkr + ALL bin/lib/*.sh + related thin shells + key Gleam files approaching limits.
  - Full function inventory of github_issue.sh with approx LOC, callers (GitHub vs others), Gleam overlap notes.
  - Target module map — GitHub vertical ownership, what stays shell (gh/exec), what extracts to Gleam (pure PR body etc), boundaries vs issue_shared/linear.
  - Ordered slice table (smallest first) with per-slice acceptance.
  - Explicit LOC risk plan for ≥600 files (phases.gleam, progress/main, linear_stages) with proactive split guidance.
  - Explicit non-goals (no behavior change; GitHub default; Linear mutate OFF; process_issue KEEP; shared frozen; design-only).
  - Regression surface list (all listed GitHub smoke + pr-body + Linear matrix non-regression).
  - Recommended first slice clearly called out with rationale.
  - Follow-up card titles listed.
  - Paste-ready implement brief with /goal.
- Optional (docs-only, safe): one-line pointer in `docs/gleam-migration.md` "Next product thinning" section pointing at this design (recommended follow-up).
- No product code or behavior changes in `bin/`, `src/`, or `test/`.
- `git status --porcelain` (ignoring pre-existing untracked `.grkr/*`) shows only the new design doc (and optional one-line docs pointer if performed).

---

**End of design document.**

Next: kanban factory spawns the first implement card using the brief in §11. Implement worker writes self-contained prompt (this design + listed files + AGENTS + spec parts), runs Grok Build CLI `--mode implement`, verifies `gleam build` / tests / regression shells, and completes the card. Subsequent slices follow the table. Parallel hygiene card for supervisor/phases.gleam split can be independent.

**Design-only — no product code was edited.**
