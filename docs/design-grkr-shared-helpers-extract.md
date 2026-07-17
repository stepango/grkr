# Design: Extract Shared Helpers from `bin/grkr` (Neutral `bin/lib/`)

**Status**: Design-only (plan agent). No product code edits.  
**Reference tip**: origin/main @ **5418159** (branch head **54181592cebf011169464610ececd05d9278bc75**; docs tip-sync #134 lineage after product **f6b34d4** / PR #133 Linear final thin sequencer).  
**Prior design artifacts**: `docs/design-github-process-issue-thinning.md` (GitHub thinning complete @ a3d9702), `docs/design-linear-issue-thinning.md` (Linear thinning complete through slice 5 @ f6b34d4).  
**Gap addressed**: After both vertical thins, `bin/grkr` (435 LOC) remains the home for several cross-provider shared helpers (test checkpoint writer, line-limit/publishable guard, codex exec bridge, progress CLI bridge, attach logs). Provider libs (`github_issue.sh` 539, `linear_issue_stages.sh` 725) and thin sequencers already depend on these via ambient call-time resolution. The header comment in `github_issue.sh` still claims "Shared helpers stay in bin/grkr"; this design supersedes that. Goal: move truly shared helpers to neutral `bin/lib/*.sh` so `bin/grkr` becomes a pure CLI launcher (resolve + source + flag parse + log/trap + thin `process_issue` sequencer + dispatch). Optional pure Gleam later only if justified. Design-only — no product shell/Gleam implementation.  
**Date**: 2026-07-17

---

## 1. Goal / non-goals

### Goal
Produce `docs/design-grkr-shared-helpers-extract.md` that:

- Re-measures (by reading files) the current state at tip 5418159 and inventories every still-defined function in `bin/grkr` (name, approx LOC, callers across GitHub/Linear/launcher, Gleam overlap).
- Produces a **target module map** for neutral shared helpers (prefer concern-split `bin/lib/issue_shared.sh` or small focused files; never grow `linear_issue_stages.sh` or `github_issue.sh` as a dumping ground).
- Defines an **ordered slice table** of shippable PRs (smallest first) with per-slice acceptance: files stay ≤1000 LOC, `gleam build` + `gleam test` + `npm test` green, GitHub smoke suite + Linear regression matrix green when shared touched, zero intentional behavior change.
- Explicitly states **non-goals** (no behavior change; GitHub default; Linear mutate default OFF; `process_issue` thin sequencer stays in `grkr` unless proven better elsewhere; no new public flags).
- Cites AGENTS.md, `spec/parts/` (17/22/25/26/31/38/39 + supporting), and prior designs.
- Provides a ready-to-spawn **first implement slice** recommendation + follow-up card titles (do not implement).
- Lists the **regression surface** (all tests that must stay green).
- Includes a **paste-ready first implement card brief** with `/goal`.

Preserve (per AGENTS + prior designs):
- Thin shell conventions in `bin/` and `test/`.
- Every file ≤ 1000 LOC (extract helpers early; split before growth).
- `spec/parts/` as canonical source; no spec content edits in design-only (sync optional for index only).
- Prefer **shared neutral delegates** over duplicating or growing provider-specific files.
- Heavy orchestration (codex exec, gh, worktree context, bash loops) may stay shell; pure formatting/rendering already largely in Gleam (progress/templates, workflow/*).
- GitHub remains the default `GRKR_ISSUE_PROVIDER`.
- Linear and GitHub call sites stay separate; shared code is provider-agnostic or header-parameterized (example: `write_test_checkpoint_with_header`).
- `bin/grkr` remains the single entry that sources doctor + thin libs + dispatches `--issue` / `--project` / `--linear-issue` / init. `process_issue` and `process_linear_issue` remain thin sequencers.

### Non-goals (explicitly out of scope for this design and its children)
- No behavior change to user-facing flags, commands, `--issue`, `--linear-issue`, or `grkr` contract.
- `GRKR_ISSUE_PROVIDER` default remains GitHub; no picker/supervisor rewrite.
- No live Linear mutation changes (`GRKR_LINEAR_MUTATE=1` default OFF semantics unchanged).
- Do not move already-extracted GitHub verticals or Linear verticals.
- Do not move `process_issue` (thin sequencer) out of `bin/grkr` unless this design proves a clearly better home (default: KEEP thin sequencer in launcher).
- Do not grow `linear_issue_stages.sh` (~725) or `github_issue.sh` (~539) to absorb shared helpers.
- Do not edit product Gleam or shell logic in the design phase.
- No new public flags or provider switches.
- No smoke e2e creation beyond listing the regression surface.

---

## 2. Current state (cite files + tip)

**What is already Gleam (do not re-port blindly; wire/thin only)**:
- `src/grkr/workflow/`: `decision_gate.gleam`, `implement_stage.gleam`, `test_stage.gleam`, `worktree*`, `task_log*`, `decision.gleam`, `main.gleam`, `ffi.gleam`, `handle_comment.gleam`, `resolve_pr.gleam`.
- `src/grkr/progress/`: `checkpoint_*`, `linear_*`, `templates.gleam`, `cli.gleam`, `main.gleam`.
- `src/grkr/refusal/*`, `issue_provider/*`, `linear/*`, `project_status/*`, `supervisor/*`, `github_picker/*`, `sync_main/*`, `task_slug*`.
- Thin shell: `bin/grkr-issue-workflow.sh` (~124 LOC), `bin/grkr-templates.sh` (~114 LOC), `bin/grkr-project-status.sh` (~81 LOC), `bin/grkr-task-slug.sh` (~17 LOC), `bin/doctor.sh` (~52 LOC thin).
- Shared thin libs: `bin/lib/task_progress.sh` (176 LOC), `bin/lib/refusal_paths.sh` (~125 LOC).
- GitHub path: `bin/grkr` (435 LOC thin launcher + sequencer); `bin/lib/github_issue.sh` (539 LOC: test/publish/research-plan/checkpoint/comment/completion/bootstrap/decision/implement/finalize).
- Linear path: `bin/lib/linear_issue.sh` (329 LOC thin sequencer + load/meta/bootstrap); `bin/lib/linear_issue_stages.sh` (725 LOC: test/publish/refusal/research/plan/implement stages + decision/implement orchestration); `bin/lib/linear_mutate.sh` (62 LOC guarded apply).

**Current state of `bin/grkr` at tip (re-verified by reading the file)**:
- 435 LOC total.
- Sources (in order): `doctor.sh`, `grkr-project-status.sh`, `grkr-issue-workflow.sh`, `lib/refusal_paths.sh`, `lib/task_progress.sh`, `lib/linear_issue.sh` (internally sources `linear_mutate.sh` then `linear_issue_stages.sh`), `lib/github_issue.sh`, `grkr-task-slug.sh`; later `. "$SCRIPT_DIR/grkr-templates.sh"`.
- All shared helper functions are **defined after** the sourcing block. Bash resolves functions at call time, so provider libs (`github_issue.sh`, `linear_issue_stages.sh`) can call them even though definitions appear later in the sourcing file (`bin/grkr`).
- `process_issue` is now a thin sequencer (post PR #121) delegating to `bootstrap_*`, `ensure_checkpoint_stage`, `run_github_*`, `ensure_publishable_file_sizes`, `ensure_test_checkpoint`, `publish_*`, `finalize_*`.
- `process_linear_issue` is a thin sequencer (post PR #133) delegating similarly for Linear.

**Related sizes at tip (re-measured)**:
- `bin/grkr`: 435 LOC
- `bin/lib/github_issue.sh`: 539 LOC
- `bin/lib/linear_issue_stages.sh`: 725 LOC
- `bin/lib/linear_issue.sh`: 329 LOC
- `bin/lib/linear_mutate.sh`: 62 LOC
- `bin/lib/task_progress.sh`: 176 LOC
- `bin/lib/refusal_paths.sh`: ~125 LOC
- `bin/grkr-issue-workflow.sh`: 124 LOC
- `bin/grkr-templates.sh`: 114 LOC
- `bin/grkr-project-status.sh`: 81 LOC
- `bin/doctor.sh`: 52 LOC
- `bin/grkr-task-slug.sh`: 17 LOC

**Source order implications (critical for extraction)**:
- Today: helpers defined late in `bin/grkr` after all `.` sourcing. Call-time resolution works.
- After moving shared helpers to e.g. `bin/lib/issue_shared.sh`: the new lib must be sourced **before** `lib/linear_issue.sh` and `lib/github_issue.sh` (or at minimum before dispatch) so definitions exist when provider stages call them. Prefer early source for clarity and to avoid accidental ambient ordering bugs. `linear_issue.sh` internally sources mutate then stages — source shared before `linear_issue.sh` to keep the chain safe.

---

## 3. Inventory: every function still defined in `bin/grkr`

Re-verified via direct file read + grep for definitions/callers. Numbers approximate body LOC (excludes top-level sourcing/usage/dispatch). Callers listed by provider surface + launcher.

| approx LOC | Function | lines (approx) | Callers (GitHub / Linear / both / launcher) | Gleam overlap / already-delegated? | Notes |
|------------|----------|----------------|---------------------------------------------|------------------------------------|-------|
| 15 | `resolve_script_path` | L4-18 | launcher bootstrap only | None | Pure bootstrap; stays in launcher. |
| 9 | `usage` | L31-39 | launcher CLI only | None | Help text; stays in launcher. |
| 14 | `attach_issue_logs` | L86-99 | GitHub finalize (github_issue.sh:3), refusal_paths.sh, cleanup_on_exit | None | GitHub issue comment log dump. Linear does not use (no gh issue comments for Linear items). |
| 8 | `cleanup_on_exit` | L101-108 | launcher trap only (EXIT) | None | Removes prompt file, optionally attaches logs, cleans pipe/tee. Stays launcher-local with trap. |
| 12 | `collect_file_line_limit_violations` | L139-150 | both (via ensure_publishable + github publish path) | None | Uses `git_in_issue_context` (from grkr-issue-workflow). Staged files >1000. |
| 13 | `check_file_line_limit` | L152-164 | both (via ensure_publishable + github publish) | None | Thin wrapper over collect; prints and returns violations count. |
| 19 | `run_progress_cli` | L167-185 | both (many: Linear mutations, checkpoints, marker, Linear mutate; GitHub marker; tests stub it) | Thin bridge to `gleam run -m grkr/progress/cli`; fallback marker only | Heavy ambient (SCRIPT_DIR, GRKR_GLEAM_PROJECT_ROOT). Care required on extract. |
| 6 | `checkpoint_marker` | L187-192 | both (github comment helpers, Linear stages, tests) | Delegates to run_progress_cli marker | Tiny; often paired with run_progress_cli. |
| 17 | `build_command_list` | L194-210 | both (github ensure_test_checkpoint, linear ensure_linear_test_checkpoint) | None (pure list builder) | BUILD/TEST or npm test. Good shared candidate. |
| 10 | `cleanup_test_result_logs` | L212-221 | both (github test checkpoint, linear test checkpoint) | None | Removes temp log files listed in results tsv. |
| 62 | `write_test_checkpoint_with_header` | L228-289 | both (github via write_test_checkpoint_file wrapper; Linear direct with "Linear issue ID: title") | None (shared body writer) | Extracted in prior test-stage work precisely for cross-provider reuse. Header-param. |
| 19 | `summarize_text` | L291-309 | **none** (rg found 0 callers in *.sh; only historical mention in prior design) | None | Likely dead code. Confirm in implement slice; if dead, delete or leave (non-goal to clean aggressively). |
| 18 | `run_codex_prompt` | L311-328 | both (github decision/implement stages; linear decision/implement stages) | Uses `persist_task_log_output` (Gleam task_log) | Codex exec + persist bridge. Shared. |
| 31 | `ensure_publishable_file_sizes` | L330-360 | both (github process_issue; linear ensure_linear_publish_complete) | Uses stage_*, collect/check, run_codex_prompt (remediation), write_line_limit_fix_prompt (templates) | Line-limit guard + optional remediation loop. Shared. |
| 43 | `process_issue` | L362-404 | launcher only (--issue / --project loop) | Thin sequencer; delegates to bootstrap/ensure_*/run_* (github lib) + shared | KEEP thin sequencer in grkr per non-goals unless design proves better home. |

**Top-level launcher-only surface (stays in grkr)**:
- Flag parse, MODE dispatch, init path, --project watcher loop, --issue → `process_issue`, --linear-issue → `process_linear_issue`.
- Logging pipe/tee, CURRENT_* globals, MAX_* constants, sourcing bootstrap.

**Call graph notes**:
- GitHub happy path (post thin): `process_issue` → bootstrap (lib) → ensure research/plan (lib) → run decision (lib + run_codex) → (proceed) run implement (lib + run_codex) → ensure_publishable (shared) → ensure_test (lib + build_command + write_*_with_header) → publish (lib) → finalize (lib + attach).
- Linear happy path mirrors with Linear-specific ensure_* in stages + shared helpers.
- Refusal paths (decision or impl) go through `refusal_paths.sh` + `attach_issue_logs` (GitHub) or Linear refusal checkpoint (no gh logs).

**Gleam overlap notes**:
- `run_progress_cli` already bridges to `progress/cli`; fallback is tiny pure marker.
- `persist_task_log_output` (used by run_codex) is already Gleam.
- `build_command_list` is pure list logic — candidate for pure Gleam later (only if no globals/exec).
- `summarize_text` is pure text util — if live, candidate; currently appears dead.
- Checkpoint header formatting and line-limit prompt fragments live in templates (Gleam) or are thin wrappers.
- Heavy exec (codex, test commands in worktree, gh posting) and ambient context (CURRENT_*, worktree) stay shell for now.

---

## 4. Target module map + ownership boundaries

**Guiding principle**: `bin/grkr` becomes pure launcher + thin sequencer + launcher-local trap. Shared helpers that both providers (or tests) already call move to neutral `bin/lib/`. Provider-specific bodies stay in their vertical (`github_issue.sh`, `linear_issue*.sh`). Never put Linear-only into github or vice-versa. Do not dump shared into `linear_issue_stages.sh` (already 725) or `github_issue.sh` (539).

**Preferred locations**:
- New neutral shared surface: `bin/lib/issue_shared.sh` (or small focused splits if blast radius justifies):
  - `write_test_checkpoint_with_header`, `cleanup_test_result_logs`, `build_command_list` (test-write cluster).
  - `collect_file_line_limit_violations`, `check_file_line_limit`, `ensure_publishable_file_sizes` (publish/line-limit cluster).
  - `run_codex_prompt` (codex/exec bridge).
  - `run_progress_cli`, `checkpoint_marker` (progress bridge — extract carefully due to ambient deps).
  - `attach_issue_logs` (primarily GitHub+refusal; verify Linear does not call).
- Keep forever in launcher (`bin/grkr`):
  - `resolve_script_path`, `usage`.
  - `cleanup_on_exit` + `trap` (launcher-local state + pipe).
  - `process_issue` (thin sequencer — default KEEP).
  - MODE/flag parse, sourcing order, logging setup, dispatch to `process_linear_issue`.
- Existing shared (already correct):
  - `bin/lib/task_progress.sh`, `bin/lib/refusal_paths.sh`.
- Provider ownership:
  - GitHub owns: gh issue view/comment/edit/labels, "Issue #N: title", "Fixes #N", project moves via grkr-project-status, `write_test_checkpoint_file` (thin header wrapper), all `ensure_*`/`publish_*`/`bootstrap_*`/`run_github_*`/`finalize_*` in `github_issue.sh`.
  - Linear owns: `issue_provider/main fetch-issue` wire, "Linear issue ID: title", no # identifiers, no "Fixes #N", PR from `linear-$SLUG`, Linear state/comment mutation planning, `process_linear_issue` thin + `bootstrap_linear_*` + thin wrappers in `linear_issue.sh`, all `ensure_linear_*` in stages.
  - Shared (header-param or provider-agnostic): the list above + `stage_relevant_issue_files`, `git_in_issue_context`, `prepare_issue_worktree`, `run_decision_gate`, `detect_implementation_refusal`, `mark_task_progress_*`, `run_test_stage_hook`, `persist_task_log_output`, `generate_*_implement_commit_message`, `extract_*_codex_pr_body` variants, templates renderers.

**Concrete proposed new file**:
- `bin/lib/issue_shared.sh` (new, well under 1000 with room). Small focused files (e.g. `checkpoints.sh`, `publish_guard.sh`) are acceptable if a slice proves cleaner, but one neutral shared file is preferred for first cuts to keep sourcing simple.
- Update sourcing in `bin/grkr`: source `issue_shared.sh` **after** task_progress/refusal_paths and **before** `linear_issue.sh` (and therefore before `github_issue.sh`).

**LOC discipline** (AGENTS + prior designs):
- If any file would exceed ~950 during change, extract first.
- Shared that both use **must** go to neutral before landing in a provider file.
- Target each new/existing file with comfortable headroom.

---

## 5. Ordered slice table (smallest first)

Each slice acceptance:
- Files ≤1000 LOC (block if any touched file would exceed ~950 without prior extract).
- `gleam build` + `gleam test` + `npm test` green.
- GitHub smoke suite green (`grkr-smoke.sh`, `checkpoint-resume`, `refusal`, `implementation-to-refusal`, `line-limit`, `pr-body-limit`, `progress-cli`, dirty/branch/init/installed).
- Linear regression green when shared touched (`grkr-linear-issue-implement.sh`, `grkr-linear-refuse-progress.sh`, `grkr-linear-issue-mvp.sh`, `grkr-linear-apply-matrix.sh`).
- Zero intentional behavior change (identical logs, artifacts, gh calls for GitHub paths, mutation dumps for Linear, progress.json, exit codes, worktree state).
- README + docs/gleam-migration "Next product thinning" note added (per AGENTS) only on functional slices.
- Source order: new shared lib sourced before provider libs.

| Title | Primary files | Deps / shared ambient | Acceptance | Est. LOC delta (net) |
|-------|---------------|-----------------------|------------|----------------------|
| Shared test-write cluster (write_test_checkpoint_with_header + cleanup_test_result_logs + build_command_list) | `bin/lib/issue_shared.sh` (new), `bin/grkr`, update sourcing | `checkpoint_marker`, `run_test_stage_hook`, `write_test_checkpoint_file` (github wrapper), `git_in_*` | Both providers produce identical test.md (header + marker + sections), stages.test, exit codes; GitHub/Linear regressions green; no behavior change | +70–90 in shared; –60–80 in grkr |
| Line-limit + ensure_publishable_file_sizes | `bin/lib/issue_shared.sh`, `bin/grkr` | `collect/check`, `stage_relevant*`, `run_codex_prompt`, `write_line_limit_fix_prompt` (templates), `git_in_*` | Line-limit remediation + abort paths identical for GitHub + Linear publish; grkr-line-limit + Linear implement tests green | +30–50 in shared; –25–40 in grkr |
| run_codex_prompt (codex/exec + persist bridge) | `bin/lib/issue_shared.sh`, `bin/grkr` | `persist_task_log_output` (already Gleam), mktemp, workdir context | Decision + implement codex runs produce identical logs/artifacts for both providers; smoke + implement + Linear implement green | +15–25 in shared; –10–15 in grkr |
| run_progress_cli + checkpoint_marker (careful ambient) | `bin/lib/issue_shared.sh` or tiny keep-in-grkr, `bin/grkr` | SCRIPT_DIR, GRKR_GLEAM_PROJECT_ROOT, fallback marker | All marker + Linear mutation planning paths unchanged; progress-cli test + Linear matrix + GitHub checkpoints green | +15–25 or 0 (if kept tiny); net neutral or small move |
| attach_issue_logs | `bin/lib/issue_shared.sh`, `bin/grkr`, `bin/lib/github_issue.sh`, `bin/lib/refusal_paths.sh` | CURRENT_ISSUE, LOGFILE | GitHub finalize + refusal paths attach identical logs; Linear untouched (no callers); GitHub regressions green | +10–15 in shared; –10 in grkr |
| (Hygiene / deadcode) Confirm or remove summarize_text | `bin/grkr` (or delete) | None | If confirmed dead: remove (or document). If any latent caller appears: move or keep. Zero behavior impact. | 0 or –19 |
| Leave launcher surface in grkr (no slice) | `bin/grkr` | resolve, usage, cleanup_on_exit+trap, process_issue thin sequencer, dispatch | Explicit non-move; grkr remains ~300–350 LOC launcher after extracts | N/A |

Slices are independent where possible; earlier rows reduce blast radius for later rows. Order may be adjusted with rationale (largest truly-shared cluster first is preferred per task guidance).

---

## 6. Optional later pure Gleam candidates (NOT required first slices)

Only after shell is thin and parity proven, and **only if provably pure** (no globals, no exec side effects, no ambient resolution):

- `build_command_list` (pure list from env) → `src/grkr/workflow/test_stage.gleam` or new helper.
- `summarize_text` (if ever revived) → pure util.
- Checkpoint header formatting fragments or line-limit prompt body pieces (most already live in `progress/templates.gleam`).
- `run_progress_cli` marker fallback (already tiny pure).

Heavy bridges (codex exec, worktree test runs, gh posting, log attachment) stay shell. Do not force Gleam ports for orchestration.

---

## 7. Regression surface (tests that must stay green)

All of these must pass with identical behavior after every slice that touches shared code.

**GitHub-specific / smoke**:
- `test/grkr-smoke.sh` (happy path to PR + complete comment)
- `test/grkr-checkpoint-resume.sh` (research/plan/test resume from markers)
- `test/grkr-refusal.sh` (decision-gate refusal + checkpoint + progress)
- `test/grkr-implementation-to-refusal.sh` (during-impl refusal conversion)
- `test/grkr-line-limit.sh` (remediation loop + publish abort)
- `test/grkr-pr-body-limit.sh` (compact PR body + Fixes footer)
- `test/grkr-progress-cli.sh` (marker + progress helpers)
- `test/grkr-dirty-worktree-warning.sh`, `test/grkr-branch-exists.sh`, `test/grkr-init.sh`, `test/grkr-installed-layout.sh` (infrastructure + layout)

**Linear-specific (must stay green on shared extraction)**:
- `test/grkr-linear-issue-implement.sh` (full to STAGE=complete; PR from linear-*, complete comment + Done plan)
- `test/grkr-linear-refuse-progress.sh` (plans comment + Backlog; direct call to ensure_linear_refusal_checkpoint)
- `test/grkr-linear-issue-mvp.sh` (MVP smoke)
- `test/grkr-linear-apply-matrix.sh` (hermetic GRKR_LINEAR_APPLY_CMD matrix)

**Cross-cutting**:
- `npm test` (shell harness)
- `gleam test` + `gleam build` clean on every slice

No new e2e required; reuse existing fixtures + gh stubs. Linear tests use `LINEAR_FIXTURE_PATH` or issue_provider fixtures.

---

## 8. Spec refs + AGENTS constraints

**Must read for implementers**:
- `spec/parts/17-issue-workflow-overview.md`
- `spec/parts/22-stage-3-implement-or-refuse-decision-gate.md`
- `spec/parts/25-stage-4-implement.md`
- `spec/parts/26-stage-5-test.md`
- `spec/parts/31-test-checkpoint.md`
- `spec/parts/32-detailed-issue-workflow-pseudocode.md` (flow context)
- `spec/parts/38-acceptance-criteria.md`
- `spec/parts/39-recommended-implementation-order.md`
- AGENTS.md (≤1000 LOC, thin bin/, update README after func change, spec/parts canonical, GitHub default, shared delegates, preserve shell conventions, run sync-spec only if parts touched)
- Prior designs: `docs/design-github-process-issue-thinning.md`, `docs/design-linear-issue-thinning.md`, `docs/design-linear-test-stage.md`, `docs/design-linear-publish-stage.md`, `docs/design-linear-implement-stage.md`

Existing design style to mirror exactly: goal/non-goals, current state with tip + LOC table, full function inventory + callers + Gleam notes, target module map + ownership, ordered slice table with acceptance, LOC risk, explicit non-goals, regression surface, paste-ready card brief.

---

## 9. Recommended first implement slice + rationale

**First slice**: Extract the largest truly-shared, already-cross-called cluster with minimal blast radius: `write_test_checkpoint_with_header` + `cleanup_test_result_logs` (+ `build_command_list` for completeness) into `bin/lib/issue_shared.sh`.

**Rationale** (matches task intuition):
- Already designed for sharing (header-param); both providers call it.
- Clear boundary; exercises worktree test exec, command list, marker, progress, header formatting.
- Does not touch publish remediation, codex, or attach (lower risk).
- Creates the neutral lib + sourcing precedent for subsequent slices.
- GitHub regression (smoke, checkpoint-resume, line-limit, refusal) + Linear (implement, mvp, refuse, apply-matrix) directly cover it.
- Leaves launcher surface and trap untouched.

See §11 for paste-ready card title + `/goal` brief.

Follow-up slices follow the ordered table (line-limit/ensure_publishable, run_codex_prompt, progress bridge, attach).

---

## 10. Follow-up implement card titles (ready to spawn; do not implement here)

- "Extract line-limit + ensure_publishable_file_sizes to bin/lib/issue_shared.sh"
- "Extract run_codex_prompt (codex/exec bridge) to bin/lib/issue_shared.sh"
- "Extract run_progress_cli + checkpoint_marker to neutral shared (or keep tiny in grkr)"
- "Extract attach_issue_logs to bin/lib/issue_shared.sh (GitHub+refusal paths)"
- "LOC hygiene + deadcode confirm for summarize_text; source-order polish"
- "Optional: pure Gleam candidates (build_command_list etc.) after shell thin"

Factory can spawn in order after first lands and is verified.

---

## 11. Paste-ready first implement card brief with /goal

```
/goal Extract shared test-write cluster (write_test_checkpoint_with_header + cleanup_test_result_logs + build_command_list) to new neutral bin/lib/issue_shared.sh while keeping external contracts 100% identical for --issue and --linear-issue. Create sourcing precedent (source shared before provider libs). GitHub regression green (smoke + checkpoint-resume + line-limit + refusal + pr-body); Linear regression green (implement + mvp + refuse-progress + apply-matrix). bin/grkr net thinner; no behavior change.

Context: tip 5418159 (docs tip-sync #134 after product f6b34d4 / PR #133). bin/grkr 435 LOC thin launcher post GitHub process_issue thin (a3d9702) + Linear final sequencer thin (f6b34d4). Shared header writer already exists for cross-provider reuse. github_issue.sh 539; linear_issue_stages.sh 725 (do not grow). grkr-issue-workflow.sh + grkr-templates.sh are thin Gleam delegate precedent. linear_mutate.sh already separated.

Read (must):
- AGENTS.md (≤1000, thin bin/, shared delegates, GitHub default, update README on func change, spec canonical)
- spec/parts/17-issue-workflow-overview.md, 26-stage-5-test.md, 31-test-checkpoint.md, 22-decision-gate.md, 25-implement.md, 32-pseudocode, 38-acceptance, 39-recommended...
- docs/design-grkr-shared-helpers-extract.md + design-github-process-issue-thinning.md + design-linear-issue-thinning.md + design-linear-test-stage.md
- bin/grkr (write_test_checkpoint_with_header L228-289, cleanup_test_result_logs, build_command_list, attach/cleanup/process_issue call sites, sourcing order)
- bin/lib/github_issue.sh (write_test_checkpoint_file wrapper + ensure_test_checkpoint calls; header note about shared)
- bin/lib/linear_issue_stages.sh (ensure_linear_test_checkpoint direct call with Linear header + ambient list)
- bin/lib/linear_issue.sh (sources mutate+stages; process_linear_issue thin sequencer)
- bin/lib/task_progress.sh (mark_failed etc.)
- bin/grkr-issue-workflow.sh (run_test_stage_hook, git_in_issue_context)
- test/grkr-smoke.sh, grkr-checkpoint-resume.sh, grkr-line-limit.sh, grkr-refusal.sh, grkr-implementation-to-refusal.sh + all Linear regression shells (must stay green)
- src/grkr/workflow/test_stage.gleam + progress/* (hook/marker surface)

Acceptance (one PR):
- GitHub --issue test path produces identical test.md (marker + "Issue #N: title"), gh comment, progress stages.test=done|failed, exit codes, worktree exec, command list as before.
- Linear --linear-issue test path produces identical test.md (marker + "Linear issue ID: title"), progress stages.test, mutation dumps, exit codes as before.
- New shared lib sourced in bin/grkr before linear_issue.sh and github_issue.sh; provider call sites unchanged.
- No file >1000 LOC; bin/grkr net thinner or neutral; shared file has headroom.
- gleam build + gleam test + npm test green.
- README + docs/gleam-migration "Next product thinning" note added (per AGENTS).
- Zero behavior change to user flags, contracts, or mutate defaults.
- No GitHub label / Linear mutation / supervisor changes.

Non-goals: publish extraction, codex extraction, progress bridge extraction, attach extraction, process_issue move, new flags, spec edits, live mutate change.

Use Grok Build CLI --mode implement (or full). After changes run gleam build + relevant tests + the listed regression shells. Follow AGENTS exactly.
```

---

## 12. Acceptance for THIS design card

- Design doc exists at `docs/design-grkr-shared-helpers-extract.md` with:
  - Full current-tip SHAs + LOC table for bin/grkr + ALL bin/lib/*.sh + related thin shells.
  - Full function inventory with callers (GitHub vs Linear vs both vs launcher-only) + Gleam overlap notes.
  - Target module map — concern-split neutral libs, ownership boundaries vs github_issue / linear_issue*, what stays forever in launcher.
  - Ordered slice table (smallest first) with per-slice acceptance.
  - Explicit non-goals (no behavior change; GitHub default; Linear mutate OFF; process_issue KEEP default; no new flags; design-only).
  - Regression surface list (all listed GitHub smoke + Linear matrix + cross-cutting).
  - Recommended first slice clearly called out with rationale.
  - Follow-up card titles listed.
  - Paste-ready implement brief with /goal.
- Optional (docs-only, safe): one-line pointer in `docs/gleam-migration.md` "Next product thinning" section pointing at this design.
- No product code or behavior changes in `bin/`, `src/`, or `test/`.
- `git status --porcelain` (ignoring pre-existing untracked `.grkr/*`) shows only the new design doc (and optional one-line docs pointer).

---

**End of design document.**

Next: kanban factory spawns the first implement card using the brief in §11. Implement worker writes self-contained prompt (this design + listed files + AGENTS + spec parts), runs Grok Build CLI `--mode implement`, verifies `gleam build` / tests / regression shells, and completes the card. Subsequent slices follow the table.

**Design-only — no product code was edited.**
