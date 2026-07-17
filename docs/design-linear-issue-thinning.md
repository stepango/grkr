# Design: Linear `linear_issue.sh` Thinning (near 1000 LOC limit)

**Status**: Design-only (plan agent). No product code edits.  
**Reference tip**: origin/main docs tip **bdf396b** (docs tip-sync after product **a3d9702** / PR #121 thin process_issue orchestrator).  
**Prior design artifacts**: `docs/design-github-process-issue-thinning.md` (complete; GitHub path now thin), `docs/design-linear-publish-stage.md`, `docs/design-linear-test-stage.md`, `docs/design-linear-implement-stage.md`, `docs/design-linear-live-mutate.md`.  
**Gap addressed**: `bin/lib/linear_issue.sh` ~923 LOC (near AGENTS.md hard 1000 LOC limit). GitHub `process_issue` thinning is complete (`bin/grkr` 435 LOC thin launcher; `bin/lib/github_issue.sh` 539 LOC). Docs already state: extract shared before any Linear growth. This design inventories the Linear path and proposes ordered, shippable extract slices (shared-neutral first, then Linear-only vertical chunks) while preserving zero behavior change.  
**Date**: 2026-07-16

---

## 1. Goal / non-goals

### Goal
Produce `docs/design-linear-issue-thinning.md` that:

- Inventories **every function** in `bin/lib/linear_issue.sh` (name, approx LOC, callers, Gleam overlap / already-delegated).
- Proposes a **target module map + ownership boundaries** (prefer shared-neutral `bin/lib/*.sh` already used by GitHub + thin Linear-only surface; optional pure Gleam under `src/grkr/workflow/*` or progress for pure formatters later).
- Defines **ordered slice table** of shippable PRs (smallest first) with per-slice acceptance: files stay ≤1000 LOC, `gleam build` + `gleam test` + `npm test` green, Linear `--linear-issue` regression green (implement + refuse + MVP + apply-matrix), GitHub smoke suite green when shared helpers are touched.
- Documents **LOC risk rules** (block slice if `linear_issue.sh` would exceed ~950 without extract first; also cite `github_issue.sh` ~539, `grkr` ~435).
- Explicitly states **non-goals**.
- Cites spec refs and AGENTS.md constraints.
- Provides a ready-to-spawn **first implement slice** recommendation + follow-up card titles (do not implement here).
- Lists the **regression surface** (tests that must stay green).
- Includes a **paste-ready first implement card brief** with `/goal`.

Preserve (per AGENTS + prior designs):
- Thin shell conventions in `bin/`.
- Every file ≤ 1000 LOC (extract helpers early; prefer split before growth).
- `spec/parts/` as canonical source; no spec content edits in design-only (sync optional for index only).
- Prefer **shared thin delegates** over duplicating logic or growing provider-specific files without prior neutral extraction.
- Heavy orchestration (codex exec, gh CLI, bash loops, worktree context) may stay shell initially; pure/decision/render/message formatting already largely in Gleam.
- GitHub remains the default `GRKR_ISSUE_PROVIDER`.
- Linear and GitHub call sites stay separate; shared code is header-parameterized or provider-agnostic helpers only (example: `write_test_checkpoint_with_header`).
- `bin/lib/linear_mutate.sh` (~62 LOC) remains the guarded apply surface only.

### Non-goals (explicitly out of scope for this design and its children)
- No behavior change to user-facing flags, commands, `--linear-issue` contract, or mutation defaults.
- `GRKR_ISSUE_PROVIDER` default remains GitHub; no picker/supervisor rewrite.
- No live Linear mutation changes (dry-run + guarded `GRKR_LINEAR_MUTATE=1` semantics unchanged).
- Do not grow `bin/lib/linear_issue.sh` without prior shared extraction to a neutral lib.
- Do not move Linear concerns into `github_issue.sh` or vice-versa.
- Do not rewrite `process_linear_issue` as a pure Gleam sequencer in this work (optional later only after shell thin).
- Do not edit product Gleam or shell logic in the design phase.
- No new public flags or provider switches.
- No smoke e2e beyond design inventory and regression listing.

---

## 2. Current state (cite files + tip)

**What is already Gleam (do not re-port blindly; wire/thin only)**:
- `src/grkr/workflow/`: `decision_gate.gleam`, `implement_stage.gleam`, `test_stage.gleam`, `worktree*`, `task_log*`, `decision.gleam`, `main.gleam`, `ffi.gleam`, `handle_comment.gleam`, `resolve_pr.gleam`.
- `src/grkr/progress/`: `checkpoint_*`, `linear_*`, `templates.gleam`, `cli.gleam`, `main.gleam`.
- `src/grkr/refusal/*`, `issue_provider/*`, `linear/*`, `project_status/*`, `supervisor/*`, `github_picker/*`, `sync_main/*`, `task_slug*`.
- Thin shell: `bin/grkr-issue-workflow.sh` (~68-80 LOC thin Gleam delegate), `bin/grkr-templates.sh` (~62 LOC), `bin/grkr-project-status.sh` (~81 LOC).
- Shared thin libs: `bin/lib/task_progress.sh` (176 LOC), `bin/lib/refusal_paths.sh` (125 LOC).
- GitHub path fully thinned: `bin/grkr` 435 LOC (thin launcher + sequencer); `bin/lib/github_issue.sh` 539 LOC (test, publish, research/plan checkpoints, completion, bootstrap/decision/implement/finalize stages).

**Current thick shell in `bin/lib/linear_issue.sh`** (measured at tip; see §3 for detailed inventory):
- Owns the entire Linear `--linear-issue` orchestration: `process_linear_issue` (~182 LOC body) + 6 `ensure_linear_*` functions + meta/progress writers + mutation planning + publish complete.
- Total ~923 LOC (near hard 1000 limit per AGENTS.md).
- Reuses many shared thin delegates (see "Shared ambient" below).
- Never calls GitHub label edits or issue comments for Linear items.
- `process_linear_issue` mirrors the GitHub tail but with Linear header wording ("Linear issue ID: title"), no Fixes footer, dry-run Linear mutation planning (`linear-comment-mutation`, `linear-state-mutation`, `plan-linear-refusal`), and optional guarded apply via `linear_mutate.sh`.

**GitHub path at tip (post a3d9702 / PR #121)**:
- `bin/grkr` is now a thin launcher/sequencer.
- GitHub-specific bodies live in `bin/lib/github_issue.sh` (bootstrap, decision stage, implement stage + impl-refusal conversion, research/plan/test/publish/complete).
- Shared helpers remain in `bin/grkr` or `bin/lib/*.sh` when truly cross-provider (e.g. `ensure_publishable_file_sizes`, `run_codex_prompt`, `attach_issue_logs`).

**Linear path flow (high-level, post publish+complete + guarded mutate)**:
1. `bin/grkr` dispatch on `--linear-issue` → `process_linear_issue "$LINEAR_ISSUE_ID"`.
2. `load_linear_issue_assignments` (via `run_issue_provider_cli` → `issue_provider/main fetch-issue`).
3. Write `meta.env`, `issue-context.json`, seed `progress.json` (provider=linear).
4. `ensure_linear_checkpoint_stage` research + plan (write local .md + plan Linear comment mutation dry-run; optional guarded apply).
5. `prepare_issue_worktree` (linear-$TASK_SLUG branch).
6. Decision prompt + `run_codex_prompt` + `run_decision_gate` (provider-aware; refuse delegates to `linear_flow`).
7. Refuse: `ensure_linear_refusal_checkpoint` (plans comment + Backlog state) → cleanup → return.
8. Proceed: `ensure_linear_implement_in_progress` (plans "In Progress" state mutation).
9. Implement codex → `implementation.log`.
10. `detect_implementation_refusal` → `ensure_linear_refusal_checkpoint` conversion path if needed.
11. `ensure_linear_test_checkpoint` (reuses `build_command_list` / `run_test_stage_hook` / `write_test_checkpoint_with_header` with Linear header; plans test comment + "In Review" state).
12. `ensure_linear_publish_complete` (reuses `ensure_publishable_file_sizes`, `stage_relevant*`, `generate_linear_implement_commit_message`, `extract_linear_codex_pr_body`; gh pr create/edit; `mark_task_progress_complete`; plans complete comment + Done state).
13. Echo `STAGE=complete`; emit TASK_DIR / WORKTREE.

**Shared ambient already used by Linear (stay shared / do not duplicate)**:
- `prepare_issue_worktree`, `stage_relevant_issue_files`, `ensure_publishable_file_sizes`, `check_file_line_limit`, `collect_file_line_limit_violations`, `git_in_issue_context`.
- `run_codex_prompt`, `run_decision_gate`, `detect_implementation_refusal`, `persist_task_log_output`.
- `build_command_list`, `run_test_stage_hook`, `write_test_checkpoint_with_header`, `cleanup_test_result_logs`.
- `mark_task_progress_complete`, `mark_task_progress_failed`, `mark_task_progress_refused`, `update_task_progress_stage`, `ensure_task_progress_file`.
- `run_progress_cli`, `checkpoint_marker`.
- `generate_linear_implement_commit_message`, `extract_linear_codex_pr_body` (Linear-specific templates).
- `maybe_apply_linear_mutation` (from `bin/lib/linear_mutate.sh` ~62 LOC).
- `bin/lib/task_progress.sh` (~176 LOC), `bin/lib/refusal_paths.sh` (~125 LOC), `bin/grkr-issue-workflow.sh` (~68-80 LOC thin), `bin/grkr-templates.sh`.

**Related sizes at tip**:
- `bin/grkr`: 435 LOC
- `bin/lib/github_issue.sh`: 539 LOC
- `bin/lib/linear_mutate.sh`: 62 LOC
- `bin/lib/task_progress.sh`: 176 LOC
- `bin/lib/refusal_paths.sh`: 125 LOC

---

## 3. Inventory: EVERY function in `bin/lib/linear_issue.sh`

Pre-measured at tip (verify/refine; numbers approximate body LOC). All functions are defined in this single file.

| approx LOC | Function | lines (approx) | Callers | Gleam overlap / already-delegated? | Notes |
|-----------|----------|----------------|---------|------------------------------------|-------|
| 11 | `linear_issue_project_root` | L8-L18 | Internal (run_issue_provider_cli) | None | Resolves GRKR_GLEAM_PROJECT_ROOT or SCRIPT_DIR parent. |
| 13 | `run_issue_provider_cli` | L19-L31 | `load_linear_issue_assignments` | Delegates to `gleam run -m grkr/issue_provider/main` | Thin bridge; fixture/live via LINEAR_FIXTURE_PATH or token. |
| 39 | `decode_shell_assignment_value` | L32-L70 | `load_linear_issue_assignments` | Mirrors Gleam shell_quote decode (multi-line bodies via \n) | Pure string util; potentially reusable but currently Linear-wire specific. |
| 64 | `load_linear_issue_assignments` | L71-L134 | `process_linear_issue` | Uses run_issue_provider_cli | Sets globals: FOUND, ISSUE_ID, ISSUE_IDENTIFIER, ISSUE_TITLE, ISSUE_DESCRIPTION, ISSUE_URL, ISSUE_STATE, ISSUE_STATE_ID, ISSUE_PRIORITY, ISSUE_UPDATED_AT, JOB_KEY, TASK_SLUG, ERROR. |
| 20 | `write_linear_task_meta_env` | L135-L154 | `process_linear_issue` | None (Linear-shaped meta) | Writes PROVIDER=linear + identifier/id/slug/branch/url. |
| 42 | `ensure_linear_task_progress_file` | L155-L196 | `process_linear_issue` | Reuses `timestamp_utc` (task_progress) + jq | Seeds provider=linear progress.json with research/plan/implement_or_refuse/test pending. |
| 60 | `ensure_linear_checkpoint_stage` | L197-L256 | `process_linear_issue` | Uses `write_research_checkpoint_file`, `write_plan_checkpoint_file` (templates), `run_progress_cli linear-comment-mutation`, `maybe_apply_linear_mutation`, `update_task_progress_stage` | Research/plan only; writes local .md + plans Linear mutation + optional guarded apply. Resume-safe. |
| 117 | `ensure_linear_refusal_checkpoint` | L257-L373 | `process_linear_issue` (decision + impl-refusal), `test/grkr-linear-refuse-progress.sh` (direct) | Uses `run_progress_cli plan-linear-refusal / render-refusal / linear-comment-mutation / linear-state-mutation`, `mark_task_progress_refused`, `maybe_apply` | Full refuse path: refusal.md + comment + (optional) Backlog state; plan file + dumps; soft by default. |
| 58 | `ensure_linear_implement_in_progress` | L374-L431 | `process_linear_issue` | Uses `run_progress_cli linear-state / linear-state-mutation`, `update_task_progress_stage`, `maybe_apply` | Plans "In Progress" state mutation (default or LINEAR_STATE_IMPLEMENTATION_ID); marks implement_or_refuse=done. |
| 159 | `ensure_linear_test_checkpoint` | L432-L590 | `process_linear_issue` | Reuses `run_test_stage_hook`, `build_command_list`, `write_test_checkpoint_with_header` (Linear header), `run_progress_cli linear-comment-mutation + linear-state-mutation (test)`, `cleanup_test_result_logs`, `mark_task_progress_failed`, `checkpoint_marker` | Exec BUILD/TEST in worktree; writes test.md; plans test comment + "In Review" state; updates stages.test=done\|failed. Resume-safe. Largest chunk. |
| 151 | `ensure_linear_publish_complete` | L591-L741 | `process_linear_issue` | Reuses `ensure_publishable_file_sizes`, `stage_relevant_issue_files`, `git_in_issue_context`, `check_file_line_limit`, `generate_linear_implement_commit_message`, `extract_linear_codex_pr_body`, `mark_task_progress_complete`, `run_progress_cli linear-comment-mutation (pr_summary) + linear-state-mutation (complete)`, `maybe_apply` | Sizes + commit/push/PR (linear-* branch, no Fixes footer, no labels) + complete comment FIRST then Done state. No gh issue edits. |
| 182 | `process_linear_issue` | L742-L923 | `bin/grkr` (only entry for --linear-issue) | Orchestration only; delegates to all above + shared ambient (prepare_issue_worktree, run_codex_prompt, run_decision_gate, detect_implementation_refusal, etc.) | Full sequencer: load → meta/progress → research/plan → worktree → decision → refuse-or-proceed → implement → impl-refusal-or-test → publish+complete. Thin sequencer target after extracts. |

**Call graph summary (Linear happy path)**:
`process_linear_issue` → load + write_meta + ensure_task_progress → ensure_checkpoint (research) → ensure_checkpoint (plan) → prepare_worktree → run_codex + run_decision_gate → (proceed) ensure_linear_implement_in_progress → run_codex implement → (no refusal) ensure_linear_test_checkpoint → ensure_linear_publish_complete → STAGE=complete.

Refusal paths (decision gate or during-impl) call `ensure_linear_refusal_checkpoint` (with optional state_id).

**Test direct callers**:
- `test/grkr-linear-refuse-progress.sh`: sources linear_issue.sh + task_progress.sh and calls `ensure_linear_refusal_checkpoint` directly (with seeded progress).

---

## 4. Target module map + ownership boundaries

**Guiding principle**: Keep `linear_issue.sh` under ~950 LOC (extract before growth). Prefer shared-neutral extraction for any utility both providers could (or already do) use. Keep Linear-only mutation planning, Linear header wording, Linear state/comment orchestration in the Linear surface. `bin/grkr` remains the single entry that sources doctor + thin libs + dispatches.

**Preferred locations (in order)**:
1. **Shared-neutral helpers** (both providers use or could use without provider-specific headers/footers): extract to `bin/lib/*.sh` (examples: `decode_shell_assignment_value` if a neutral shell-unquote proves reusable across wire protocols; git/codex context helpers if they emerge as pure; do **not** duplicate existing shared like `write_test_checkpoint_with_header` or `build_command_list`).
2. **Linear-only vertical chunks** after shared hygiene: move largest pure bodies (`ensure_linear_test_checkpoint`, `ensure_linear_publish_complete`, `ensure_linear_refusal_checkpoint`) into a sibling lib (e.g. `bin/lib/linear_issue_stages.sh` or keep stages co-located but extract from the main sequencer file). `process_linear_issue` becomes a thin sequencer that calls the extracted fns.
3. **Thin `bin/lib/linear_issue.sh`**: retains `process_linear_issue` (bootstrap + decision + refuse/implement + test + publish sequence), `load_linear_issue_assignments` / meta / progress seed, and thin wrappers that delegate to the sibling stage lib.
4. **Keep `bin/lib/linear_mutate.sh`** (~62 LOC) as the guarded apply surface only. It is already separated and should not absorb planning logic.
5. **Optional pure Gleam later** (only after shell is thin): pure formatters or renderers can move to `src/grkr/progress/*` or `src/grkr/workflow/*` (e.g. if a Linear-specific PR body fragment or checkpoint body is provably pure and has no shell side effects). Most formatters are already in progress/templates or workflow. Do not force Gleam ports for shell-heavy loops.
6. **Do not**: move Linear concerns into `github_issue.sh`; duplicate shared helpers; rewrite supervisor/picker; alter `GRKR_ISSUE_PROVIDER` default.

**Ownership boundaries (Linear vs GitHub)**:
- Linear owns: `issue_provider/main fetch-issue` wire (KEY=val shell assignments), "Linear issue ID: title" headers, no # on identifiers, no "Fixes #N", PR from `linear-$SLUG` branch (acceptable), Linear state/comment mutation planning (`linear-state*`, `linear-comment-mutation`, `plan-linear-refusal`), `process_linear_issue` tail, `ensure_linear_*` bodies.
- GitHub owns: gh issue view / comment / edit labels, "Issue #N: title", "Fixes #N" footer, project moves via grkr-project-status, `process_issue` / `ensure_*` / `publish_*` for GitHub.
- Shared (already or to be): `write_test_checkpoint_with_header`, `build_command_list`, `run_test_stage_hook`, `ensure_publishable_file_sizes`, `stage_relevant_issue_files`, `git_in_issue_context`, `run_codex_prompt` + persist, `run_decision_gate`, `detect_implementation_refusal`, `mark_task_progress_*`, `checkpoint_marker`, `run_progress_cli`, `prepare_issue_worktree`, `cleanup_test_result_logs`.

**Concrete proposed files (small slices only)**:
- `bin/lib/linear_issue.sh` (thin sequencer + load/meta after extracts).
- `bin/lib/linear_issue_stages.sh` (or focused `linear_checkpoints.sh` / `linear_publish.sh`) when vertical chunks are extracted.
- No new Gleam modules required for first slices (shell thin first).

**LOC discipline**: If `linear_issue.sh` would exceed ~950 LOC during a change, extract a focused helper lib first (AGENTS rule). Same rule applies to `github_issue.sh` (~539) and `grkr` (~435).

---

## 5. LOC risk rules

`bin/lib/linear_issue.sh` is at ~923 LOC and owns the entire Linear `--linear-issue` orchestration.

**Mandatory rules before any Linear growth**:
- If a change would push `linear_issue.sh` >~950 LOC, **extract first** (block the slice).
- Shared helpers that both providers use (or will use) **must** be extracted to a neutral location **before** being added to either `*_issue.sh`.
  - Current good examples: `task_progress.sh`, `write_test_checkpoint_with_header`, `build_command_list`, `run_test_stage_hook`, `stage_relevant_issue_files`, `ensure_publishable_file_sizes`, `run_codex_prompt`, `run_decision_gate`, `detect_implementation_refusal`, `mark_task_progress_*`, `checkpoint_marker`, `run_progress_cli`.
- When a helper is only Linear-specific (Linear identifier wording, Linear state/comment mutation planning, no-labels PR body, "Linear issue ID: title"), keep in linear_issue (or extracted Linear-only sibling).
- When a helper is only GitHub-specific (gh labels, "Fixes #N", "Issue #N" header, project moves), it belongs in `github_issue.sh` or grkr — do not put in linear_issue.sh.
- Prefer adding a 1-line thin wrapper in the provider lib that calls a shared fn in `bin/lib/` or delegates to Gleam rather than copying bodies.
- `bin/grkr` itself must not grow past ~950 without extraction.

**Safe pattern seen in prior slices**:
- Extracted `write_test_checkpoint_with_header` (shared body) while leaving GitHub `write_test_checkpoint_file` / `ensure_test_checkpoint` and Linear header call site unchanged externally.
- `mark_task_progress_complete` is provider-agnostic and lives in `task_progress.sh`.

Violation of these rules blocks the slice.

Current related sizes (block growth without extract):
- `linear_issue.sh`: ~923 → target keep < ~950
- `github_issue.sh`: ~539 (already houses GitHub verticals)
- `grkr`: ~435 (thin launcher)

---

## 6. Non-goals (restated for implementers)

- No user-facing behavior change for `--linear-issue` or any flag.
- GitHub remains default `GRKR_ISSUE_PROVIDER`.
- No supervisor/picker/scheduler changes.
- No live Linear mutation behavior change (dry-run + guarded apply semantics unchanged).
- Do not grow `linear_issue.sh` without prior shared extraction.
- Do not move Linear into `github_issue.sh`.
- Do not rewrite `process_linear_issue` as pure Gleam in this design's children (optional later).
- Do not edit product Gleam or shell logic in the design phase.
- No new public surface that alters the Linear contract.
- No smoke e2e beyond design; tests are listed only for regression surface.

---

## 7. Spec refs + AGENTS constraints

**Must read for implementers**:
- `spec/parts/17-issue-workflow-overview.md`
- `spec/parts/22-stage-3-implement-or-refuse-decision-gate.md`
- `spec/parts/23-refusal-flow.md`
- `spec/parts/25-stage-4-implement.md`
- `spec/parts/26-stage-5-test.md`
- `spec/parts/31-test-checkpoint.md`
- `spec/parts/32-detailed-issue-workflow-pseudocode.md`
- `spec/parts/38-acceptance-criteria.md`
- `spec/parts/39-recommended-implementation-order.md`
- AGENTS.md (≤1000 LOC, thin bin/, update README after func change, spec/parts canonical, GitHub default, shared delegates, preserve shell conventions, run sync-spec only if parts touched)
- Prior Linear designs: `docs/design-linear-implement-stage.md`, `docs/design-linear-test-stage.md`, `docs/design-linear-publish-stage.md`, `docs/design-linear-live-mutate.md`
- GitHub thinning precedent: `docs/design-github-process-issue-thinning.md`

Existing design style to mirror exactly: goal/non-goals, current state with tip, modules/files, wire protocol, progress.json parity, fixtures/test plan, risks, product decisions, slice acceptance, out-of-scope, recommended order, paste-ready card brief.

---

## 8. Explicit ordered slice table (smallest shippable first)

Each slice acceptance must require:
- Files ≤1000 LOC (block if linear_issue would exceed ~950 without extract first).
- `gleam build` + `gleam test` + `npm test` green.
- Linear `--linear-issue` regression green: `test/grkr-linear-issue-implement.sh`, `test/grkr-linear-refuse-progress.sh`, `test/grkr-linear-issue-mvp.sh`, `test/grkr-linear-apply-matrix.sh`.
- GitHub smoke suite green if shared helper extraction touches GitHub paths (`test/grkr-smoke.sh`, `grkr-checkpoint-resume.sh`, `grkr-refusal.sh`, `grkr-implementation-to-refusal.sh`, `grkr-line-limit.sh`, `grkr-pr-body-limit.sh`, etc.).
- Zero intentional behavior change; no live mutate default change; no user-facing flags.
- README + docs/gleam-migration thin note added (per AGENTS) only on functional slices.

| Title | Primary files | Deps / shared ambient | Acceptance | Est. LOC delta (net) |
|-------|---------------|-----------------------|------------|----------------------|
| Shared pure/shell utility hygiene (pre-slice, if any) | `bin/lib/linear_issue.sh`, potential neutral `bin/lib/*.sh` (e.g. shell-unquote if proven reusable) | `decode_shell_assignment_value` if neutral; otherwise docs-only | No behavior change; clearer reuse docs or tiny neutral extract; all regressions green | 0–10 (or 0 if nothing truly shared yet) |
| Extract Linear test checkpoint (~159 LOC) to sibling | `bin/lib/linear_issue.sh` (thin call), `bin/lib/linear_issue_stages.sh` (new) or keep co-located | `build_command_list`, `run_test_stage_hook`, `write_test_checkpoint_with_header`, `run_progress_cli`, `checkpoint_marker`, `cleanup_test_result_logs`, `mark_task_progress_failed` | Linear test path identical externally (test.md header/marker/sections, stages.test, mutation dumps, exit codes); GitHub untouched; Linear regression green; ≤1000 | +100–140 in sibling; –120–150 in linear_issue |
| Extract Linear publish + complete (~151 LOC) to sibling | `bin/lib/linear_issue.sh`, `bin/lib/linear_issue_stages.sh` (or focused publish) | `ensure_publishable_file_sizes`, `stage_relevant*`, `git_in_*`, `check_file_line_limit`, `generate_linear_implement_commit_message`, `extract_linear_codex_pr_body`, `mark_task_progress_complete`, `run_progress_cli` (pr_summary + Done) | Linear publish+complete parity (same commits/PRs from linear-*, no labels, complete comment before Done, progress complete, mutation dumps); GitHub untouched; Linear regression green | +100–130 in sibling; –110–140 in linear_issue |
| Extract Linear refusal checkpoint (~117 LOC) | `bin/lib/linear_issue.sh`, sibling stages lib | `run_progress_cli` (plan-linear-refusal + render + mutations), `mark_task_progress_refused`, `maybe_apply` | Linear refuse path identical (refusal.md, planned comment + Backlog, progress refused, dumps); direct test caller unchanged; regressions green | +70–100 in sibling; –80–110 in linear_issue |
| Extract research/plan `ensure_linear_checkpoint_stage` + implement_in_progress (~60+58) | `bin/lib/linear_issue.sh`, sibling | `write_research/plan_checkpoint_file` (templates), `run_progress_cli` (linear-comment-mutation + state), `update_task_progress_stage`, `maybe_apply` | Research/plan + implement_in_progress Linear paths parity (local .md + planned mutations + progress); resume works; regressions green | +60–90; –40–60 in linear_issue |
| Thin `process_linear_issue` to pure sequencer | `bin/lib/linear_issue.sh` (main), sibling stages | All above extracted fns + shared ambient (prepare_worktree, run_codex, run_decision_gate, detect_implementation_refusal) | `process_linear_issue` body becomes thin sequence of load → ensure_* calls; Linear happy + refuse + impl-refusal + failure paths green; no behavior change | –80–120 in linear_issue |
| (Optional later) Pure Gleam Linear helpers | `src/grkr/progress/*` or `workflow/*`, thin delegate | Templates, progress/cli, linear_state | Only if a pure helper is justified after shell thin; parity tests added | +30–80 Gleam (pure) |

Each row is a candidate single-PR card. Earlier rows unblock later rows. Order may be adjusted with rationale (largest headroom first is preferred to create safety margin).

---

## 9. Recommended first implement slice + rationale

**First slice**: Extract the largest vertical Linear-only chunk that frees headroom — `ensure_linear_test_checkpoint` (~159 LOC) — into a sibling lib (e.g. `bin/lib/linear_issue_stages.sh` or focused test stage lib) while `process_linear_issue` and the call site in `bin/grkr` stay behaviorally identical.

**Rationale**:
- Largest single chunk; immediately creates ~150 LOC headroom under the 950 rule.
- Already reuses shared delegates (`build_command_list`, `run_test_stage_hook`, `write_test_checkpoint_with_header`, `cleanup_test_result_logs`) — minimal new shared work.
- Exercises worktree exec, command list, mutation planning, progress, marker, and Linear header path.
- Does not touch publish, refusal, or decision — lower blast radius for first cut.
- Linear regression surface (`grkr-linear-issue-implement.sh`, MVP, apply-matrix) directly covers it.
- GitHub untouched (shared header writer continues to serve both).
- Creates the sibling lib pattern for subsequent extractions (publish, refusal).
- Matches the GitHub precedent (test checkpoint was slice 1 in the GitHub thinning design).

See §12 for paste-ready card title + `/goal` brief.

---

## 10. Follow-up implement card titles (ready to spawn; do not implement here)

- "Extract Linear publish + complete (`ensure_linear_publish_complete`) to bin/lib/linear_issue_stages.sh (or focused lib)"
- "Extract Linear refusal checkpoint (`ensure_linear_refusal_checkpoint`) to linear stages lib"
- "Extract Linear research/plan checkpoint + implement_in_progress to linear stages lib"
- "Thin bin/lib/linear_issue.sh process_linear_issue to launcher + delegates after stage extracts"
- "LOC hygiene + shared shell utility extract (if decode or other neutral helpers justify)"
- "Optional: pure Gleam Linear formatter surface (after shell thin, only if justified)"

Factory can spawn these in order after the first lands and is verified.

---

## 11. Regression surface (tests that must stay green)

All of these exercise the `--linear-issue` path and must pass with identical behavior (logs, artifacts, gh calls for PR only, progress.json, mutation dumps, exit codes, worktree state) after every slice. GitHub tests must stay green on shared extractions.

**Linear-specific (must stay green)**:
- `test/grkr-linear-issue-implement.sh` (full happy path to STAGE=complete; PR from linear-*, no gh issue edits, complete comment + Done plan, no-changes path still completes)
- `test/grkr-linear-refuse-progress.sh` (plans comment + Backlog state; writes refusal.md; progress refused; direct call to ensure_linear_refusal_checkpoint)
- `test/grkr-linear-issue-mvp.sh` (MVP smoke: research/plan + decision + implement + test + publish/complete)
- `test/grkr-linear-apply-matrix.sh` (hermetic GRKR_LINEAR_APPLY_CMD stub matrix: dry-run, skipped-no-token, applied, skipped-already, failed, name-only)

**GitHub smoke suite (must stay green on shared helper extraction; untouched otherwise)**:
- `test/grkr-smoke.sh`
- `test/grkr-checkpoint-resume.sh`
- `test/grkr-refusal.sh`
- `test/grkr-implementation-to-refusal.sh`
- `test/grkr-line-limit.sh`
- `test/grkr-pr-body-limit.sh`
- `test/grkr-progress-cli.sh`
- `test/grkr-dirty-worktree-warning.sh`, `test/grkr-branch-exists.sh`, `test/grkr-init.sh`, `test/grkr-installed-layout.sh` (infrastructure)

**Cross-cutting**:
- `npm test` (shell harness)
- `gleam test` + `gleam build` clean on every slice

No new GitHub-specific e2e required for Linear thinning; reuse existing fixtures + gh stubs. Linear tests use `LINEAR_FIXTURE_PATH` or issue_provider fixtures; no live Linear by default.

---

## 12. Paste-ready first implement card brief with /goal

```
/goal Extract Linear test checkpoint (ensure_linear_test_checkpoint ~159 LOC) to thin sibling lib (bin/lib/linear_issue_stages.sh or focused) while keeping external contract 100% identical for --linear-issue. Create shared reuse pattern precedent for later publish/refusal extracts. Linear regression green (implement + mvp + apply-matrix); GitHub untouched (continues to use write_test_checkpoint_with_header). bin/lib/linear_issue.sh becomes slightly thinner; process_linear_issue call site unchanged.

Context: docs tip bdf396b (product a3d9702 / PR #121). bin/lib/linear_issue.sh ~923 LOC near 1000 AGENTS limit. GitHub process_issue thinning COMPLETE (bin/grkr 435 LOC thin launcher; github_issue.sh 539). Shared header writer + build_command_list + run_test_stage_hook already exist from design-linear-test-stage. grkr-issue-workflow.sh is thin Gleam delegate precedent. linear_mutate.sh already separated for guarded apply.

Read (must):
- AGENTS.md (≤1000, thin bin/, shared delegates, GitHub default, update README on func change, spec canonical)
- spec/parts/17-issue-workflow-overview.md, 26-stage-5-test.md, 31-test-checkpoint.md, 22-decision-gate.md, 25-implement.md, 23-refusal-flow.md, 32-pseudocode, 38-acceptance, 39-recommended...
- docs/design-linear-test-stage.md (how header was shared) + design-linear-publish-stage.md + design-linear-implement-stage.md + design-github-process-issue-thinning.md (mirror pattern) + this design doc
- bin/lib/linear_issue.sh (ensure_linear_test_checkpoint ~432-590, write_test_checkpoint_with_header call with Linear header, build_command_list, run_test_stage_hook, run_progress_cli linear-*, maybe_apply, process_linear_issue call site)
- bin/grkr (dispatch only: process_linear_issue "$LINEAR_ISSUE_ID")
- bin/lib/task_progress.sh (update_stage, mark_failed)
- bin/grkr-issue-workflow.sh (thin delegate pattern)
- test/grkr-linear-issue-implement.sh, grkr-linear-refuse-progress.sh, grkr-linear-issue-mvp.sh, grkr-linear-apply-matrix.sh (must stay green)
- test/grkr-smoke.sh + GitHub checkpoint/resume/refusal (must stay green if shared touched)
- src/grkr/workflow/test_stage.gleam + progress/* (for hook/marker surface)

Acceptance (one PR):
- Linear --linear-issue test path produces identical test.md (marker + "Linear issue ID: title"), progress stages.test=done|failed, mutation dumps (test.linear-mutation.txt + test.linear-state-mutation.txt), exit codes, worktree exec, command list as before.
- New/updated shell test or evolved MVP/implement exercises the path; fixture/gh stub constraints preserved.
- GitHub path unchanged (still reaches STAGE=complete; uses shared header writer).
- No file >1000 LOC; linear_issue.sh net thinner or neutral (block if would exceed ~950 without extract).
- gleam build + gleam test + npm test green.
- README + docs/gleam-migration thin note added (per AGENTS) if functional change.
- No behavior change to user flags, Linear contract, or live mutate defaults.
- No GitHub publish/label changes; no supervisor changes.

Non-goals: publish extraction, refusal extraction, live mutate changes, new flags, spec edits, GitHub behavior change.

Use Grok Build CLI --mode implement (or full). After changes run gleam build + relevant tests + the listed regression shells. Follow AGENTS exactly.
```

---

## 13. Acceptance for THIS design card

- Design doc exists at `docs/design-linear-issue-thinning.md` with:
  - Full inventory (every function, LOC, callers, Gleam overlap).
  - Target module map + concrete proposed files + ownership vs GitHub.
  - Ordered slice table (smallest shippable first) with acceptance per slice.
  - LOC risk rules (950 threshold + shared extraction mandate).
  - Explicit non-goals.
  - Spec refs + AGENTS alignment.
  - Regression surface list (Linear MVP/implement/refuse/apply-matrix + GitHub smoke).
  - Recommended first slice clearly called out with rationale.
  - Follow-up card titles listed.
  - Paste-ready implement brief with /goal.
- Optional: one-line pointer added to `docs/gleam-migration.md` "Next product thinning" or "Still forward-looking" (docs-only, safe).
- No product code or behavior changes in `bin/`, `src/`, or `test/`.
- Design-only — no product code edited.
- `git status --porcelain` (ignoring pre-existing untracked `.grkr/*`) shows only the new design doc (and optional one-line docs pointer).

---

**End of design document.**

Next: kanban factory spawns the first implement card using the brief in §12. Implement worker writes self-contained prompt (this design + listed files + AGENTS + spec parts), runs Grok Build CLI `--mode implement`, verifies `gleam build` / tests / regression shells, and completes the card. Subsequent slices follow the table.

**Design-only — no product code was edited.**
