# Design: GitHub `process_issue` Thinning (bin/grkr → Gleam)

**Status**: Design-only (plan agent). No product code edits.  
**Reference tip**: origin/main @ **8526d74** (post PR #107 live-mutate nits lineage **8d4b674**).  
**Prior design artifacts**: `docs/design-linear-publish-stage.md`, `docs/design-linear-test-stage.md`, `docs/design-linear-implement-stage.md`, `docs/design-linear-live-mutate.md`.  
**Gap addressed**: `bin/grkr` remains ~875 LOC thick launcher/orchestrator. GitHub `process_issue` (~166 LOC) + helpers (test checkpoint, publish, line limits, PR body, checkpoints) are the largest remaining shell thickness after spec/39 items 6–12 landed (decision_gate, implement_stage, test_stage, refusal, worktree, task_log, supervisor, picker, progress). Linear is already fully wired (dry-run + guarded mutate) and lives in `bin/lib/linear_issue.sh` (~923 LOC — near 1000). This design decomposes GitHub path thinning into small shippable kanban slices.  
**Date**: 2026-07-15

---

## 1. Goal / non-goals

### Goal
Produce `docs/design-github-process-issue-thinning.md` that:

- Inventories every still-thick function in `bin/grkr` (name, approx LOC, callers, Gleam overlap / already-delegated).
- Proposes a concrete **target module map** (prefer `src/grkr/workflow/*` or focused new modules; thin `bin/grkr` becomes launcher + thin delegates only). Includes proposed new files (e.g. `bin/lib/github_issue.sh`, `workflow/github_process_issue.gleam` or equivalent CLI surface, publish helpers, checkpoint helpers) with clear ownership boundaries vs Linear.
- Defines an **ordered slice table** of shippable PRs with per-slice acceptance: files stay ≤1000 LOC, `gleam build` + `gleam test` + `npm test` green, GitHub `--issue` regression fully green, Linear untouched unless a shared helper extraction is required.
- Documents **LOC risk rules** for `linear_issue.sh` (923 LOC): extraction rules before any growth; when shared helpers must leave `bin/grkr` without growing linear_issue.sh.
- Explicitly states **non-goals**.
- Cites spec refs and AGENTS.md.
- Provides a ready-to-spawn **first implement slice** recommendation + follow-up card titles (do not implement).
- Lists the **regression surface** (tests that must stay green).

Preserve (per AGENTS + prior designs):
- Thin shell conventions in `bin/`.
- Every file ≤ 1000 LOC (extract helpers early; prefer split before growth).
- `spec/parts/` as canonical source; no spec content edits in design-only (sync optional for index only).
- Prefer **shared thin delegates** over duplicating `process_issue` into Linear (or vice-versa).
- Heavy orchestration (codex exec, gh CLI, bash loops, worktree context) may stay shell initially; pure/decision/render/message formatting → Gleam first.
- GitHub remains the default `GRKR_ISSUE_PROVIDER`.
- Linear and GitHub call sites stay separate; shared code is header-parameterized helpers only (example: `write_test_checkpoint_with_header`).

### Non-goals (explicitly out of scope for this design and its children)
- No behavior change to user-facing flags, commands, or `grkr --issue` contract.
- `GRKR_ISSUE_PROVIDER` default remains GitHub; no picker/supervisor rewrite.
- No live Linear mutation changes.
- No duplication of `process_linear_issue` orchestration or Linear-specific state planning.
- Do not grow `bin/lib/linear_issue.sh` without prior shared extraction to a neutral lib.
- Do not edit `bin/grkr` implementation logic, `bin/lib/linear_issue.sh`, or `src/` in the design phase.
- No new public flags or provider switches for this work.

---

## 2. Current state (cite files + tip)

**What is already Gleam (do not re-port blindly; wire/thin only)**:
- `src/grkr/workflow/`: `decision_gate.gleam`, `implement_stage.gleam`, `test_stage.gleam`, `worktree*` (worktree.gleam + ops + stage + types + ffi), `task_log*` (core, persist, cli, types, ffi), `decision.gleam`, `main.gleam`, `ffi.gleam`, `handle_comment.gleam`, `resolve_pr.gleam`.
- `src/grkr/progress/`: `checkpoint_*`, `linear_*`, `templates.gleam`, `cli.gleam`, `main.gleam`.
- `src/grkr/refusal/*`, `github_picker/*`, `supervisor/*`, `task_slug*`, `sync_main/*`, `issue_provider/*`, `project_status/*`.
- Thin shell: `bin/grkr-issue-workflow.sh` (~68 LOC: doctor + `gleam_wf` + delegates for prepare/collect/stage/cleanup, all task_log, decision, implement/test stage hooks, `git_in_issue_context` compat).
- `bin/grkr-templates.sh` (~110 LOC thin delegator to progress/templates for 8 renderers).
- `bin/lib/task_progress.sh` (176 LOC shared: ensure/update/mark complete/failed/refused + meta/context writers).
- `bin/lib/refusal_paths.sh` (125 LOC: normalize/extract + handle_*_refusal).

**Current thick shell in `bin/grkr`** (measured at tip; see §3 for detailed inventory):
- `process_issue` (~166 LOC body) is the GitHub orchestrator.
- `ensure_test_checkpoint` (~110 LOC) + `write_test_checkpoint*` (~63+33).
- `publish_issue_changes` (~57 LOC).
- `ensure_checkpoint_stage` + comment helpers (~54+).
- Line-limit, PR body, codex run, completion comment, attach/cleanup, usage, etc.
- Sources: `doctor.sh`, `grkr-project-status.sh`, `grkr-issue-workflow.sh`, `lib/refusal_paths.sh`, `lib/task_progress.sh`, `lib/linear_issue.sh`, `grkr-task-slug.sh`, `grkr-templates.sh`.

**Linear path** (complete for research→plan→decision→implement→test→publish+complete + guarded mutate):
- Lives in `bin/lib/linear_issue.sh` (~923 LOC — near hard limit).
- Reuses many shared thin delegates (`prepare_issue_worktree`, `stage_relevant_issue_files`, `build_command_list`, `run_test_stage_hook`, `generate_linear_implement_commit_message`, `write_test_checkpoint_with_header`, `mark_task_progress_complete`, `run_progress_cli`, `checkpoint_marker`, etc.).
- Never calls GitHub label edits or issue comments for Linear items.
- `process_linear_issue` mirrors the GitHub tail but with Linear header wording and dry-run Linear mutation planning + optional guarded apply.

**GitHub `process_issue` flow at tip (high-level)**:
1. Validate + `gh issue view` JSON.
2. `task_slug`, `TASK_DIR`, `progress.json`, meta/context.
3. `ensure_checkpoint_stage` (research + plan) — gh comment + local .md.
4. `prepare_issue_worktree`.
5. Write decision prompt + `run_codex_prompt` + `run_decision_gate` → proceed|refuse.
6. Refuse: cleanup, attach logs, return.
7. `move_issue_to_in_progress`.
8. Write issue prompt + `run_codex_prompt` (implement) → `implementation.log`.
9. `detect_implementation_refusal` → `handle_implementation_refusal` path (reuses refusal_paths + decision_gate refuse surface).
10. `ensure_publishable_file_sizes` (stage + line-limit remediation loop via codex append).
11. `ensure_test_checkpoint` (run_test_stage_hook + build_command_list + exec in worktree + write + gh comment + progress).
12. `publish_issue_changes` (stage, commit via Gleam hook, push, pr create/edit, labels "implemented"/"todo").
13. `mark_task_progress_complete`, `move_issue_to_done`, `post_completion_comment`, attach logs.

**Already extracted patterns to mirror** (from grkr-issue-workflow + Linear slices):
- Gleam CLI + thin sh wrapper + `bin/grkr` calls thin fn (or direct `gleam run -m`).
- Provider-aware hooks live in Gleam (e.g. `implement_stage` commit-message `--provider linear`).
- Shared body writers parameterized by header (e.g. `write_test_checkpoint_with_header`).
- Heavy exec (codex, gh, test commands) + worktree context + gh posting stay in shell for first slices.

---

## 3. Inventory: every function still thick in `bin/grkr`

Re-verified via source reads + query-provided awk-on-function-bodies table (numbers approximate; body LOC excludes top-level sourcing/usage).

| LOC (approx) | Function | Primary callers | Gleam overlap / already-delegated? | Notes |
|--------------|----------|-----------------|------------------------------------|-------|
| 166 | `process_issue` | `--issue`, `--project` loop | Orchestration only; delegates to many | Main GitHub orchestrator. Largest remaining thick fn. |
| 110 | `ensure_test_checkpoint` | `process_issue` | Reuses `run_test_stage_hook`, `build_command_list`, `write_test_checkpoint_with_header` | gh comment + progress + worktree exec. |
| 63 | `write_test_checkpoint_with_header` | `ensure_test_checkpoint`, Linear `ensure_linear_test_checkpoint` | Shared (header-param) | Extracted in test-stage slice for reuse. |
| 57 | `publish_issue_changes` | `process_issue` | Uses `generate_implement_commit_message`, `stage_relevant...`, `extract_codex_pr_body` | Commit/push/PR/labels. |
| 55 | `usage` | top-level | None | CLI help. |
| 54 | `ensure_checkpoint_stage` | `process_issue` | Uses `write_research...`, `write_plan...` (via templates thin), `run_progress_cli` marker | research/plan gh comment path. |
| 38 | `cleanup_on_exit` | trap | N/A | EXIT trap. |
| 33 | `write_test_checkpoint_file` | `ensure_test_checkpoint` (GitHub only) | Thin wrapper over with_header | GitHub "Issue #N" header. |
| 32 | `ensure_publishable_file_sizes` | `process_issue` | Uses `stage_relevant...`, `collect/check_file_line_limit`, `run_codex_prompt` (append) | Remediation loop. |
| 26 | `resolve_script_path` | top | None | Bootstrap. |
| 24 | `extract_codex_pr_body` | `publish_issue_changes` | Uses `emit_task_log_stream` (Gleam task_log), `ensure_pr_body_limit` | PR body from codex log + "Fixes #N". |
| 20 | `summarize_text` | (PR body helpers) | None | Util. |
| 20 | `run_progress_cli` | many | Thin bridge to `gleam run -m grkr/progress/cli` | marker / linear-* / etc. |
| 19 | `run_codex_prompt` | decision/implement + remediation | Uses `persist_task_log_output` (Gleam) | codex exec + persist. |
| 18 | `post_completion_comment` | `process_issue` | None (body simple) | gh completion comment. |
| 18 | `ensure_pr_body_limit` | extract_* | Uses templates footer + append | 60k char + Fixes footer. |
| 18 | `build_command_list` | test checkpoint (both providers) | None (pure list) | BUILD/TEST or npm test. |
| 16 | `checkpoint_comment_body_from_json` | ensure_* | Uses `checkpoint_marker` (progress) | jq marker find. |
| 15 | `checkpoint_comment_id_from_json` | ensure_* | Same | jq marker find. |
| 15 | `check_file_line_limit` | publish + ensure sizes | Uses collect | Staged >1000 guard. |
| 15 | `attach_issue_logs` | cleanup + explicit | N/A | gh log dump. |
| 13 | `collect_file_line_limit_violations` | check + ensure sizes | git_in_issue_context | Staged files >1000. |
| 11 | `cleanup_test_result_logs` | ensure_test_checkpoint | None | Temp cleanup. |
| 9 | `fetch_issue_comments_json` | ensure_* | None | gh comments. |
| 7 | `checkpoint_marker` | many | Delegates to `run_progress_cli marker` | Progress CLI marker. |

**Other sources sourced by bin/grkr (not "in" grkr but part of thick surface)**:
- `doctor.sh` (221 LOC legacy), `grkr-project-status.sh` (81 LOC thin delegator), `grkr-issue-workflow.sh` (68 LOC thin), `grkr-task-slug.sh` (thin), `grkr-templates.sh` (thin).
- `lib/linear_issue.sh` (~923 LOC — owns `process_linear_issue` + 6 `ensure_linear_*`).
- `lib/task_progress.sh` (176 LOC shared), `lib/refusal_paths.sh` (125 LOC shared).

**Related thin/thick shells**:
- `bin/lib/linear_mutate.sh` (37 LOC — guarded apply helper).
- No other large GitHub-specific orchestration remains outside `process_issue` + the listed helpers.

**Call graph summary (GitHub happy path)**:
`process_issue` → ensure_checkpoint (research/plan) → prepare_worktree → codex + run_decision_gate → (proceed) move_in_progress → codex implement → (no refusal) ensure_sizes → ensure_test_checkpoint → publish_issue_changes → mark_complete + move_done + post_comment.

Refusal and impl-refusal paths go through `refusal_paths.sh` + decision_gate refuse surface (already Gleam).

---

## 4. Target module map + ownership boundaries

**Guiding principle**: Thin `bin/grkr` to launcher + small dispatch + thin delegates only (target < ~400-500 LOC for the GitHub path surface). Heavy codex/gh loops and worktree context may stay shell in early slices; pure formatting, decision, render, marker, and state logic already live in Gleam.

**Preferred locations**:
- `src/grkr/workflow/`: Add focused modules or extend existing (e.g. `publish.gleam` or `github_process.gleam` for pure helpers: PR body formatting without footer, line-limit prompt fragments if pure, commit message already there). Avoid monoliths.
- New or extended CLI surface: `gleam run -m grkr/workflow/github_process` (or subcommand) for any new pure orchestration hooks needed (example: `pr-body`, `test-checkpoint-body`, `line-limit-remediation-prompt`).
- `bin/lib/github_issue.sh` (new, thin): GitHub-specific orchestration extracted from `process_issue` / `ensure_*` / `publish_*` (research/plan/test/publish/complete). Mirrors `linear_issue.sh` structure but for GitHub. `bin/grkr` sources it and calls thin fns.
- Keep `bin/grkr` as the single entry that sources doctor + thin libs + dispatches `--issue` / `--project` / `--linear-issue` / init. It should end up calling:
  - `prepare_issue_worktree`, `stage_relevant...` etc. (already thin via grkr-issue-workflow).
  - `run_decision_gate`, `detect_implementation_refusal` (already).
  - `ensure_github_checkpoint_stage`, `ensure_github_test_checkpoint`, `publish_github_issue_changes`, `post_github_completion_comment` (new thin names or same with provider branches).
- `bin/grkr-templates.sh` + `progress/templates.gleam`: already thin; extend only if a pure renderer is justified (e.g. compact PR body, line-limit prompt body).
- `progress/cli.gleam` + `main.gleam`: already the bridge for markers and future pure renderers.
- Shared neutral libs (`bin/lib/*.sh`): `task_progress.sh` (already), possible future `git_context.sh` or `codex_run.sh` if helpers clearly benefit both providers without growing either `*_issue.sh`.

**Ownership boundaries (Linear vs GitHub)**:
- GitHub owns: gh issue view / comment / edit labels, "Issue #N: title" headers, "Fixes #N" footer, project moves (move_to_in_progress / move_to_done), `process_issue` tail.
- Linear owns: `issue_provider/main fetch-issue`, Linear identifier (no #), "Linear issue ID: title", no GitHub labels, PR from `linear-*` branch (real GitHub PR is acceptable product default), Linear state/comment mutation planning + guarded apply.
- Shared (header-parameterized or provider flag): `write_test_checkpoint_with_header`, `build_command_list`, `run_test_stage_hook`, `ensure_publishable_file_sizes` (context-driven via CURRENT), `stage_relevant_issue_files`, `git_in_issue_context`, `extract_*_pr_body` variants, `mark_task_progress_*`, `checkpoint_marker`, `run_progress_cli`, `generate_*_implement_commit_message`, `run_codex_prompt` + persist, line-limit collect/check.

**Proposed concrete new files (small slices only; created when a vertical concern justifies)**:
- `bin/lib/github_issue.sh` (when first vertical extraction lands, e.g. test or publish helpers).
- `src/grkr/workflow/github_process.gleam` (or `publish.gleam`, `checkpoint.gleam` extension) — only when a pure helper is extracted (not required for first slice).
- Keep changes additive/narrow; do not move everything at once.

**LOC discipline**: If `bin/grkr` or `linear_issue.sh` would exceed 950 during a change, extract a focused helper lib first (AGENTS rule).

---

## 5. Slice order + acceptance per slice

**Core rules for every slice**:
- One vertical concern per slice (e.g. "extract test checkpoint writer + runner for GitHub", "extract publish helpers", "thin process_issue orchestration last").
- GitHub `--issue` path regression-green (all existing GitHub shell tests pass with zero behavior change).
- `gleam build` + `gleam test` + `npm test` green.
- Files ≤1000 LOC (extract before landing if risk).
- Linear untouched unless the slice is a shared helper extraction that both providers already (or will) call.
- Match pattern: Gleam CLI (if pure) + thin sh wrapper + `bin/grkr` calls thin fn (or direct gleam run).
- Default provider remains GitHub; no user-visible flag changes.

**Recommended slice order** (smallest shippable first; each can land independently):

1. **Shared header extraction hygiene (optional pre-slice)**: Ensure `write_test_checkpoint_with_header` + `build_command_list` + `extract_*_pr_body` variants + `ensure_publishable_file_sizes` are clearly reusable and documented. (May be a no-op or tiny doc in grkr-issue-workflow / templates.)
2. **Extract GitHub test checkpoint runner** (`ensure_github_test_checkpoint` or narrow provider branch inside existing) into `bin/lib/github_issue.sh` (new) or keep in grkr with thin call. Wire `bin/grkr` to delegate. GitHub test path unchanged externally.
3. **Extract GitHub publish helpers** (`publish_github_issue_changes`, PR body with Fixes footer, label edits) into `bin/lib/github_issue.sh`. Reuse `ensure_publishable_file_sizes`, Gleam commit hook, task_log emit. GitHub path 100% parity.
4. **Extract GitHub research/plan checkpoint** (`ensure_github_checkpoint_stage` + comment posting) to same lib or thin delegate. Reuse templates + progress marker.
5. **Extract completion surface** (`post_github_completion_comment`, move_to_done, gh label finalization) — small.
6. **Thin `process_issue` orchestration last**: Replace inlined bodies with calls to the extracted `ensure_github_*` / `publish_github_*` fns. `bin/grkr` becomes thin launcher for GitHub path. Keep heavy loops in the lib or in grkr as "orchestration glue" only if they are gh/codex context-heavy.
7. **Optional pure Gleam surface** (later): `workflow/github_process.gleam` or `publish.gleam` for PR body formatting, line-limit prompt fragments, etc., once shell is thin and parity proven.

**Per-slice acceptance (template)**:
- GitHub happy path (smoke) + refusal + impl-to-refusal + line-limit + pr-body-limit + checkpoint-resume reach the same artifacts + gh calls + progress.json + exit codes as before.
- No change to Linear paths or linear_issue.sh (unless explicit shared extraction slice).
- All listed regression tests green.
- No file >1000 LOC.
- `gleam build/test` + `npm test` green.
- README + gleam-migration updated with thin note (per AGENTS) only on functional slices.

---

## 6. LOC risk: `linear_issue.sh` 923 — extraction rules

`bin/lib/linear_issue.sh` is at ~923 LOC (query measurement) and owns the entire Linear `--linear-issue` orchestration (`process_linear_issue` + 6 `ensure_linear_*` + meta/progress writers + mutation planning + publish complete).

**Mandatory rules before any Linear growth**:
- If a change would push `linear_issue.sh` >950 LOC, extract first.
- Shared helpers that both providers use (or will use) **must** be extracted to a neutral location **before** being added to either `*_issue.sh`:
  - Current good examples: `task_progress.sh`, `write_test_checkpoint_with_header` (in grkr, called by both), `build_command_list`, `run_test_stage_hook`, `stage_relevant_issue_files`, `ensure_publishable_file_sizes`.
- When a helper is only GitHub-specific (gh labels, "Fixes #N", "Issue #N" header, project moves), it belongs in a GitHub lib (`bin/lib/github_issue.sh` or inline in grkr under thin fns) — do not put in linear_issue.sh.
- When a helper is only Linear-specific (Linear identifier wording, `linear-state`/`linear-comment-mutation` planning, no-labels PR body), keep in linear_issue.sh.
- Prefer adding a 1-line thin wrapper in the provider lib that calls a shared fn in `bin/lib/` or delegates to Gleam rather than copying bodies.
- `bin/grkr` itself must not grow past 950 without extraction (it sources linear_issue.sh; any new shared orchestration glue should go to a lib).

**Safe pattern seen in prior slices**:
- Extracted `write_test_checkpoint_with_header` (shared body) while leaving GitHub `write_test_checkpoint_file` and Linear header call site unchanged externally.
- `mark_task_progress_complete` is provider-agnostic and lives in `task_progress.sh`.

Violation of these rules blocks the slice.

---

## 7. Non-goals (restated for implementers)

- No user-facing behavior change for `--issue` or any flag.
- GitHub remains default `GRKR_ISSUE_PROVIDER`.
- No supervisor/picker changes.
- No live Linear mutation behavior change.
- Do not grow linear_issue.sh without prior shared extraction.
- Do not edit product Gleam or shell logic in the design phase.
- No new public surface that alters the GitHub contract.

---

## 8. Spec refs + AGENTS constraints

**Must read for implementers**:
- `spec/parts/17-issue-workflow-overview.md`
- `spec/parts/22-stage-3-implement-or-refuse-decision-gate.md`
- `spec/parts/25-stage-4-implement.md`
- `spec/parts/26-stage-5-test.md`
- `spec/parts/08-worker-scripts.md`
- `spec/parts/38-acceptance-criteria.md`
- `spec/parts/39-recommended-implementation-order.md`
- `spec/parts/31-test-checkpoint.md`
- `spec/parts/32-detailed-issue-workflow-pseudocode.md` (for flow context)
- AGENTS.md (≤1000 LOC, thin bin/, update README after func change, spec/parts canonical, GitHub default, shared delegates, preserve shell conventions, run sync-spec only if parts touched)

Existing design style to mirror exactly: `docs/design-linear-*.md` (goal/non-goals, current state with tip, modules/files, wire protocol, progress.json parity, fixtures/test plan, risks, product decisions, slice acceptance, out-of-scope, recommended order, paste-ready card brief).

---

## 9. Explicit slice table

| Title | Primary files | Deps | Acceptance | Est. LOC delta (net) |
|-------|---------------|------|------------|----------------------|
| Shared test/publish header hygiene (pre) | bin/grkr, bin/grkr-templates.sh, bin/grkr-issue-workflow.sh (docs/comments) | Existing write_*_with_header, extract_linear_* | No behavior change; clearer reuse docs; tests green | 0–5 |
| Extract GitHub test checkpoint to lib | bin/lib/github_issue.sh (new), bin/grkr, bin/grkr-issue-workflow.sh | build_command_list, run_test_stage_hook, write_test_checkpoint_with_header, task_progress, gh comment posting | GitHub ensure_test_checkpoint external contract identical; Linear untouched; all GitHub tests green; ≤1000 | +80–120 in lib; –30–50 in grkr |
| Extract GitHub publish + PR body + labels | bin/lib/github_issue.sh, bin/grkr | ensure_publishable_file_sizes, stage_*, generate_implement_*, extract_codex_pr_body, task_log emit, gh pr/issue edit | publish_issue_changes parity (same commits, PRs, labels, failures); no Linear impact; tests (line-limit, pr-body, smoke) green | +60–90 in lib; –20–40 in grkr |
| Extract GitHub research/plan checkpoints | bin/lib/github_issue.sh (or extend), bin/grkr | write_research/plan via templates thin, ensure_checkpoint_stage, gh comment, checkpoint json helpers | Research/plan gh posts + resume + progress identical; GitHub regression green | +40–70; –20 in grkr |
| Extract completion surface | bin/lib/github_issue.sh, bin/grkr | post_completion_comment, mark_complete, move_to_done | Completion comment + Done move + logs identical | +20–30; –10 |
| Thin process_issue orchestration | bin/grkr (main), bin/lib/github_issue.sh | All above extracted fns | process_issue body becomes thin sequence of ensure_*/publish_* calls; GitHub happy + refuse + failure paths green; no behavior change | –80–120 in grkr |
| (Optional later) Pure Gleam github process surface | src/grkr/workflow/github_process.gleam (or publish.gleam), thin delegate | Templates, progress/cli | Only if a pure helper is justified after shell is thin; parity tests added | +30–80 Gleam (pure) |

Each row is a candidate single-PPR card. Earlier rows unblock later rows.

---

## 10. Recommended first implement slice (for kanban factory)

**First slice**: "Extract GitHub test checkpoint runner + writer wiring to thin lib" (or the hygiene pre-slice if cleaner).

Rationale:
- Test checkpoint is already partially shared (`write_test_checkpoint_with_header` exists because of Linear test slice).
- Vertical, small, high signal (exercises worktree exec, build_command_list, gh comment, progress, marker).
- Does not touch publish, line-limit remediation, or PR body (lower blast radius).
- Creates `bin/lib/github_issue.sh` pattern for subsequent extractions.
- GitHub regression surface (smoke, checkpoint-resume, line-limit, refusal, impl-to-refusal) exercises the path.
- Linear test path continues to call the shared header writer; no change required in linear_issue.sh.

See §12 for paste-ready card title + /goal brief.

---

## 11. Follow-up implement card titles (ready to spawn; do not implement here)

- "Extract GitHub publish helpers (commit/push/PR/labels) to bin/lib/github_issue.sh"
- "Extract GitHub research/plan checkpoint posting to github_issue lib"
- "Extract GitHub completion surface (post comment + project Done) to github_issue lib"
- "Thin bin/grkr process_issue to launcher + delegates after GitHub lib extractions"
- "Add pure Gleam github_process helpers (optional, after shell thin)"
- "LOC hygiene + shared git/codex helpers extraction (if bin/grkr or linear_issue.sh approach 950)"

Factory can spawn these in order after the first lands and is verified.

---

## 12. Regression surface (tests that must stay green)

All of these exercise GitHub `--issue` paths and must pass with identical behavior (logs, artifacts, gh calls, progress.json, exit codes, worktree state) after every slice:

- `test/grkr-smoke.sh` (full happy path to PR + complete comment)
- `test/grkr-checkpoint-resume.sh` (research/plan/test resume from comment markers)
- `test/grkr-refusal.sh` (decision-gate refusal + checkpoint + progress)
- `test/grkr-implementation-to-refusal.sh` (during-impl refusal conversion)
- `test/grkr-line-limit.sh` (remediation loop + publish abort)
- `test/grkr-pr-body-limit.sh` (compact PR body + Fixes footer)
- `test/grkr-progress-cli.sh` (marker + progress helpers)
- Linear tests must not regress (they rely on shared helpers): `test/grkr-linear-issue-implement.sh` (full to complete), `test/grkr-linear-refuse-progress.sh`, `test/grkr-linear-issue-mvp.sh` (historical)
- `test/grkr-dirty-worktree-warning.sh`, `test/grkr-branch-exists.sh`, `test/grkr-init.sh`, `test/grkr-installed-layout.sh` (infrastructure)
- `npm test` (shell harness) + `gleam test` + `gleam build` clean on every slice.

No new GitHub-specific e2e required for thinning; reuse existing fixtures + gh stubs.

---

## 13. Paste-ready first implement card brief with /goal

```
/goal Extract GitHub test checkpoint (ensure_test_checkpoint + write path) to thin bin/lib/github_issue.sh (or narrow delegate) while keeping external contract 100% identical for --issue. Create shared reuse pattern for later publish/checkpoint extractions. GitHub regression green; Linear untouched (continues to use write_test_checkpoint_with_header). bin/grkr becomes slightly thinner caller.

Context: tip 8526d74 (post #107). bin/grkr ~875 LOC still thick; process_issue 166 + ensure_test_checkpoint 110 largest remaining. Linear full (publish+complete + guarded mutate) already in linear_issue.sh ~923 (near limit). Shared header writer already exists from design-linear-test-stage. grkr-issue-workflow.sh is 68 LOC thin Gleam delegate precedent.

Read (must):
- AGENTS.md (≤1000, thin bin/, shared delegates, GitHub default, update README on func change, spec canonical)
- spec/parts/17-issue-workflow-overview.md, 26-stage-5-test.md, 31-test-checkpoint.md, 08-worker-scripts.md, 39-recommended..., 32-pseudocode
- docs/design-linear-test-stage.md (how header was shared) + design-linear-publish-stage.md + this design doc
- bin/grkr (ensure_test_checkpoint ~412, write_test_checkpoint*, build_command_list, cleanup_test_result_logs, process_issue call site ~825, gh comment posting)
- bin/grkr-issue-workflow.sh (run_test_stage_hook delegate + thin pattern)
- bin/lib/task_progress.sh (update_stage, mark_failed)
- bin/grkr-templates.sh (if any test body render moves)
- test/grkr-smoke.sh, grkr-checkpoint-resume.sh, grkr-line-limit.sh, grkr-refusal.sh, grkr-implementation-to-refusal.sh, grkr-pr-body-limit.sh, grkr-linear-issue-implement.sh (must stay green)
- src/grkr/workflow/test_stage.gleam + progress/* (for hook/marker surface)

Acceptance (one PR):
- GitHub --issue test path produces identical test.md (marker + "Issue #N: title"), gh comment, progress stages.test=done|failed, exit codes, worktree exec, command list as before.
- New/updated shell test or evolved smoke exercises the path; gh stub constraints preserved.
- Linear path unchanged (still reaches STAGE=complete; uses shared header writer).
- No file >1000 LOC; bin/grkr net thinner or neutral.
- gleam build + gleam test + npm test green.
- README + docs/gleam-migration thin note added (per AGENTS).
- No behavior change to user flags or GitHub contract.
- No Linear mutation or supervisor changes.

Non-goals: publish extraction, Linear changes, new flags, spec edits.

Use Grok Build CLI --mode implement (or full). After changes run gleam build + relevant tests + the listed regression shells. Follow AGENTS exactly.
```

---

## 14. Acceptance for THIS design card

- Design doc exists at `docs/design-github-process-issue-thinning.md` with:
  - Full inventory + callers + Gleam overlap.
  - Target module map + concrete proposed files + ownership vs Linear.
  - Ordered slice table with acceptance per slice.
  - Linear 923 LOC extraction rules.
  - Explicit non-goals.
  - Spec refs + AGENTS alignment.
  - Regression surface list.
  - Recommended first slice clearly called out.
  - Follow-up card titles listed.
  - Paste-ready implement brief.
- Optional: one-line pointer added to README.md or docs/gleam-migration.md "Still forward-looking" / Remaining section (docs-only, safe).
- No product code or behavior changes in bin/, src/, or test/.
- Design-only commit on `docs/github-process-issue-thinning` (or files left ready).

**Post-write note (design phase)**: A clean `git status --porcelain` (ignoring pre-existing untracked `.grkr/kanban-cron-*` and `.grkr/e2e-logs/`) should show only the new design doc (and optional one-line docs pointer). No edits to product logic.

---

**End of design document.**

Next: kanban factory spawns the first implement card using the brief in §12. Implement worker writes self-contained prompt (this design + listed files + AGENTS + spec parts), runs Grok Build CLI `--mode implement`, verifies `gleam build` / tests / regression shells, and completes the card. Subsequent slices follow the table.

**Design-only — no product code was edited.**