# Design: Concern-split `bin/lib/github_issue.sh` (stages siblings + thin facade)

**Status**: Design-only (plan agent). No product shell/Gleam edits in this card.  
**Reference tip**: origin/main @ **e974fbd** (docs pin Grok CLI model #179). Product tip **cb6b1b5** / PR #177 (Linear stages-split complete; facade `linear_issue_stages.sh` source-only).  
**Prior design artifacts**: `docs/design-linear-issue-stages-split.md` (**mirror this structure**), `docs/design-github-issue-lib-thinning.md` (vertical inventory + optional checkpoint-json), `docs/design-github-process-issue-thinning.md` (how bodies landed in `github_issue.sh`, PRs #112–#121), Gleam thins PR body #147 + completion #152.  
**Gap addressed**: After process_issue thinning, shared helpers, Gleam PR-body/completion thins, and **Linear stages-split complete**, the largest remaining **GitHub shell vertical** is `bin/lib/github_issue.sh` (**542 LOC**, 17 functions). It is under the 1000 LOC hard limit but is the next high-value shell concern-split: thin facade + focused stage siblings, **zero behavior change**.  
**Date**: 2026-07-21  
**Kanban**: t_cfa6ec59  

---

## 1. Goal / non-goals

### Goal

Produce `docs/design-github-issue-stages-split.md` so implementers can ship ordered PRs that:

- Concern-split `bin/lib/github_issue.sh` into focused sibling modules (research/plan, test, publish, implement/bootstrap/finalize) plus a **thin facade** at the **stable path** `bin/lib/github_issue.sh` (already sourced by `bin/grkr`).
- Keep `process_issue` in `bin/grkr` as the thin sequencer (unchanged call sites and public names).
- Keep every file ≤1000 LOC; prefer siblings **≪400**.
- Preserve external contracts: `--issue` logs, artifacts, exit codes, progress.json, gh calls, PR bodies with Fixes, labels, worktree cleanup.
- Do **not** grow `issue_shared.sh` or any `linear_*` file as dumping grounds for GitHub stage bodies.

### Non-goals

- No behavior change to user-facing flags, `--issue` / `--linear-issue` contracts, or mutation defaults.
- `GRKR_ISSUE_PROVIDER` default remains **GitHub**; no picker/supervisor rewrite.
- Linear paths **untouched** (prefer empty Linear diff).
- `issue_shared.sh` **frozen** (no dump of GitHub stage bodies).
- Do not move `process_issue` out of `bin/grkr`.
- Do not rename public functions — ambient bash resolution and tests depend on stable names.
- Do not rewrite GitHub path as pure Gleam in this work (prior pure extracts already landed: PR body #147, completion #152).
- **No checkpoint-json pure Gleam extract** in this work (`design-github-issue-lib-thinning.md` §5 remaining optional/low-ROI stays separate if ever).
- No new public flags or provider switches.
- Design phase: docs only (+ optional Next pointer); no product shell body moves.

Preserve (per AGENTS + priors): thin shell conventions; ≤1000 LOC; `spec/parts/` canonical; shared neutral helpers stay shared; heavy gh/exec/worktree loops may stay shell.

---

## 2. Current state (cite files + tip)

### Re-measured LOC at tip e974fbd / product cb6b1b5

| File | LOC | Role |
|------|-----|------|
| `bin/lib/github_issue.sh` | **542** | Full GitHub vertical ← **this target** |
| `bin/lib/issue_shared.sh` | 387 | Neutral shared (frozen) |
| `bin/lib/linear_issue.sh` | 329 | Thin Linear sequencer + load/meta; sources mutate + stages facade |
| `bin/lib/linear_issue_stages.sh` | **88** | Linear stages **facade source-only** (pattern reference) |
| `linear_issue_stages_refusal.sh` | ~131 | Linear sibling |
| `linear_issue_stages_research_plan.sh` | ~125 | Linear sibling |
| `linear_issue_stages_implement.sh` | ~133 | Linear sibling |
| `linear_issue_stages_test.sh` | ~176 | Linear sibling |
| `linear_issue_stages_publish.sh` | ~175 | Linear sibling |
| `bin/grkr` | 198 | Thin launcher + GitHub `process_issue` sequencer |
| `bin/lib/task_progress.sh` | ~176 | Shared progress.json |
| `bin/lib/refusal_paths.sh` | ~125 | Shared refusal path helpers |

### Source chain (must preserve)

`bin/grkr` sources (order):

1. doctor, project-status, issue-workflow, refusal_paths, task_progress  
2. **`issue_shared.sh`** (before providers)  
3. **`linear_issue.sh`** → mutate + **stages facade** (Linear only)  
4. **`github_issue.sh`** ← stable GitHub entry (becomes facade)  
5. task-slug, templates  

Bash resolves functions at **call time**. `process_issue` only needs all GitHub stage fns defined before it runs (after full source of `github_issue.sh` facade + siblings).

### What prior work already did

| Work | Tip / PR | Effect |
|------|----------|--------|
| GitHub process_issue thinning | #112–#121 → **a3d9702** | Bodies → `github_issue.sh`; `process_issue` thin sequencer in `bin/grkr` |
| Shared helpers | #136–#144 | Bridges in `issue_shared.sh` |
| PR body Gleam thin | **1216e94** / #147 | `ensure_pr_body_limit` + `extract_codex_pr_body` thin delegates |
| Completion Gleam thin | **29c7a4b** / #152 | `post_completion_comment` thin Gleam render + gh post |
| Linear thinning | #125–#133 → **f6b34d4** | Stages into one `linear_issue_stages.sh` |
| Linear stages-split | #167–#177 → **cb6b1b5** | Facade + 5 siblings; **pattern to mirror** |

### GitHub path flow (unchanged contract)

`process_issue` sequence in `bin/grkr`:

1. `bootstrap_github_issue_task`  
2. `ensure_checkpoint_stage` research + plan  
3. `run_github_decision_stage` → if not proceed: `handle_github_decision_refuse` → return  
4. `run_github_implement_stage` (impl-refusal may set `GITHUB_IMPL_REFUSED` and return)  
5. `ensure_publishable_file_sizes` (**shared**, stays in `issue_shared.sh`)  
6. `ensure_test_checkpoint`  
7. `publish_issue_changes`  
8. `finalize_github_issue_complete`  

---

## 3. Inventory: every function in `github_issue.sh`

Re-verified via full file read (542 lines). Approx body LOC includes function-local comments.

| ~LOC | Function | ~lines | External callers | Ambient deps (call-time) | Gleam / shared overlap | Notes |
|-----:|----------|--------|------------------|--------------------------|------------------------|-------|
| 9 | `fetch_issue_comments_json` | 30–37 | internal (`ensure_*`) | `gh` | None | gh comments JSON for resume |
| 15 | `checkpoint_comment_id_from_json` | 39–52 | internal | `checkpoint_marker` (shared) | marker | jq last matching comment id |
| 15 | `checkpoint_comment_body_from_json` | 54–67 | internal | `checkpoint_marker` | marker | jq body restore |
| 54 | `ensure_checkpoint_stage` | 69–121 | `process_issue` (×2) | write_research/plan (templates), `update_task_progress_stage`, self helpers | templates + progress | research/plan reuse/restore/post |
| 28 | `write_test_checkpoint_file` | 123–149 | internal `ensure_test` | `write_test_checkpoint_with_header` (shared) | shared write | "Issue #N: title" header |
| 118 | `ensure_test_checkpoint` | 151–259 | `process_issue` | comment helpers, `run_test_stage_hook`, `build_command_list`, progress/mark, `CURRENT_ISSUE_WORKTREE` | test_stage + shared | Largest vertical; worktree exec + gh post |
| 57 | `publish_issue_changes` | 269–324 | `process_issue` | stage/git/limit/commit msg, `extract_codex_pr_body`, gh pr/issue | implement_stage + shared | Labels + Fixes via body path |
| 4 | `publish_github_issue_changes` | 326–328 | alias | → `publish_issue_changes` | — | Naming parity |
| 14 | `ensure_pr_body_limit` | 330–342 | internal extract | `ensure_github_pr_body` (templates) | **already thin Gleam** | #147 |
| 31 | `extract_codex_pr_body` | 344–367 | publish | task_log emit/shard, select/ensure Gleam | **already thin Gleam** | #147 |
| 14 | `post_completion_comment` | 375–387 | finalize | `render_github_completion_summary` | **already thin Gleam** | #152 |
| 10 | `post_github_completion_comment` | 389–391 | alias | → post | — | Naming parity |
| 35 | `bootstrap_github_issue_task` | 399–428 | `process_issue` | gh view, task_slug, project-status, task_progress writers | thin delegates | Sets TITLE/BODY/URL/BRANCH/… globals |
| 29 | `run_github_decision_stage` | 434–458 | `process_issue` | prepare_worktree, templates, `run_codex_prompt`, `run_decision_gate` | decision_gate | Sets `IMPLEMENTATION_DECISION` |
| 15 | `handle_github_decision_refuse` | 463–471 | `process_issue` | cleanup worktree, `attach_issue_logs` | shared attach | Cleanup only (gate did refuse side effects) |
| 53 | `run_github_implement_stage` | 478–527 | `process_issue` | move in-progress, templates, codex, refusal_paths, mark refused | refusal + project-status | Sets `GITHUB_IMPL_REFUSED` on conversion |
| 12 | `finalize_github_issue_complete` | 531–542 | `process_issue` | mark complete, move done, **`post_completion_comment`**, attach | progress + project-status | Calls publish-module completion |

**Cross-module ambient deps after split** (call-time; all siblings loaded by facade before dispatch):

- `ensure_test_checkpoint` → comment helpers in **research_plan** module  
- `finalize_github_issue_complete` → `post_completion_comment` in **publish** module  

**Not in this file (stay put):**

- `process_issue` → `bin/grkr`  
- `ensure_publishable_file_sizes`, `run_codex_prompt`, `attach_issue_logs`, … → `issue_shared.sh`  
- Decision/impl refusal conversion helpers → `refusal_paths.sh` + Gleam  
- No `ensure_*_refusal` GitHub stage fn (unlike Linear) — refusal conversion is inside `run_github_implement_stage` + shared paths  

---

## 4. Target module map + ownership boundaries

### Recommended shape: thin facade + **four** concern modules

| Path | Owns | Est. LOC after split |
|------|------|----------------------|
| `bin/lib/github_issue.sh` | **Facade only**: short header + ordered fail-closed `.` of children. **No function bodies** after final slice. **Stable path** already sourced by `bin/grkr`. | ~40–60 |
| `bin/lib/github_issue_stages_research_plan.sh` | `fetch_issue_comments_json` + `checkpoint_comment_*` + `ensure_checkpoint_stage` | ~100–120 |
| `bin/lib/github_issue_stages_test.sh` | `write_test_checkpoint_file` + `ensure_test_checkpoint` | ~155–175 |
| `bin/lib/github_issue_stages_publish.sh` | `publish_issue_changes` + alias + `ensure_pr_body_limit` + `extract_codex_pr_body` + `post_completion_comment` + alias | ~140–160 |
| `bin/lib/github_issue_stages_implement.sh` | `bootstrap_github_issue_task` + `run_github_decision_stage` + `handle_github_decision_refuse` + `run_github_implement_stage` + `finalize_github_issue_complete` | ~155–175 |

**Why four children (not five like Linear):**

- Linear needed a dedicated **refusal** sibling (`ensure_linear_refusal_checkpoint`) with a direct unit-style test.  
- GitHub has **no** equivalent stage body in this file; refusal lives in `refusal_paths.sh` + inside implement.  
- Four concerns match process_issue seams: research/plan → decision/implement/bootstrap/finalize → test → publish/complete.

**Why facade is `github_issue.sh` (not new `github_issue_stages.sh`):**

- `bin/grkr` already sources `lib/github_issue.sh` only.  
- Extra hop would force grkr + any direct sourcers to change without benefit.  
- Linear already had `linear_issue_stages.sh` as the intermediate; GitHub does not.

### Alternatives considered

| Alternative | Verdict |
|-------------|---------|
| Three modules: `{checkpoints, publish, implement}` (merge research+test) | Rejected: test is the largest vertical; weaker PR isolation; research helpers still couple to both |
| Five modules: extract comment helpers alone | Rejected: ~39 LOC helpers not worth a file; keep with research_plan; test uses ambiently |
| `bin/grkr` sources each sibling | Rejected: facade keeps one stable path (matches Linear + Gleam facades) |
| Dump stages into `issue_shared.sh` | **Forbidden** |

### Source order inside the facade

```text
# github_issue.sh (facade) — bin/grkr already sourced issue_shared + linear before this
. ".../github_issue_stages_research_plan.sh"  # helpers used by test at call-time
. ".../github_issue_stages_implement.sh"      # bootstrap/decision/implement/finalize
. ".../github_issue_stages_test.sh"           # uses comment helpers ambiently
. ".../github_issue_stages_publish.sh"        # completion used by finalize ambiently
```

- Prefer **dependency-before-depender for readability**: research_plan before test; publish before finalize is *not* required at parse time if both are sourced before `process_issue` runs.  
- **Call-time resolution**: any order works if **all** siblings are sourced before dispatch. Still fail-closed if a sibling is missing (mirror Linear facade):

```bash
CANDIDATE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/github_issue_stages_….sh"
if [ -f "$CANDIDATE" ]; then . "$CANDIDATE"
else echo "❌ missing GitHub stages … module: $CANDIDATE" >&2; return 1 2>/dev/null || exit 1
fi
```

### Ownership boundaries

| Surface | Rule |
|---------|------|
| `bin/grkr` | Thin `process_issue` + launcher; **do not** re-absorb stage bodies |
| `github_issue.sh` | Facade only after final slice |
| `github_issue_stages_*.sh` | GitHub-only stage bodies |
| `issue_shared.sh` | **Frozen** — no GitHub stage moves |
| `linear_*` | **Untouched** |
| `refusal_paths.sh` / `task_progress.sh` | Shared as today |

### Stable public API (do not rename)

All 17 names above stay byte-identical at call sites (`process_issue` args, exit codes, globals: `TITLE`, `ISSUE_JSON`, `IMPLEMENTATION_DECISION`, `GITHUB_IMPL_REFUSED`, `BRANCH_URL`, `PR_URL`, …).

### test-copy / fixture packaging

`test/test-copy-grkr-lib.sh` already:

```bash
cp "$repo_root/bin/lib/"*.sh "$dest/lib/"
```

New `github_issue_stages_*.sh` siblings are **auto-copied**. Still:

- Document packaging in design + first implement header/comment (like Linear).  
- Fail-closed facade if sibling missing (do not silently omit functions).  
- Optional: one-line comment in `test-copy-grkr-lib.sh` noting GitHub stages siblings (Linear already has a similar note).

---

## 5. Ordered shippable slice table (smallest first)

Each product slice acceptance:

- Files ≤1000 LOC; siblings prefer ≪400  
- `bash -n` on every touched `.sh`  
- `gleam build` + `gleam test` green  
- GitHub regression suite green (see §6)  
- Linear non-regression: prefer **empty** Linear diff; if any shared/copy touch, run Linear matrix  
- Zero intentional behavior change; no new flags  
- README + `docs/gleam-migration.md` thin Next note on functional slices  
- Empty/trivial diff on `linear_*` / `issue_shared.sh` / `process_issue` body  

| # | Title | Primary files | What moves | Acceptance highlight | Est. LOC delta |
|---|-------|---------------|------------|----------------------|----------------|
| **0** | Design only (this doc) | `docs/design-github-issue-stages-split.md` + optional Next pointer | none | Design complete; no product | +doc only |
| **1** | **First implement**: research_plan extract + introduce facade sourcing | facade begins + new `github_issue_stages_research_plan.sh` | Exact move: comment helpers + `ensure_checkpoint_stage`; facade sources sibling; other bodies remain in facade | checkpoint-resume + smoke; `ensure_checkpoint_stage` still resolves from grkr | facade −~93 body + source block; research_plan ~100–120 |
| **2** | test checkpoint → `github_issue_stages_test.sh` | facade + new test module | Exact move write_test + ensure_test | checkpoint-resume test path + smoke; worktree exec parity | −~146 from facade remainder |
| **3** | publish + completion → `github_issue_stages_publish.sh` | facade + new publish module | Exact move publish cluster + PR body + completion aliases | smoke + pr-body-limit + line-limit publish path | −~130–150 |
| **4** | implement cluster → `github_issue_stages_implement.sh`; facade source-only | facade + new implement module | bootstrap + decision + refuse + implement + finalize; **no bodies left in facade** | full happy + refuse + impl-to-refusal | facade ~40–60; implement ~155–175 |
| **5** (optional) | Header/docs “stages split complete” | docs | No logic | Tip pins accurate | docs only |

### Why research_plan first (not test or publish)

1. **Smallest complete vertical** (~93 LOC) that still proves multi-file facade + fail-closed source.  
2. Dedicated coverage via **`grkr-checkpoint-resume.sh`** (research/plan reuse/restore) without worktree test exec or `gh pr create`.  
3. Establishes pattern before larger test (~146) and publish (~130+) moves.  
4. Helpers become available ambiently for later test extract (same call-time model as today).  
5. Linear chose refusal first for a *dedicated direct test*; GitHub has no such refusal file — research_plan is the analogous “smallest high-signal seam.”

**Acceptable swap**: test first if implementer wants larger isolation immediately — same end state; must still introduce facade + fail-closed source in whichever lands first. Prefer research_plan unless blocked.

### LOC risk rules

- Block any slice leaving a single `github_issue*` file >~900 without further split.  
- Do **not** add GitHub stage code to `issue_shared.sh` or `linear_*`.  
- Do **not** fatten `process_issue` in `bin/grkr`.  
- Checkpoint-json pure extract remains **out of scope** (optional/low-ROI, separate card if ever).  
- Siblings target ≪400.

### Safe move pattern (every product slice) — mirror Linear

1. New sibling with **exact** function body + local comments (no refactors).  
2. Facade sources sibling; **remove** definition from old home (**no** thin wrapper left).  
3. Update headers (slice N, ambient deps, remaining bodies list).  
4. `bash -n` + GitHub regression + gleam + npm.  
5. README + gleam-migration thin note.

---

## 6. Regression surface

### GitHub (must stay green every product slice)

- `test/grkr-smoke.sh`  
- `test/grkr-checkpoint-resume.sh`  
- `test/grkr-refusal.sh`  
- `test/grkr-implementation-to-refusal.sh`  
- `test/grkr-line-limit.sh`  
- `test/grkr-pr-body-limit.sh`  
- `test/grkr-progress-cli.sh`  
- `test/grkr-dirty-worktree-warning.sh`, `grkr-branch-exists.sh`, `grkr-init.sh`, `grkr-installed-layout.sh`  
- Prefer full `npm test` (includes coding-agent-swap + worker/robot suite)

### Build

- `gleam build` + `gleam test`  
- `bash -n` on all touched shells  

### Linear (non-regression)

- Prefer **empty** Linear diff.  
- If copy helper / shared boundary touched: `grkr-linear-issue-implement.sh`, `grkr-linear-issue-mvp.sh`, `grkr-linear-refuse-progress.sh`, `grkr-linear-apply-matrix.sh`

Behavioral invariants: identical logs, gh calls, artifacts, PR bodies, progress.json, exit codes, worktree cleanup.

---

## 7. Spec + AGENTS citations

| Ref | Why |
|-----|-----|
| `AGENTS.md` | ≤1000 LOC; thin `bin/`; README on functional change; `spec/parts/` canonical; shell conventions |
| `spec/parts/17-issue-workflow-overview.md` | E2E issue workflow |
| `spec/parts/19–26` | Stage contracts (research through implement/test as applicable) |
| `spec/parts/22` | Decision gate |
| `spec/parts/23` / `24` | Refuse + impl-refusal |
| `spec/parts/25` | Implement |
| `spec/parts/26` / `31` | Test checkpoint |
| `spec/parts/27–31` | Related checkpoint/progress surfaces as needed |
| `spec/parts/39` | Order / status notes |
| `spec/parts/38` | Acceptance (if useful) |
| Prior designs in header | Pattern + non-goals continuity |

No spec content change required for pure shell LOC split.

---

## 8. Recommended first implement slice + rationale

**First product slice**: Extract research/plan cluster  
(`fetch_issue_comments_json`, `checkpoint_comment_id_from_json`, `checkpoint_comment_body_from_json`, `ensure_checkpoint_stage`)  
into `bin/lib/github_issue_stages_research_plan.sh` and convert `github_issue.sh` into a **facade that sources the research_plan module** while temporarily retaining other function bodies in the facade file.

**Rationale**: smallest high-signal vertical; proves facade + fail-closed multi-file packaging; strong checkpoint-resume coverage; lowest blast radius vs test exec / PR create; sets ambient helpers for later test extract.

See §10 for paste-ready card brief.

---

## 9. Follow-up implement card titles (do not implement here)

1. `implement: github_issue stages research_plan extract + facade (slice 1)` — **first**  
2. `implement: github_issue stages test checkpoint → stages_test.sh (slice 2)`  
3. `implement: github_issue stages publish+completion → stages_publish.sh (slice 3)`  
4. `implement: github_issue stages implement/bootstrap/finalize → stages_implement.sh; facade source-only (slice 4)`  
5. `docs: tip-sync after github_issue stages-split complete` (if high-level tips lag)  
6. *(separate, optional, non-goal here)* checkpoint-json pure extract if ever justified  

Factory may spawn slice 1 as child of this design card after land.

---

## 10. Paste-ready first implement card brief with `/goal`

```
/goal Extract GitHub research/plan cluster (fetch_issue_comments_json + checkpoint_comment_id_from_json + checkpoint_comment_body_from_json + ensure_checkpoint_stage) from bin/lib/github_issue.sh into bin/lib/github_issue_stages_research_plan.sh and make github_issue.sh a thin facade that sources the research_plan module (while other stage bodies remain in the facade until later slices). Zero behavior change. Stable function names. bin/grkr still sources only github_issue.sh. process_issue stays thin sequencer in bin/grkr. Linear + issue_shared untouched. No new flags. No checkpoint-json Gleam extract.

Context: tip e974fbd (docs #179) / product tip cb6b1b5 #177 Linear stages-split complete. github_issue.sh 542 LOC largest remaining GitHub shell vertical after process_issue thin (#112–#121), Gleam PR body #147 + completion #152. Design: docs/design-github-issue-stages-split.md (this card parent). Pattern: exact body move like Linear stages-split (docs/design-linear-issue-stages-split.md + facade fail-closed source).

Read (must):
- AGENTS.md
- docs/design-github-issue-stages-split.md (§4–§6, §10)
- docs/design-linear-issue-stages-split.md (facade pattern reference)
- docs/design-github-issue-lib-thinning.md (non-goals: checkpoint-json optional)
- bin/lib/github_issue.sh (helpers + ensure_checkpoint_stage ~L30–121 + header)
- bin/grkr (source order + process_issue call sites)
- bin/lib/issue_shared.sh (freeze — do not dump)
- bin/lib/linear_issue_stages.sh (fail-closed source pattern)
- test/test-copy-grkr-lib.sh (already cp bin/lib/*.sh — siblings auto-copied; optional comment)
- test/grkr-checkpoint-resume.sh, grkr-smoke.sh (+ full GitHub suite)
- spec/parts/17,19–26,27–31,39 as needed

Implement (Grok Build --mode implement or full):
1. Add bin/lib/github_issue_stages_research_plan.sh with exact bodies + comment blocks for the four functions.
2. At top of github_issue.sh (after header), source research_plan sibling via BASH_SOURCE-relative path with fail-closed missing message (mirror linear_issue_stages.sh); remove in-file definitions (no wrappers).
3. Update github_issue.sh header: facade begins; document stages-split slice 1; list remaining bodies still in file.
4. Do not rename functions; do not touch linear_* / issue_shared dump; no new flags; process_issue untouched.
5. Optional: one-line test-copy comment noting github_issue_stages_*.sh (glob already covers).

Verify:
- bash -n bin/lib/github_issue*.sh
- bash test/grkr-checkpoint-resume.sh
- bash test/grkr-smoke.sh
- bash test/grkr-refusal.sh
- bash test/grkr-implementation-to-refusal.sh
- bash test/grkr-line-limit.sh
- bash test/grkr-pr-body-limit.sh
- gleam build && gleam test
- npm test (or full GitHub suite above + progress-cli + dirty/branch/init/installed)
- git diff --stat: empty or trivial on linear_* / issue_shared.sh / bin/grkr process_issue body

Acceptance:
- All files ≤1000 LOC; research_plan sibling ≪400
- process_issue still calls ensure_checkpoint_stage by name; resolves via facade
- Identical resume/restore/post behavior for research/plan
- README + docs/gleam-migration.md thin note (Next product thinning → github stages-split slice 1 landed)

Non-goals: no test/publish/implement extracts yet; no Gleam rewrite; no checkpoint-json pure extract; no Linear behavior change.
```

---

## 11. Risks and mitigations

| Risk | Mitigation |
|------|------------|
| Missing sibling → mysterious “command not found” | Fail-closed facade source (Linear pattern); test-copy already globs `*.sh` |
| Cross-module ambient deps (test→helpers, finalize→completion) | All siblings sourced before `process_issue`; document in facade header; prefer research_plan before test in source order |
| Accidental behavior edit during move | Exact body move only; no drive-by refactors; diff = pure relocation |
| Header comment drift | Each slice updates facade header slice list; children carry local ambient docs |
| Parallel workers editing monolith | Detached worktree from origin/main; small slices |
| Temptation to “also” extract checkpoint-json to Gleam | Explicit non-goal; separate card if ever |

---

## 12. Done criteria for this design card

- [x] Goal / non-goals (zero behavior; GitHub default; Linear untouched; issue_shared frozen; process_issue thin; no rename; no checkpoint-json extract; no new flags)  
- [x] Current state LOC + tip + source chain + prior work  
- [x] Full function inventory + callers + ambient/Gleam notes  
- [x] Target module map (facade + four concern modules) + alternatives  
- [x] Source-order constraints + call-time / finalize→completion note  
- [x] Ordered slice table + acceptance + LOC rules + safe move pattern  
- [x] Regression surface  
- [x] Spec + AGENTS citations  
- [x] Recommended first implement + rationale  
- [x] Follow-up card titles  
- [x] Paste-ready first implement brief with `/goal`  
- [x] Risks/mitigations  
- [ ] Product implementation — **out of scope** (child cards)  
- [x] Optional: one-line Next pointer in README and/or `docs/gleam-migration.md` (docs-only, this PR)

---

## 13. Next step

Kanban: land this design PR → spawn **implement: github_issue stages research_plan extract + facade (slice 1)** with parent = design task, detached worktree from new `origin/main`, Grok Build `--mode implement`, verify GitHub suite + gleam + npm, then continue slices 2–4.

---

## Context summary

| Item | Value |
|------|--------|
| Target | `bin/lib/github_issue.sh` **542 LOC**, 17 fns |
| Pattern | Linear stages-split complete @ **cb6b1b5** / #177 |
| Facade path | **`github_issue.sh` itself** (grkr already sources it) |
| Siblings | 4 (`research_plan`, `test`, `publish`, `implement`) — no refusal sibling |
| First implement | research_plan cluster + facade source |
| Non-goal | checkpoint-json Gleam extract; Linear/issue_shared/process_issue body changes |
