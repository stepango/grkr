# Design: Linear Implement-Stage Wire for `--linear-issue`

**Status**: Design-only (plan agent). No product code edits.  
**Reference tip**: Live workspace tip **5f0a4cc** (docs post-land #96); product lineage tip **8aba009** (PR #95 Linear refuse dry-run after PR #93 MVP research/plan @ 28e4794).  
**Gap addressed**: Linear implement/test/PR stages deferred; GitHub implement path is complete and must remain regression-green.  
**Date**: 2026-07-13

---

## 1. Goal / non-goals

### Goal
Wire the implement stage for `grkr --linear-issue <identifier>` (after research + plan + worktree) so that:
- The existing provider-aware `decision_gate` (and `linear_flow` for refuse) is invoked from the Linear path.
- On `proceed`: run implement codex (in the `linear-$TASK_SLUG` worktree), persist `implementation.log`, update `progress.json` parity, plan "In Progress" Linear state mutation (dry-run by default).
- On `refuse`: reuse the already-landed `linear_flow` / `ensure_linear_refusal_checkpoint` path (no duplication).
- GitHub `--issue` path and all existing GitHub fixtures/tests remain 100% unchanged.

Preserve:
- `GRKR_ISSUE_PROVIDER=linear` (or `--linear-issue`) selects Linear; default remains GitHub.
- Dry-run by default for all Linear mutations (`GRKR_LINEAR_MUTATE=1` reserved for future live apply).
- Thin shell conventions in `bin/`.
- Every file ≤ 1000 LOC.
- Spec/parts/ as canonical source.

### Non-goals (explicitly out of first slice)
- Full test stage for Linear (checkpoint + verification commands).
- Publish / PR creation for Linear-originated work (no GitHub PR by default; document as next slice).
- Live Linear GraphQL mutations (commentCreate / issueUpdate) — always plan + dry-run dumps.
- Changes to supervisor spawn (already dispatches `--linear-issue`).
- Refactoring of refusal (already first-class and Linear-aware).

---

## 2. Current state (cite files + tip SHA)

**What works (as of 8aba009 / 5f0a4cc lineage)**:
- `--linear-issue ENG-123` → `process_linear_issue` (bin/grkr + bin/lib/linear_issue.sh):
  - `load_linear_issue_assignments` via `issue_provider/main fetch-issue` (supports `LINEAR_FIXTURE_PATH`).
  - Writes `meta.env`, `issue-context.json`, seeds `progress.json` (provider=linear, stages include `implement_or_refuse` + `test`, `decision=undecided`).
  - `ensure_linear_checkpoint_stage` for research + plan: writes `<stage>.md` (via shared `write_*_checkpoint_file` thin delegates → Gleam progress/templates), plans `linear-comment-mutation` (dry-run KEY=val + *.linear-mutation.txt).
  - Prepares `linear-$TASK_SLUG` branch worktree via `prepare_issue_worktree` (Gleam delegate).
  - Prints `MVP_STAGE=plan`; returns early.
- Decision gate is **already provider-aware**:
  - `src/grkr/workflow/decision_gate.gleam`: reads `GRKR_ISSUE_PROVIDER`, on refuse calls `refusal/linear_flow.run_refusal_linear` (or github flow); `issue_label` adapts messaging.
  - `run_decision_gate` thin delegate in `bin/grkr-issue-workflow.sh`.
  - Wired only inside GitHub `process_issue` (after plan + worktree + codex decision prompt).
- Refusal for Linear is **complete (dry-run)**:
  - `src/grkr/refusal/linear_flow.gleam`
  - `bin/lib/linear_issue.sh:ensure_linear_refusal_checkpoint`
  - `progress/main:plan_linear_refusal` + `cli plan-linear-refusal`
  - `test/grkr-linear-refuse-progress.sh` (direct helper test); progress.json refused parity via `mark_task_progress_refused`.
- Implement stage hook exists but GitHub-only:
  - `src/grkr/workflow/implement_stage.gleam:generate_commit_message` → hardcodes `feat(robot): implement #<issue> <title>`.
  - Thin delegate `generate_implement_commit_message` in `bin/grkr-issue-workflow.sh`.
  - Called only from GitHub `publish_issue_changes`.
- Progress parity helpers:
  - `bin/lib/task_progress.sh`: `ensure_task_progress_file`, `update_task_progress_stage`, `mark_task_progress_refused` / `complete`.
  - Linear seeds `implement_or_refuse: {status: "pending"}`.
- `linear_state.gleam`: `implementation: "In Progress"` (default mapping; overridable via `LINEAR_STATE_IMPLEMENTATION`).
- Templates / prompts: GitHub-centric wording in `progress/templates.gleam` (render_decision_prompt, render_issue_prompt say "GitHub issue", "Issue #").
- Tests: `test/grkr-linear-issue-mvp.sh` asserts MVP ends at plan (no gh issue view); refusal progress test; many GitHub regression fixtures.
- No `decision_gate` or implement codex ever runs for Linear today.
- `bin/grkr` at call site: `if [ "$MODE" = "--linear-issue" ]; then process_linear_issue ...; fi` (no continuation).

**What stops at MVP_STAGE=plan**:
- No decision prompt/codex.
- No `run_decision_gate` call.
- No "In Progress" state plan on proceed.
- No `implementation.log`.
- No implement-stage commit hook usage.
- No during-impl refusal conversion for Linear.
- `process_linear_issue` header comment and final echo explicitly say "implement/test/PR deferred".

GitHub path is full (research → plan → decision gate → (proceed) In Progress move → implement codex + log + size checks → test → publish PR + complete).

---

## 3. Modules / files to touch (smallest slice first)

All changes are additive wiring or narrow provider branches. No duplication of refuse logic.

1. **bin/lib/linear_issue.sh** (currently ~440 LOC → est. +110-140 LOC)
   - Why: Core Linear orchestration lives here (`process_linear_issue`, ensure_*_checkpoint helpers, refusal helper).
   - Add: `ensure_linear_implement_stage` (or inline), decision prompt + codex run, In Progress mutation planning, implement prompt reuse, implementation.log handling, during-impl refusal path using existing `ensure_linear_refusal_checkpoint`.
   - Keep ≤1000 (easy; this file is small).
   - Preserve: thin run_progress_cli + decode patterns.

2. **bin/grkr** (currently ~833 LOC post recent extracts → est. +20-40 LOC delta)
   - Why: `--linear-issue` dispatch + shared `run_codex_prompt`, `CURRENT_ISSUE_WORKTREE`, progress sourcing.
   - Changes: After `process_linear_issue` call (or refactor process_linear_issue to return control), continue into decision/implement for Linear when appropriate. Or (preferred thin): make `process_linear_issue` itself drive the post-plan flow (like process_issue does) using new helpers from linear_issue.sh. Update help text minimally.
   - Risk: file size — extract more to lib if >950. Use same pattern as GitHub (mktemp prompts, run_codex, detect refusal).
   - Non-goal: do not duplicate publish logic here for Linear.

3. **src/grkr/workflow/implement_stage.gleam** (~36 LOC → est. +25-40 LOC)
   - Why: Commit message must differ for Linear (`ENG-123` vs `#123`; no `#` per product default).
   - Add: Provider-aware `generate_commit_message` (or `generate_commit_message_for_provider`), CLI support for `commit-message --provider linear|github <id> <title>`, or simple branch on env inside existing fn + new exported `generate_linear_commit_message`.
   - Add unit test cases. Keep pure.
   - Update thin delegate in `bin/grkr-issue-workflow.sh` if signature changes (small).

4. **src/grkr/progress/templates.gleam** (and cli entry) (~176 LOC → est. +30-50 if needed)
   - Why: Decision prompt and implement prompt hardcode "GitHub issue" / "Issue #".
   - Smallest: Add `render_linear_decision_prompt` / `render_linear_issue_prompt` (or parameterize with provider + conditional wording). Or (cheapest for first slice): document reuse of GitHub wording for Linear implement (cosmetic only; functional contract is identical) and defer wording fix.
   - Preferred minimal: extend `cli_render_*` + templates with `render-linear-decision-prompt` etc. that substitute "Linear issue IDENTIFIER" and omit `#`. This keeps prompts correct for the agent.
   - CLI surface in `progress/cli.gleam` + update `grkr-templates.sh` thin delegates if new renderers added.
   - LOC guard: if this pushes file over, split renderers.

5. **bin/grkr-issue-workflow.sh** (~68 LOC → est. +5-15 LOC)
   - Why: Thin delegates for `run_decision_gate`, `generate_implement_commit_message`, `run_test_stage_hook`.
   - Add (if needed): `generate_linear_implement_commit_message` or extend delegate to pass provider. Or just reuse/adapt existing + env.
   - Keep very small.

6. **test/grkr-linear-issue-mvp.sh** or **new test/grkr-linear-issue-implement.sh** (new file)
   - Why: Extend MVP test or carve dedicated implement smoke that drives full decision + proceed path with mocked codex, asserts `implementation.log`, progress.json `implement_or_refuse=done`, `*.linear-mutation.txt` for state, no gh calls.
   - Mirror structure of existing MVP + linear-refuse tests (stub codex, git, gh that asserts "UNEXPECTED" on misuse).

7. **test/grkr/workflow/implement_stage_test.gleam** (small delta)
   - Add Linear commit message test cases (once Gleam hook supports it).

8. **docs/gleam-migration.md** + **README.md** (post-implement note, per AGENTS)
   - Note only (implement card will do functional update).

9. **spec/parts/** (no change for first slice; 39 already marks as deferred)

**LOC discipline**: All existing files comfortably under 1000. New logic goes into linear_issue.sh (plenty of headroom) or narrow Gleam extensions. If bin/grkr approaches limit, extract `linear_implement_flow.sh` or similar before landing.

---

## 4. Wire protocol

### How `process_linear_issue` (or its continuation) continues past plan
Preferred approach (thin, reuses patterns):
- Keep `process_linear_issue` responsible for full Linear issue workflow (research/plan/decision/implement).
- After existing plan checkpoint + `prepare_issue_worktree` + setting `CURRENT_ISSUE_WORKTREE`:
  1. Write decision prompt (reuse `write_decision_prompt_file` — or new linear variant).
  2. `run_codex_prompt ... "decide whether to implement..."`
  3. `decision=$(run_decision_gate "$IDENTIFIER" "$decision_output_file" "$PROGRESS_FILE" "$TASK_SLUG" ...)` (note: decision_gate already accepts identifier for linear; it normalizes inside).
  4. Normalize to lowercase.
  5. If refuse: cleanup worktree (already happens inside gate via linear_flow for side effects; just ensure CURRENT cleared + return).
  6. If proceed:
     - Plan Linear "In Progress" state mutation dry-run (new helper `ensure_linear_in_progress_checkpoint` or direct `run_progress_cli linear-state-mutation "$mutation_issue_id" "$state_id"` + dump to `implement.linear-state-mutation.txt` + update progress stage).
     - Write implement prompt (via `write_issue_prompt_file` or linear variant).
     - `run_codex_prompt ... "implement the issue" ...` → `$TASK_DIR/implementation.log`
     - `implementation_refusal=$(detect_implementation_refusal "$codex_output_file")`
     - If present: convert to refusal using `ensure_linear_refusal_checkpoint` (already Linear-aware) + mark refused + cleanup.
     - Else: persist log, update progress (implement_or_refuse done), optionally mark "implement" stage metadata.
     - (No publish in slice 1.)
  7. Return success (no "MVP_STAGE=plan" anymore; or keep a `STAGE=implement` echo for tests).

Decision gate call site reuses exact `run_decision_gate` thin wrapper (already provider-dispatches inside Gleam).

### Env vars & fixture paths
- `GRKR_ISSUE_PROVIDER=linear` (or implicit via `--linear-issue` dispatch).
- `LINEAR_FIXTURE_PATH` (already used by issue_provider for fetch-issue in tests).
- `GRKR_LINEAR_MUTATE` — ignored / reserved; all paths remain dry-run (plan + log files).
- `LINEAR_STATE_IMPLEMENTATION` (optional override for state name; default "In Progress" from linear_state).
- `mutation_issue_id`: prefer `ISSUE_ID` (Linear UUID) when present (from issue-context.json or fetch), fall back to `ISSUE_IDENTIFIER` (ENG-123 style). Same pattern already used in `ensure_linear_checkpoint_stage` and refusal.

### KEY=val / progress CLI patterns to reuse
- `run_progress_cli linear-state-mutation "$linear_issue_id" "$state_id"`
- `run_progress_cli linear-state ...` (for name resolution)
- Dump format parity with refusal: `*.linear-state-mutation.txt`, `*.linear-mutation.txt` for comments.
- Progress updates via existing `update_task_progress_stage "$PROGRESS_FILE" "implement_or_refuse" "done" "$key"` (or extend for "implement" sub-stage if desired).
- `mark_task_progress_refused` already works for Linear.

### Commit message for Linear
- Default: `feat(robot): implement ENG-123 <title>` (no leading `#`).
- Hook extension: make `implement_stage.gleam` provider-aware.
  - Option A (smallest): add `generate_commit_message(provider, id, title)` or keep old + new `generate_linear_commit_message(id, title)`.
  - CLI: `commit-message <id> <title>` (current) stays GitHub for compat; add `commit-message --provider linear <id> <title>` or detect via env inside.
  - In shell: `generate_implement_commit_message` (or new linear variant) called with `ISSUE_IDENTIFIER` for Linear.
  - Update delegate + call site in publish (GitHub keeps old) and new Linear implement path.
- Product decision accepted: no `#` for Linear identifiers.

### Worktree / branch
- Already correct: `BRANCH="linear-$TASK_SLUG"`; `prepare_issue_worktree` + `git_in_issue_context` (via CURRENT_ISSUE_WORKTREE) work unchanged.
- Task slug derivation already lowercases identifier (ENG-123 → eng-123).

### progress.json parity
- Existing seed already has `implement_or_refuse` and `test`.
- On proceed decision: `update_task_progress_stage ... "implement_or_refuse" "done" ...` (decision gate already does `dec_update_progress` for the decision value itself).
- After successful implement codex: ensure `decision=proceed`, `stages.implement_or_refuse.status=done`, optionally add `implement: {status: "done", log: "implementation.log"}`.
- On refusal conversion: `mark_task_progress_refused` (already used by linear refusal helper).
- `status` at top level can stay "planning" until test/complete (or set "implementing").
- Mirror GitHub `mark_task_progress_complete` only when a future publish/complete slice lands.

### Linear state mapping (In Progress on implement)
- Reuse `linear_state.implementation` (default "In Progress").
- After decision proceed (or before/after codex): run `run_progress_cli linear-state-mutation "$mutation_issue_id" "$STATE_ID"` (if `LINEAR_STATE_IMPLEMENTATION_ID` or similar provided) or just plan the name via `linear-state implementation`.
- For first slice: plan the state mutation using the same pattern as refusal (`plan-linear-refusal` has state handling). Add a `plan-linear-state-update` or use existing `linear-state-mutation` CLI + record in `implement.linear-state-mutation.txt`.
- No actual move happens unless `GRKR_LINEAR_MUTATE=1` (future).

### Dry-run vs live
- Default: always dry-run. Emit same style logs as research/plan/refuse:
  - "📝 Planning Linear implement In Progress mutation for $identifier..."
  - "🔑 ... idempotency_key=... (dry-run; set GRKR_LINEAR_MUTATE=1 when live apply lands)"
- Live apply (comment + state) is explicitly future work.

---

## 5. Stage sequencing for Linear (recommended smallest green slice order)

A. Wire decision gate after plan + worktree inside Linear path (critical missing link).
   - In `process_linear_issue` (or post-call continuation in bin/grkr), after existing plan + worktree code:
     - Build decision prompt (reuse write_decision_prompt_file or linear variant).
     - run_codex_prompt.
     - decision=$(run_decision_gate "$ISSUE_IDENTIFIER" ... )  ← already works for linear identifier.
   - This reuses all existing decision extraction + provider dispatch.

B. On proceed:
   - Plan In Progress state mutation dry-run (new ensure helper modeled exactly on ensure_linear_checkpoint_stage + ensure_linear_refusal_checkpoint).
   - Optionally update progress stage for "implement_or_refuse".
   - Write/run implement prompt → implementation.log (reuse write_issue_prompt_file + run_codex_prompt).
   - Run `detect_implementation_refusal`.
   - If refusal marker: convert via `ensure_linear_refusal_checkpoint` (already exists) + mark refused + cleanup.
   - Else: update progress parity, leave worktree (for future test/publish slices or manual), persist log.

C. On refuse (from decision gate):
   - Already handled inside `run_decision_gate` → `linear_flow` (writes refusal.md, plans comment + state, updates progress). Just do worktree cleanup + return (mirrors GitHub process_issue).

D. Defer (explicitly out):
   - Test checkpoint execution + test.md.
   - Any publish (git commit using Linear commit message hook, push, GitHub PR creation, or Linear comment with "implementation complete").
   - Completion comment.
   - Moving Linear item to "Done" / "In Review".

**Orchestration note**: Do **not** duplicate `process_issue` body. Keep Linear flow inside `process_linear_issue` (or a small `process_linear_issue_impl` helper in linear_issue.sh) calling the same thin delegates (`run_decision_gate`, `detect_*`, `run_codex_prompt`, `write_*_prompt_file`, `generate_implement_commit_message`). GitHub-specific calls (move_issue_to_in_progress, publish_issue_changes, ensure_test_checkpoint, gh edits) are skipped for provider=linear.

---

## 6. Fixtures / test plan

- **Primary**: Extend `test/grkr-linear-issue-mvp.sh` or introduce `test/grkr-linear-issue-implement.sh`.
  - Reuse the same stub pattern (fake `codex`, `git`, `gh` that fails on misuse, `LINEAR_FIXTURE_PATH`).
  - Drive `bash .../grkr.sh --linear-issue ENG-123`.
  - Assert:
    - No "MVP_STAGE=plan" (or new stage marker).
    - `research.md`, `plan.md`, `implementation.log` exist.
    - `progress.json`: `decision=proceed`, `stages.implement_or_refuse.status=done`, `provider=linear`.
    - `implement.linear-state-mutation.txt` (or `*.linear-*.txt`) contains planned issueUpdate or state name.
    - `*.linear-mutation.txt` for any implement comment if we choose to plan one.
    - `gh` log contains only auth/status or nothing (no issue view / pr create).
    - Worktree path `linear-eng-123` used for codex cd.
  - Separate subtest or flag for refuse path from decision (mock codex output containing "refuse\nunderspecified\n...").

- **Gleam unit tests**:
  - `implement_stage_test.gleam`: add cases for Linear commit message form (once hook supports provider/id-without-#).
  - Possibly `decision_gate` or progress tests if new pure helpers added (unlikely).

- **Mock codex strategy** (mirror GitHub tests):
  - Existing `test/grkr-implementation-to-refusal.sh` and refusal tests use temp bin/codex that writes specific output then exits 0.
  - Replicate for Linear: codex script that echoes a proceed decision or an implement transcript (or grkr-refuse-implementation block).

- **Regression**:
  - All existing `test/grkr-*.sh` that touch `--issue` or GitHub paths must pass unchanged.
  - `grkr-linear-issue-mvp.sh` (if kept as MVP) can assert early exit still works under a flag, or we evolve it into full implement test (preferred: evolve + keep "MVP" name for historical or rename).
  - `test/grkr-linear-refuse-progress.sh` untouched (already exercises refusal helper).

- **No live token**: All tests use fixtures + stubs. `GRKR_LINEAR_ACCESS_TOKEN` never required for green.

- **Run order**: `npm test` (shell) + `gleam test` (unit) + manual smoke of `grkr --linear-issue` with fixture.

---

## 7. Risks

- Duplicating process_issue into process_linear_issue → **Mitigation**: Do not copy body. Call shared thin delegates (`run_decision_gate`, `run_codex_prompt`, `detect_implementation_refusal`, `write_*_prompt_file`, `generate_implement_commit_message`). Put Linear-specific sequencing + mutation planning inside linear_issue.sh helpers. GitHub-only fns (publish, move via gh project, test checkpoint posting) remain uncalled for linear.
- Numeric parse in GitHub paths fed Linear IDs → **Mitigation**: decision_gate already guards `int.parse` inside the non-linear branch. In shell, never pass Linear identifier to GitHub-only fns (`move_issue_to_in_progress`, `gh issue ...`). Use `ISSUE_IDENTIFIER` vs numeric `ISSUE`.
- Commit message `#ENG-123` vs `ENG-123` → **Mitigation**: explicit product decision + provider-aware hook in implement_stage. Update only the Linear call site; GitHub test expectations stay `#123`.
- Publishing GitHub PR for Linear worktrees → **Mitigation**: explicit non-goal for slice. Skip `publish_issue_changes` entirely for Linear. Future slice can decide (GitHub PR + Fixes footer? Linear comment link?).
- File size of `linear_issue.sh` / `bin/grkr` → **Mitigation**: current headroom large. Extract helpers early (e.g., `ensure_linear_implement_checkpoint`, `run_linear_implement_codex`). Monitor with `wc -l`.
- Double progress updates (decision_gate + shell) → **Mitigation**: decision_gate does the `update_task_progress_decision` (sets decision + basic implement_or_refuse). Shell post-codex implement path only does additional stage status or In Progress state plan. Audit that we don't overwrite comment_id etc. For Linear, gate's progress update for decision is fine; we can pass a flag or simply let it be (it sets "proceed"/"refuse").
- Prompt wording mismatch ("GitHub issue" for Linear runs) → Low risk for correctness; cosmetic. Can be fixed in same PR or follow-up without behavior change.
- Worktree reuse / cleanup on Linear implement → Same cleanup logic as GitHub (already shared via `cleanup_issue_worktree`).

---

## 8. Product decisions (flag only if truly blocking)

**Decision recorded (non-blocking)**:
- On proceed after implement codex (first Linear implement slice): update progress + plan Linear "In Progress" mutation dry-run. **Do NOT** create a GitHub PR or perform publish steps. The worktree + `implementation.log` + progress + planned mutation are sufficient for the slice. (Justification: keeps slice minimal, defers "how do we surface Linear work publicly" product question; matches "implement/test/PR still deferred" language in spec/39 and docs. Publish can be a clean follow-up card.)
- Commit message default for Linear: `feat(robot): implement ENG-123 <title>` (no `#`). GitHub keeps `#N`. (Justification: Linear identifiers are not GitHub numbers; `#ENG-123` looks wrong in git log.)

Both are defaults that do not block the PR; documented for implementer.

---

## 9. Smallest implement-slice acceptance criteria (for child card t_3cb7b3c2)

Ship in **one PR**:

- `process_linear_issue` (or thin continuation after it) invokes `run_decision_gate` after research+plan+worktree for `--linear-issue`.
- On decision `proceed`:
  - Plans Linear "In Progress" state mutation (dry-run file + log).
  - Runs implement codex prompt in the linear- worktree.
  - Writes `implementation.log` under `.grkr/tasks/<slug>/`.
  - Updates `progress.json` (decision=proceed, implement_or_refuse done, provider parity).
- On decision `refuse` or during-impl refusal marker: reuses existing `linear_flow` / `ensure_linear_refusal_checkpoint` path; worktree cleaned; progress refused.
- GitHub `--issue` full path + all GitHub refusal / implement / test fixtures and tests remain green with zero behavior change.
- New or extended shell test (`grkr-linear-issue-implement.sh` or evolved mvp) passes with mocked codex; asserts no stray gh calls and correct artifacts.
- `gleam test` (implement_stage + any new) + `npm test` green.
- `gleam build` clean, 0 warnings on touched modules.
- README.md + docs/gleam-migration.md updated with "Linear implement dry-run landed" note (per AGENTS).
- No file exceeds 1000 LOC.
- No live Linear GraphQL by default (all mutations are planned/dumped; `GRKR_LINEAR_MUTATE` has no effect yet).
- Commit message for Linear uses identifier without `#`; GitHub unchanged.
- Decision gate + linear_flow untouched (already correct).

---

## 10. Out of scope for first implement PR

- Test stage execution / test.md / verification commands for Linear.
- Any publish logic (commit using Linear commit msg, push, PR creation, linking).
- Live `GRKR_LINEAR_MUTATE=1` apply path for implement state/comment.
- Supervisor changes (pick/scheduler already spawn `--linear-issue` correctly).
- Changes to `worker-refuse-issue.sh` (already thin + provider-aware via gate).
- Full Linear completion flow or Done state.
- Updating spec/parts beyond what sync would do (no spec content change required for wiring).
- Refactoring templates wording if we choose the minimal "reuse GitHub prompt text" path.

---

## Recommended implementation order (child worker)

1. Extend implement_stage.gleam + test for Linear commit message form (provider-aware or dedicated fn). Update grkr-issue-workflow.sh delegate if needed.
2. Add minimal Linear issue prompt / decision prompt renderers in progress/templates (or decide to reuse and note cosmetic).
3. In bin/lib/linear_issue.sh:
   - Add `ensure_linear_implement_in_progress` (or similar) that plans state mutation + writes dump + updates progress.
   - Refactor/extend `process_linear_issue` to run decision gate + on proceed run implement codex + log + during-refusal conversion using existing helpers.
4. Wire call site / continuation in bin/grkr (minimal).
5. Add/update shell test that exercises proceed path end-to-end (mocked).
6. Run full verification: gleam build/test, npm test, manual fixture run.
7. Update docs/README (thin notes).
8. (Optional hygiene) run `scripts/sync-spec.sh` (expect noop on content).

---

## Implement card brief (paste-ready for child worker)

```
/goal Wire Linear implement stage after research/plan for --linear-issue (reuse decision_gate + linear_flow + progress helpers). Dry-run only. GitHub default + regression untouched.

Context: tip 5f0a4cc / product 8aba009 (PR#95 refuse landed). Open gap = Linear implement. process_linear_issue stops at MVP_STAGE=plan and never calls decision_gate. decision_gate + linear_flow + linear_state already provider-aware.

Read (must):
- spec/parts/17-issue-workflow-overview.md, 22-stage-3-..., 25-stage-4-implement.md, 23-refusal-flow.md, 39-recommended-...
- AGENTS.md (≤1000 LOC, split if needed, update README after func change, spec/parts canonical, thin bin/ sh, GitHub default)
- bin/grkr (process_issue vs process_linear_issue call site)
- bin/lib/linear_issue.sh (full; ensure_* helpers, MVP end)
- bin/grkr-issue-workflow.sh (thin delegates)
- src/grkr/workflow/{decision_gate.gleam, implement_stage.gleam}
- src/grkr/refusal/linear_flow.gleam
- src/grkr/progress/{main.gleam, cli.gleam, linear_state.gleam, templates.gleam, linear_mutation.gleam}
- bin/lib/task_progress.sh + refusal_paths.sh (shared mark helpers)
- test/grkr-linear-issue-mvp.sh, test/grkr-linear-refuse-progress.sh, implement_stage_test.gleam
- docs/gleam-migration.md, README.md

Acceptance (one PR):
- process_linear_issue runs decision_gate post plan+worktree
- proceed → implement codex + implementation.log + progress parity + In Progress mutation plan (dry-run)
- refuse path reuses linear_flow / ensure_linear_refusal_checkpoint (no dupe)
- GitHub --issue path + tests 100% green
- Linear commit msg: "feat(robot): implement ENG-123 <title>" (no #)
- tests + README/gleam-migration note
- no file >1000 LOC; no live mutate default

Non-goals: test stage, PR publish, live GraphQL.

Use Grok Build CLI --mode implement (or full). After changes run gleam build + relevant tests. Follow AGENTS exactly.
```

---

**End of design document.**

Next: implement worker takes this + the listed files + AGENTS.md + relevant spec parts, writes self-contained prompt, runs the build CLI, verifies, etc.