# Design: Concern-split `bin/lib/linear_issue_stages.sh` (LOC hygiene)

**Status**: Design-only (plan agent / Hermes finish path after Grok Build CLI 503). No product code edits.  
**Reference tip**: origin/main @ **deb0acc** (`feat: add easy Docker image and Helm chart for grkr deploy (#166)`). Product lineage before deploy: **cfdfb76** / PR #164 resolve_pr LOC hygiene; Linear stages file still **727 LOC** (post final Linear thin sequencer **f6b34d4** / PR #133).  
**Prior design artifacts**: `docs/design-linear-issue-thinning.md` (Linear extract slices 1–5 complete @ f6b34d4), `docs/design-grkr-shared-helpers-extract.md` (shared complete through attach + coding-agent bridge), `docs/design-github-issue-lib-thinning.md` (GitHub vertical optional thins), stage designs (`design-linear-{test,publish,implement,live-mutate}-stage.md`). Architectural analogy: supervisor `phases.gleam` thin dispatcher + concern modules (PR #154), progress/main facade (PR #156), resolve_pr/main facade (PR #164).  
**Gap addressed**: After GitHub process_issue thinning, Linear thinning into one stages file, and shared helpers leave `bin/grkr` thin, the **largest remaining shell vertical** is `bin/lib/linear_issue_stages.sh` (~727 LOC). It is under the AGENTS.md hard 1000 LOC limit but dominates shell maintainability. Next high-value slice: **concern-split** into focused stage modules + thin facade (source chain), **zero behavior change**.  
**Date**: 2026-07-20  
**Kanban**: t_f059093f  
**Note on authoring path**: Card required Grok Build CLI `--mode design`; xAI returned HTTP 503 on two attempts (`/tmp/kanban-grok-t_f059093f.log`). Design completed from live tip inventory so the board is not blocked on a transient API outage.

---

## 1. Goal / non-goals

### Goal

Produce this design doc so implementers can ship ordered PRs that:

- Concern-split `bin/lib/linear_issue_stages.sh` into focused sibling modules (test / publish / refusal / research-plan / decision-implement) plus a **thin facade** that preserves today’s public function names.
- Keep `process_linear_issue` in `bin/lib/linear_issue.sh` as the thin sequencer (unchanged call sites).
- Keep every file ≤1000 LOC with comfortable headroom; prefer splits **before** any growth.
- Preserve external contracts: `--linear-issue` logs, artifacts, exit codes, progress.json, mutation dumps, GitHub PR from `linear-*`, `GRKR_LINEAR_MUTATE` default OFF.
- Do **not** grow `bin/lib/github_issue.sh` or `bin/lib/issue_shared.sh` as dumping grounds for Linear stage bodies.

### Non-goals (explicitly out of scope for this design and its children)

- No behavior change to user-facing flags, `--linear-issue` / `--issue` contracts, or mutation defaults.
- `GRKR_ISSUE_PROVIDER` default remains GitHub; no picker/supervisor rewrite.
- No live Linear mutation semantics change (`GRKR_LINEAR_MUTATE=1` remains opt-in; soft default; STRICT optional as today).
- Do not move Linear concerns into `github_issue.sh` or dump Linear-only bodies into `issue_shared.sh`.
- Do not rewrite `process_linear_issue` as pure Gleam in this work.
- Do not rename public functions (`ensure_linear_*`, `run_linear_*`, `handle_linear_*`) — ambient bash resolution and tests depend on stable names.
- Do not edit product Gleam or shell logic in the **design** phase.
- No new public flags or provider switches.
- No mandatory live e2e (`test/e2e-linear-live.sh` remains optional/token-gated).
- Optional/low-ROI further thinning of `github_issue.sh` checkpoint json helpers is **out of scope** (separate design if ever needed).

Preserve (per AGENTS + prior designs):

- Thin shell conventions in `bin/` and `test/`.
- Every file ≤1000 LOC.
- `spec/parts/` canonical; design-only: no forced spec content edits (sync optional if parts touched later).
- Shared neutral helpers stay in `issue_shared.sh` / `task_progress.sh` / `refusal_paths.sh` / thin Gleam delegates.
- Heavy orchestration (coding agent, gh, worktree, bash loops) may stay shell; pure formatters already largely Gleam.

---

## 2. Current state (cite files + tip)

### Re-measured LOC at tip deb0acc

| File | LOC | Role |
|------|-----|------|
| `bin/lib/linear_issue_stages.sh` | **727** | Linear stage bodies + decision/implement orchestration ← **this target** |
| `bin/lib/github_issue.sh` | 542 | GitHub vertical (optional further thins low-ROI) |
| `bin/lib/issue_shared.sh` | 387 | Neutral shared (coding agent bridge, progress CLI, publish guard, test write, attach) |
| `bin/lib/linear_issue.sh` | 329 | Thin sequencer + load/meta/bootstrap + sources mutate+stages |
| `bin/grkr` | 198 | Thin launcher + GitHub `process_issue` sequencer + dispatch |
| `bin/lib/task_progress.sh` | 176 | Shared progress.json helpers |
| `bin/lib/refusal_paths.sh` | 125 | Shared refusal path helpers |
| `bin/lib/linear_mutate.sh` | 62 | Guarded `maybe_apply_linear_mutation` only |

Header of stages file is ~74 LOC of historical slice documentation (slices 1–5 from prior thinning).

### Source chain (must preserve)

`bin/grkr` sources (order):

1. doctor, project-status, issue-workflow, refusal_paths, task_progress  
2. **`issue_shared.sh`** (before providers)  
3. **`linear_issue.sh`**, which sources:
   - `linear_mutate.sh` (first — `maybe_apply_linear_mutation`)
   - **`linear_issue_stages.sh`** (second — all stage fns)
4. `github_issue.sh`, task-slug, templates  

Bash resolves functions at **call time**. Tests that source only `linear_issue.sh` (e.g. refuse-progress after stubbing `run_progress_cli`) still get stages via the internal `.` of stages.

### What prior work already did

- **Linear thinning** (`design-linear-issue-thinning.md`, PRs #125–#133): moved stage bodies out of fat `linear_issue.sh` (~923) into **one** `linear_issue_stages.sh`, then thinned `process_linear_issue` to a sequencer. Net: sequencer thin, stages fat.
- **Shared helpers** (`design-grkr-shared-helpers-extract.md`, PRs #136–#144 + coding agent #149–#150): common bridges live in `issue_shared.sh`; stages call them ambiently.
- **Gleam facade hygiene** (phases #154, progress/main #156, handle_comment #158, comment_handler #160, resolve_pr #164): thin public entry + concern modules — **the pattern this design applies to shell stages**.

### Linear path flow (unchanged contract)

1. `bin/grkr --linear-issue ID` → `process_linear_issue`
2. `bootstrap_linear_issue_task` (load + meta + issue-context + progress seed) — stays in `linear_issue.sh`
3. `ensure_linear_checkpoint_stage` research + plan
4. `run_linear_decision_stage` → if not proceed: `handle_linear_decision_refuse` → return
5. `run_linear_implement_stage` (in-progress + implement + optional impl-refusal → `ensure_linear_refusal_checkpoint`)
6. `ensure_linear_test_checkpoint`
7. `ensure_linear_publish_complete`
8. Finalize echoes (`STAGE=complete`, TASK_DIR, WORKTREE)

GitHub PR is created from `linear-*` branch; Linear comments/state are planned (and optionally applied via mutate). No gh issue label/comment for Linear items.

---

## 3. Inventory: every function in `linear_issue_stages.sh`

Re-verified via definition scan at tip deb0acc. Approx body LOC includes surrounding comments immediately above the function where they document only that function.

| approx LOC | Function | lines (approx) | Callers | Ambient deps (call-time) | Gleam / shared overlap | Notes |
|-----------:|----------|----------------|---------|--------------------------|------------------------|-------|
| 160 | `ensure_linear_test_checkpoint` | 75–234 | `process_linear_issue` | `build_command_list`, `run_test_stage_hook`, `write_test_checkpoint_with_header`, `run_progress_cli`, `checkpoint_marker`, `cleanup_test_result_logs`, `mark_task_progress_failed`, `update_task_progress_stage`, `maybe_apply_linear_mutation`; globals `CURRENT_ISSUE_WORKTREE`, `LINEAR_STATE_TEST_ID` | progress CLI linear-comment/state mutations; shared test write | Largest vertical; resume-safe; Linear header on test.md |
| 157 | `ensure_linear_publish_complete` | 235–391 | `process_linear_issue` | `ensure_publishable_file_sizes`, `check_file_line_limit`, `stage_relevant_issue_files`, `git_in_issue_context`, `generate_linear_implement_commit_message`, `extract_linear_codex_pr_body`, `mark_task_progress_complete`, `run_progress_cli`, `maybe_apply`; globals worktree/REPO/MAIN_BRANCH/LINEAR_STATE_DONE_ID | templates / progress for PR body + complete comment + Done | PR from linear-*; complete comment **before** Done; no labels |
| 116 | `ensure_linear_refusal_checkpoint` | 392–507 | `process_linear_issue` (via decision/impl paths), **`run_linear_implement_stage`**, **direct** `test/grkr-linear-refuse-progress.sh` | `run_progress_cli` (plan-linear-refusal / render-refusal / mutations), `mark_task_progress_refused`, `maybe_apply` | refusal/flow + progress linear | Soft by default; no gh |
| 58 | `ensure_linear_checkpoint_stage` | 508–565 | `process_linear_issue` (research + plan ×2) | `write_research_checkpoint_file`, `write_plan_checkpoint_file`, `run_progress_cli`, `update_task_progress_stage`, `maybe_apply` | templates + progress | Stage arg selects research vs plan |
| 60 | `ensure_linear_implement_in_progress` | 566–625 | **`run_linear_implement_stage` only** (not sequencer directly) | `run_progress_cli` linear-state / linear-state-mutation, `update_task_progress_stage`, `maybe_apply` | progress | Plans In Progress; marks implement_or_refuse done |
| 33 | `run_linear_decision_stage` | 626–658 | `process_linear_issue` | `prepare_issue_worktree`, `write_decision_prompt_file`, `run_codex_prompt`, `run_decision_gate`; sets `IMPLEMENTATION_DECISION`, `CURRENT_ISSUE_WORKTREE` | decision_gate + coding agent bridge | Forces `GRKR_ISSUE_PROVIDER=linear` for gate |
| 17 | `handle_linear_decision_refuse` | 659–675 | `process_linear_issue` | `cleanup_issue_worktree` | decision gate already did refuse side effects | Cleanup + echoes only |
| 52 | `run_linear_implement_stage` | 676–727 | `process_linear_issue` | `ensure_linear_implement_in_progress`, `write_issue_prompt_file`, `run_codex_prompt`, `detect_implementation_refusal`, `normalize_refusal_class`, `extract_refusal_reasoning`, `ensure_linear_refusal_checkpoint`, `cleanup_issue_worktree` | implement + refusal | Sets `LINEAR_IMPL_REFUSED`; leaves worktree/prompt for test/publish on success |

**Not in stages** (stay in `linear_issue.sh`): `linear_issue_project_root`, `run_issue_provider_cli`, `decode_shell_assignment_value`, `load_linear_issue_assignments`, `write_linear_task_meta_env`, `ensure_linear_task_progress_file`, `bootstrap_linear_issue_task`, `process_linear_issue`.

**Not in stages** (stay in `linear_mutate.sh`): `maybe_apply_linear_mutation` and apply helpers.

---

## 4. Target module map + ownership boundaries

### Recommended shape: thin facade + five concern modules

Mirror Gleam facade hygiene and the existing “sibling lib” pattern, but split the **fat** stages file rather than inventing a second provider.

| Path | Owns | Est. LOC after split |
|------|------|----------------------|
| `bin/lib/linear_issue_stages.sh` | **Facade only**: short header + ordered `.` of children. **No function bodies.** Keeps the stable path that `linear_issue.sh` already sources. | ~25–40 |
| `bin/lib/linear_issue_stages_test.sh` | `ensure_linear_test_checkpoint` | ~170–190 |
| `bin/lib/linear_issue_stages_publish.sh` | `ensure_linear_publish_complete` | ~165–185 |
| `bin/lib/linear_issue_stages_refusal.sh` | `ensure_linear_refusal_checkpoint` | ~125–145 |
| `bin/lib/linear_issue_stages_research_plan.sh` | `ensure_linear_checkpoint_stage` + `ensure_linear_implement_in_progress` | ~130–150 |
| `bin/lib/linear_issue_stages_implement.sh` | `run_linear_decision_stage` + `handle_linear_decision_refuse` + `run_linear_implement_stage` | ~110–130 |

**Why five children (not one mega-move):**

- Matches historical slice seams already documented in the stages header (test / publish / refusal / research-plan / decision-implement).
- Each child stays well under 300 LOC → room for comments without approaching 1000.
- Independent shippable PRs with focused regression surfaces (e.g. refuse test hits refusal module hard).
- Facade keeps **one** source path for `linear_issue.sh` and for tests that only source `linear_issue.sh`.

**Alternative considered (fewer files):**

- Three modules: `{test_publish, refusal_research, decision_implement}` — fewer files, larger blobs (~300+), weaker PR isolation.
- Rejected as primary: headroom and reviewability worse; five files is still a small surface for shell.

**Alternative considered (no facade; linear_issue sources each child):**

- Works, but forces every test/copy helper (`test-copy-grkr-lib.sh`) and comment in `linear_issue.sh` to list five paths. Facade is simpler and matches “stable entry” used in Gleam splits.

### Source order inside the facade

```text
# linear_issue_stages.sh (facade) — after linear_mutate.sh already sourced by linear_issue.sh
. ".../linear_issue_stages_refusal.sh"       # needed by implement path; safe early
. ".../linear_issue_stages_research_plan.sh" # implement_in_progress used by implement
. ".../linear_issue_stages_implement.sh"     # decision + implement orchestration
. ".../linear_issue_stages_test.sh"
. ".../linear_issue_stages_publish.sh"
```

Order among independent modules is flexible; **refusal + research_plan before implement** is required because `run_linear_implement_stage` calls `ensure_linear_implement_in_progress` and `ensure_linear_refusal_checkpoint`. With call-time resolution, any order works if all are sourced before `process_linear_issue` runs — still prefer dependency-before-depender for readability and for any future top-level side effects.

Facade resolution: same BASH_SOURCE-relative pattern as today’s `STAGES_LIB_CANDIDATE` / mutate candidate.

### Ownership boundaries

| Surface | Ownership rule |
|---------|----------------|
| `linear_issue.sh` | Sequencer + load/bootstrap/meta/progress seed + source mutate then **stages facade**. Do not re-absorb stage bodies. |
| `linear_issue_stages*.sh` | Linear-only stage bodies and Linear decision/implement orchestration. |
| `linear_mutate.sh` | Guarded apply only; sourced **before** stages. |
| `issue_shared.sh` | Provider-agnostic bridges only. **No** Linear stage moves here. |
| `github_issue.sh` | GitHub-only. **No** Linear stage moves; no shared growth from this work. |
| `bin/grkr` | Unchanged for this work (already sources linear_issue). |

### Stable public API (do not rename)

- `ensure_linear_test_checkpoint`
- `ensure_linear_publish_complete`
- `ensure_linear_refusal_checkpoint`
- `ensure_linear_checkpoint_stage`
- `ensure_linear_implement_in_progress`
- `run_linear_decision_stage`
- `handle_linear_decision_refuse`
- `run_linear_implement_stage`

Call sites in `process_linear_issue` and `test/grkr-linear-refuse-progress.sh` stay byte-identical in meaning (args, exit codes, globals).

### test-copy / fixture packaging

`test/test-copy-grkr-lib.sh` (or equivalent) must copy **facade + all children** (or the whole `bin/lib/linear_issue_stages*.sh` glob). Verify and update in the first implement slice that introduces a second file. Fail closed: if a child is missing, facade `.` should error clearly rather than silently omit functions.

---

## 5. Ordered shippable slice table (smallest first)

Each slice acceptance:

- Files ≤1000 LOC (all new/edited shells).
- `bash -n` on every touched `.sh`.
- `gleam build` + `gleam test` green.
- Linear regression green: implement, mvp, refuse-progress, apply-matrix.
- GitHub non-regression: at least `test/grkr-smoke.sh` + full `npm test` when any shared/copy path touched; otherwise smoke + Linear suite minimum, prefer full `npm test`.
- Zero intentional behavior change; no mutate default change; no new flags.
- README + `docs/gleam-migration.md` thin “Next product thinning” note on functional slices (per AGENTS).
- Empty or trivial diff on `github_issue.sh` / `bin/grkr` unless copy helper forces a one-line mention.

| # | Title | Primary files | What moves | Acceptance highlight | Est. LOC delta |
|---|-------|---------------|------------|----------------------|----------------|
| **0** | Design only (this doc) | `docs/design-linear-issue-stages-split.md` | none | Design complete; no product | +doc only |
| **1** | **First implement**: extract refusal vertical to `linear_issue_stages_refusal.sh` + introduce facade sourcing pattern | `linear_issue_stages.sh` (facade begins), new `linear_issue_stages_refusal.sh`, `test-copy-grkr-lib.sh` if needed | Move `ensure_linear_refusal_checkpoint` body **exactly**; facade sources refusal + retains remaining bodies **or** sources refusal then continues defining others in-place for one PR | Refuse-progress direct call green; implement/mvp/apply-matrix green; stages facade path still `linear_issue_stages.sh` | stages file −110–130 net after move; refusal file ~120–140; facade header grows slightly |
| **2** | Extract test checkpoint → `linear_issue_stages_test.sh` | facade + new test module | Exact move of `ensure_linear_test_checkpoint` | implement + mvp green (test.md / mutations) | −150–170 from monolith remainder |
| **3** | Extract publish+complete → `linear_issue_stages_publish.sh` | facade + new publish module | Exact move of `ensure_linear_publish_complete` | implement to STAGE=complete; PR URL parse; Done after complete comment | −150–170 |
| **4** | Extract research/plan + implement_in_progress → `linear_issue_stages_research_plan.sh` | facade + new research_plan module | Exact move of both ensure_* | mvp research/plan artifacts + in-progress mutation dumps | −110–130 |
| **5** | Extract decision/implement orchestration → `linear_issue_stages_implement.sh`; facade becomes source-only | facade + new implement module | Move `run_linear_*` + `handle_linear_decision_refuse`; **no bodies left in facade** | Full happy + refuse + impl-refusal paths; empty bodies in facade | facade ~25–40; implement module ~110–130 |
| **6** (optional) | Header/comment hygiene + README/gleam-migration “stages split complete” | docs + short headers | No logic | Docs accurate tip pins | docs only |

**Why refusal first (not largest test chunk):**

- Smallest high-signal vertical with a **dedicated direct unit-style shell test** (`grkr-linear-refuse-progress.sh`) that sources `linear_issue.sh` → stages.
- Proves facade + multi-file copy packaging before moving the larger test/publish bodies.
- Lower blast radius than test (worktree exec) or publish (gh pr create) for establishing the pattern.
- Matches “smallest first” guidance in the kanban card while still creating real headroom (~116 LOC out).

**If implementer prefers largest-first:** swapping slice 1 and 2 (test first) is acceptable with rationale in the PR — same end state. Do **not** skip the facade/copy-helper work in whichever lands first.

### LOC risk rules

- Block any slice that would leave a single stages* file >~900 without a further split plan.
- Do not add Linear stage code to `issue_shared.sh` or `github_issue.sh`.
- Do not fatten `linear_issue.sh` sequencer.
- If `test-copy-grkr-lib.sh` is incomplete, fix in the same PR as the first multi-file split (not a follow-up surprise).

### Safe move pattern (every product slice)

1. Create new file with **exact** function body + its local comment block (no refactors).
2. Wire facade `.` of new file (and keep remaining definitions working).
3. Delete moved definition from old home (no thin wrapper left behind).
4. Update headers (slice N, ambient deps).
5. `bash -n` + Linear regression + gleam + npm.
6. README + gleam-migration one-liner.

---

## 6. Regression surface

### Linear-specific (must stay green every product slice)

- `test/grkr-linear-issue-implement.sh` — full happy path to `STAGE=complete`; PR from `linear-*`; no gh issue edits; complete comment + Done plan; no-changes path still completes.
- `test/grkr-linear-issue-mvp.sh` — research/plan + decision + implement + test + publish/complete smoke.
- `test/grkr-linear-refuse-progress.sh` — direct `ensure_linear_refusal_checkpoint`; refusal.md; planned comment + Backlog; progress refused; **sources linear_issue.sh only** (must still resolve stages via facade).
- `test/grkr-linear-apply-matrix.sh` — hermetic apply matrix (dry-run, skipped-no-token, applied, skipped-already, failed, name-only).

### GitHub / cross-cutting (non-regression)

From `scripts/npm-test.sh` chain (full `npm test` preferred):

- `test/grkr-coding-agent-swap.sh`, `grkr-init.sh`, `grkr-installed-layout.sh`
- `test/grkr-smoke.sh`, `grkr-checkpoint-resume.sh`, `grkr-branch-exists.sh`
- `test/grkr-refusal.sh`, `grkr-implementation-to-refusal.sh`
- `test/grkr-progress-cli.sh`, `grkr-line-limit.sh`, `grkr-pr-body-limit.sh`
- `test/grkr-dirty-worktree-warning.sh`
- worker/robot-main suite (`worker-sync-main`, `worker-pick-issue`, `worker-help`, `robot-main-*`, `worker-resolve-pr`, …)

### Build

- `gleam build` + `gleam test` (expect ~320 tests at recent tips; re-count on tip)
- `bash -n` on all touched shells

### Optional / not required for CI slice gate

- `test/e2e-linear-live.sh` (live token)
- Gleam `test/grkr/progress/linear_mutation_test.gleam` still runs under `gleam test` when present

Behavioral invariants: identical logs/artifacts/exit codes/progress.json/mutation dumps/worktree cleanup; GitHub path empty diff preferred.

---

## 7. Spec + AGENTS citations

| Ref | Why |
|-----|-----|
| `AGENTS.md` | ≤1000 LOC; thin `bin/`; README on functional change; `spec/parts/` canonical; shell conventions |
| `spec/parts/17-issue-workflow-overview.md` | End-to-end issue workflow |
| `spec/parts/21-refusal-assessment.md` | Refusal assessment inputs |
| `spec/parts/22-stage-3-implement-or-refuse-decision-gate.md` | Decision gate |
| `spec/parts/23-refusal-flow.md` / `24-implementation-refused.md` | Refuse + impl-refusal |
| `spec/parts/25-stage-4-implement.md` | Implement stage |
| `spec/parts/26-stage-5-test.md` / `31-test-checkpoint.md` | Test checkpoint |
| `spec/parts/38-acceptance-criteria.md` | Acceptance |
| `spec/parts/39-recommended-implementation-order.md` | Order / status notes |
| Prior designs listed in header | Pattern + non-goals continuity |

No spec content change required for pure shell LOC split (behavior-identical).

---

## 8. Recommended first implement slice + rationale

**First product slice**: Extract `ensure_linear_refusal_checkpoint` into `bin/lib/linear_issue_stages_refusal.sh` and convert `linear_issue_stages.sh` into a **facade that sources the refusal module** while temporarily retaining other function bodies in the facade file (or still defined after the `.` — until later slices move them).

**Rationale**:

1. Smallest complete vertical with dedicated shell coverage (`grkr-linear-refuse-progress.sh`).
2. Establishes multi-file packaging + facade before larger test/publish moves.
3. Real headroom (~116 LOC body) without touching worktree test exec or gh pr create.
4. `run_linear_implement_stage` keeps calling the same function name (call-time resolution).
5. Zero GitHub surface.

See §10 for paste-ready card brief.

---

## 9. Follow-up implement card titles (do not implement here)

1. `implement: linear_issue_stages refusal extract + facade (slice 1)` — **first**
2. `implement: linear_issue_stages test checkpoint → stages_test.sh (slice 2)`
3. `implement: linear_issue_stages publish+complete → stages_publish.sh (slice 3)`
4. `implement: linear_issue_stages research/plan + in_progress → stages_research_plan.sh (slice 4)`
5. `implement: linear_issue_stages decision/implement → stages_implement.sh; facade source-only (slice 5)`
6. `docs: tip-sync after linear_issue_stages split complete` (if high-level tips lag)

Factory may spawn slice 1 as child of this design card after land.

---

## 10. Paste-ready first implement card brief with `/goal`

```
/goal Extract ensure_linear_refusal_checkpoint from bin/lib/linear_issue_stages.sh into bin/lib/linear_issue_stages_refusal.sh and make linear_issue_stages.sh a thin facade that sources the refusal module (while other stage bodies remain in the facade until later slices). Zero behavior change. Stable function name. linear_issue.sh still sources only linear_issue_stages.sh after linear_mutate.sh. GitHub untouched. GRKR_LINEAR_MUTATE default OFF unchanged.

Context: tip deb0acc (post #166 deploy) / product lineage cfdfb76 #164. linear_issue_stages.sh 727 LOC largest shell vertical after Linear thinning complete (f6b34d4 #133) + shared helpers. Design: docs/design-linear-issue-stages-split.md (this card parent). Pattern: exact body move like prior Linear extracts + Gleam facade hygiene (phases/progress/resolve_pr).

Read (must):
- AGENTS.md
- docs/design-linear-issue-stages-split.md (§4–§6, §10)
- docs/design-linear-issue-thinning.md (historical slices)
- bin/lib/linear_issue_stages.sh (ensure_linear_refusal_checkpoint ~392-507 + header)
- bin/lib/linear_issue.sh (source chain mutate→stages; process_linear_issue)
- bin/lib/linear_mutate.sh
- test/test-copy-grkr-lib.sh (must copy new sibling)
- test/grkr-linear-refuse-progress.sh (direct caller)
- test/grkr-linear-issue-implement.sh, grkr-linear-issue-mvp.sh, grkr-linear-apply-matrix.sh
- spec/parts/17,21-26,31,38,39 as needed

Implement (Grok Build --mode implement or full):
1. Add bin/lib/linear_issue_stages_refusal.sh with exact ensure_linear_refusal_checkpoint body + comment block.
2. At top of linear_issue_stages.sh (after header), source refusal sibling via BASH_SOURCE-relative path; remove in-file definition (no wrapper).
3. Update stages header: facade begins; document slice 1 of stages-split design; list remaining bodies still in file.
4. Fix test-copy-grkr-lib.sh (or equivalent) to copy linear_issue_stages*.sh.
5. Do not rename functions; do not touch github_issue.sh / issue_shared dump; no new flags.

Verify:
- bash -n bin/lib/linear_issue*.sh
- bash test/grkr-linear-refuse-progress.sh
- bash test/grkr-linear-issue-mvp.sh
- bash test/grkr-linear-issue-implement.sh
- bash test/grkr-linear-apply-matrix.sh
- gleam build && gleam test
- npm test (or at least grkr-smoke.sh + Linear suite)
- git diff --stat: empty or trivial on github_issue.sh / bin/grkr

Acceptance:
- All files ≤1000 LOC
- refuse-progress still sources only linear_issue.sh and resolves ensure_linear_refusal_checkpoint
- Identical dry-run artifacts/dumps/progress for refuse path
- README + docs/gleam-migration.md thin note (Next product thinning → stages split slice 1 landed)

Non-goals: no test/publish/decision extracts yet; no Gleam rewrite; no live mutate default change; no GitHub behavior change.
```

---

## 11. Risks and mitigations

| Risk | Mitigation |
|------|------------|
| test-copy omits child → refuse test mysterious “command not found” | Update copy helper in **same** PR as first multi-file split; add explicit fail if source path missing |
| Facade source order wrong | Prefer refusal+research_plan before implement; all sourced before dispatch; call-time resolution is backup |
| Accidental behavior edit during move | Exact body move only; no drive-by refactors; diff should be pure relocation |
| Header comment drift | Each slice updates facade header slice list; children carry local ambient docs |
| Parallel workers editing stages | Detached worktree from origin/main; small slices |

---

## 12. Done criteria for this design card

- [x] Goal / non-goals (no behavior change; GitHub default; mutate OFF; no dump into github_issue/issue_shared)
- [x] Current state LOC + tip + source chain
- [x] Full function inventory + callers
- [x] Target module map (facade + five concern modules)
- [x] Ordered slice table + acceptance
- [x] Regression surface
- [x] Paste-ready first implement brief with `/goal`
- [x] Citations (AGENTS, spec parts, prior designs)
- [ ] Product implementation — **out of scope** (child cards)

---

## 13. Next step

Kanban: land this design PR → spawn **implement: linear_issue_stages refusal extract + facade (slice 1)** with parent = design task, detached worktree from new `origin/main`, Grok Build `--mode implement`, verify Linear matrix + gleam + npm, then continue slices 2–5.
