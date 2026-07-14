# Design: Linear Test-Stage Wire for `--linear-issue`

**Status**: Design-only (plan agent). No product code edits.  
**Reference tip**: Live workspace tip after PR #97 land **d1c1240** (feat: Linear --linear-issue implement stage decision + dry-run).  
**Prior design artifact**: `docs/design-linear-implement-stage.md` (implement slice landed; test/publish were non-goals).  
**Gap addressed**: After implement success for `--linear-issue`, `stages.test` remains `pending`; GitHub test stage (`ensure_test_checkpoint`) is complete and must remain regression-green. Next slice wires spec/26 test stage parity for Linear (dry-run mutations).  
**Date**: 2026-07-13

---

## 1. Goal / non-goals

### Goal
Wire the test stage for `grkr --linear-issue <identifier>` (after successful implement) so that:
- On implement success (worktree + `implementation.log` present, `decision=proceed`, `implement_or_refuse=done`): execute configured verification commands (BUILD_COMMAND/TEST_COMMAND or `npm test`) inside `CURRENT_ISSUE_WORKTREE`.
- Write `.grkr/tasks/<slug>/test.md` with spec/26 contents (commands, pass/fail summary, output excerpts, risks, recommendation) using **Linear-aware header wording** ("Linear issue ENG-123: title", not "Issue #ENG-123").
- Plan Linear test checkpoint comment mutation (dry-run via `linear-comment-mutation`, same pattern as research/plan) and dump to `test.linear-mutation.txt`.
- Plan Linear state mutation to `test_state` (default "In Review" from `linear_state.gleam`, overridable via `LINEAR_STATE_TEST`) and dump to `test.linear-state-mutation.txt` (when state id available).
- Update `progress.json`: `stages.test` → `done` (success) or `failed` (failure), preserve `provider=linear`.
- Echo `STAGE=test`; leave worktree for subsequent publish slice; **do not** call `mark_task_progress_complete`, do not move to Done, do not create PRs.
- GitHub `--issue` path and all existing GitHub fixtures/tests remain 100% unchanged (zero behavior change to `ensure_test_checkpoint`, `write_test_checkpoint_file`, `gh` calls).

Preserve:
- `GRKR_ISSUE_PROVIDER=linear` (or `--linear-issue`) selects Linear; default remains GitHub.
- Dry-run by default for all Linear mutations (`GRKR_LINEAR_MUTATE=1` reserved for future live apply; has no effect in this slice).
- Thin shell conventions in `bin/`.
- Every file ≤ 1000 LOC (extract helpers early if needed).
- `spec/parts/` as canonical source.
- Prefer shared thin delegates (`build_command_list`, `run_test_stage_hook`, `cleanup_test_result_logs`, `checkpoint_marker`) over duplicating `process_issue` body into `process_linear_issue`.

### Non-goals (explicitly out of this slice)
- Publish/PR creation or linking for Linear-originated work (no `publish_issue_changes`, no `gh pr create`, no GitHub PR body).
- Calling `mark_task_progress_complete` or setting top-level `status=complete`.
- Live Linear GraphQL mutations (commentCreate / issueUpdate) — always plan + dry-run dumps.
- Changes to supervisor spawn, decision_gate, or refusal paths.
- Changes to GitHub `ensure_test_checkpoint` behavior, `write_test_checkpoint_file` signature for GitHub callers, or GitHub comment posting.
- Altering test failure semantics (failure marks `stages.test=failed` + `mark_task_progress_failed`; does **not** auto-convert to refusal — matches GitHub; refusal is a distinct decision-gate or during-impl path).

---

## 2. Current state (cite files + tip SHA)

**What works for Linear at d1c1240 (post PR #97 implement dry-run land)**:
- `--linear-issue ENG-123` → `process_linear_issue` (bin/grkr dispatch + `bin/lib/linear_issue.sh`):
  - Loads via `issue_provider/main fetch-issue` (fixture via `LINEAR_FIXTURE_PATH` or live).
  - Seeds `meta.env`, `issue-context.json`, `progress.json` (provider=linear, `implement_or_refuse` + `test` pending, `decision=undecided`).
  - `ensure_linear_checkpoint_stage` for research + plan: writes `<stage>.md`, plans `linear-comment-mutation` (dry-run), writes `*.linear-mutation.txt`, updates progress.
  - Prepares `linear-$TASK_SLUG` branch worktree via `prepare_issue_worktree`.
  - Sets `GRKR_ISSUE_PROVIDER=linear`.
  - Runs decision prompt + `run_decision_gate` (provider-aware; on refuse delegates to `linear_flow` via gate).
  - On proceed: `ensure_linear_implement_in_progress` (plans state mutation dry-run to "In Progress", writes `implement.linear-state-mutation.txt`, updates `implement_or_refuse=done`), writes/runs implement prompt → `implementation.log`, detects during-impl refusal (reuses `ensure_linear_refusal_checkpoint`), on success leaves worktree + log.
  - Prints `STAGE=implement`; `TASK_DIR` + `WORKTREE` emitted.
- `stages.test.status` remains `"pending"` after successful implement.
- `linear_state.gleam`: `test_state` defaults to `"In Review"`; `state_for_stage(Test, mapping)` works; env `LINEAR_STATE_TEST` supported.
- `test_stage.gleam`: pure thin hooks only (`run-tests` message + `completion-marker`); header comment notes "GitHub-only v2" but functions are provider-agnostic.
- `implement_stage.gleam`: already provider-aware (`commit-message --provider linear`); not used in test path.
- `bin/grkr`: shared helpers exist and are reusable:
  - `build_command_list()` — respects BUILD_COMMAND/TEST_COMMAND, falls back to `npm test`.
  - `cleanup_test_result_logs()`.
  - `run_test_stage_hook()` (thin delegate to `gleam run -m grkr/workflow/test_stage run-tests`).
  - `checkpoint_marker`, `run_progress_cli`.
- `write_test_checkpoint_file` (in bin/grkr) hardcodes `Issue #%s: %s` and is called only from GitHub `ensure_test_checkpoint`.
- GitHub path: `process_issue` calls `ensure_test_checkpoint` (after implement + size checks) which runs commands in `CURRENT_ISSUE_WORKTREE`, writes `test.md` (with `Issue #N` header + marker), posts via `gh issue comment`, updates progress `test done|failed`, on fail calls `mark_task_progress_failed`.
- No test.md, no test-stage Linear comment/state planning, no publish for Linear.
- Tests: `test/grkr-linear-issue-implement.sh` asserts `stages.test.status == "pending"`, `STAGE=implement`, `implementation.log`, no `gh pr create`.
- `grkr-linear-issue-mvp.sh` is historical (evolved to cover implement).
- README + gleam-migration note "test stage + publish still deferred".

**What stops after implement for Linear**:
- `ensure_test_checkpoint` / `write_test_checkpoint_file` never called for Linear.
- No `test.md` written for Linear paths.
- No `linear-comment-mutation` planned for test stage.
- No `linear-state-mutation` planned for test_state.
- No `stages.test` update beyond the initial seed.
- Worktree left open; no continuation past `STAGE=implement`.

GitHub path is full through test + publish + complete.

---

## 3. Modules / files to touch (smallest slice first)

All changes additive or narrow provider branches. No duplication of GitHub test logic.

1. **bin/lib/linear_issue.sh** (currently ~574 LOC → est. +80-130 LOC)
   - Why: Linear orchestration (`process_linear_issue` ends at implement success).
   - Add: `ensure_linear_test_checkpoint` (or inline continuation) that:
     - Calls shared `run_test_stage_hook`.
     - Reuses `build_command_list` + execution pattern (in `CURRENT_ISSUE_WORKTREE`).
     - Writes `test.md` via a **Linear-aware writer** (or thin adapter).
     - Plans `linear-comment-mutation` using test checkpoint body (dry-run, writes `test.linear-mutation.txt`).
     - Plans `linear-state-mutation` (or name-only record) using `linear-state test` / `LINEAR_STATE_TEST`, writes `test.linear-state-mutation.txt`.
     - Calls `update_task_progress_stage "$PROGRESS_FILE" test "done" "${key:-}"` or `mark_task_progress_failed` on failure.
     - On failure: calls `mark_task_progress_failed "$PROGRESS_FILE" test`; echoes failure; keeps or cleans worktree consistently with GitHub behavior.
   - On success: `CURRENT_ISSUE_WORKTREE` left set, echo `STAGE=test`, `TASK_DIR`, `WORKTREE`.
   - Keep ≤1000 (comfortable headroom).
   - Prefer extracting a small shared helper if `write_test_checkpoint_file` needs a provider-aware variant (see below).

2. **bin/grkr** (currently ~843 LOC → est. +10-40 LOC delta, or 0 if helpers extracted)
   - Why: hosts `write_test_checkpoint_file`, `ensure_test_checkpoint`, `build_command_list`, `cleanup_test_result_logs`.
   - Options (design recommends the least invasive):
     - **Preferred (thin reuse)**: Extract `write_test_checkpoint_body` (or `format_test_checkpoint`) that takes a header string + the rest of args; GitHub keeps calling with `Issue #N` header; Linear calls a new `write_linear_test_checkpoint_file` (or same fn with header arg) that emits "Linear issue ID: title".
     - Or: add `write_test_checkpoint_file_for_provider` + keep old `write_test_checkpoint_file` as thin wrapper for GitHub compat.
     - Do **not** touch GitHub call sites or `gh` paths inside `ensure_test_checkpoint`.
   - Add (if needed) a thin `ensure_linear_test_checkpoint` wrapper or just let linear_issue.sh source and call the write helper directly.
   - File size guard: if approaching 950+, extract more test helpers to `bin/lib/task_test.sh` (new, thin) before landing.
   - `build_command_list` and `cleanup_test_result_logs` are already reusable; no change or tiny export notes.

3. **src/grkr/workflow/test_stage.gleam** (~66 LOC → est. +0-10 LOC)
   - Why: Currently documents "GitHub-only v2" in header/usage.
   - Smallest: update doc comments to note "thin hooks; used by both providers; heavy execution + write + mutation planning stay in shell".
   - No behavior change; hooks remain pure.
   - Optional: add a small pure helper if future needs arise (out of scope).

4. **bin/grkr-issue-workflow.sh** (~68 LOC → est. +0-5 LOC)
   - Why: thin delegate host.
   - No change required if `run_test_stage_hook` + `test_completion_marker` remain sufficient.
   - If a new delegate is added for Linear test wording, keep tiny.

5. **test/grkr-linear-issue-implement.sh** (update) or **new test/grkr-linear-issue-test.sh**
   - Design decision (see §6): **Evolve the implement test into an end-to-end test that reaches STAGE=test** (simplest for regression + coverage). Rename or keep file name; update assertions to expect `test.md`, `stages.test.status == "done"`, `test.linear-mutation.txt` (or state), `STAGE=test`, implementation.log still present, no gh issue/pr mutations.
   - Add a failure subcase (set TEST_COMMAND=false) that asserts `stages.test.status == "failed"`, `mark_task_progress_failed` effect, non-zero exit, worktree handling.
   - Keep existing refuse subcase.
   - Alternative (more isolated): introduce dedicated `-test.sh`; implement test stays asserting implement intermediate reachable. Prefer end-to-end continuation for this slice (clearer contract that Linear now flows research→plan→implement→test).

6. **test/grkr/workflow/test_stage_test.gleam** (small or none)
   - Existing marker + hook tests remain valid (no change to pure surface).

7. **docs/gleam-migration.md + README.md** (post-implement notes)
   - Implement card will add "Linear test stage dry-run landed" note (per AGENTS). Design does not edit these yet.

8. **spec/parts/** (no content change required for wiring; 39 already marks test as forward-looking for Linear).

**LOC discipline**: All touched files have headroom. Extract only if a helper clearly benefits reuse and keeps files <1000. New `bin/lib/` file only if `bin/grkr` would exceed; otherwise keep changes in `linear_issue.sh` + narrow edits to `bin/grkr` write helper.

---

## 4. Wire protocol

### Continuation after implement success in `process_linear_issue`
After the existing implement success block (which sets `CURRENT_ISSUE_WORKTREE`, prints STAGE=implement, returns 0):

```sh
# Success path continuation (inside process_linear_issue or a small post_implement helper)
if [ "$decision" = "proceed" ]; then
  # ... existing implement success handling ...
  # Then:
  ensure_linear_test_checkpoint \
    "$ISSUE_IDENTIFIER" "$mutation_issue_id" "$TASK_SLUG" "$TASK_DIR" \
    "$ISSUE_TITLE" "$PROGRESS_FILE" || {
      CURRENT_ISSUE_WORKTREE=""
      return 1
  }
  echo "STAGE=test"
  echo "TASK_DIR=$TASK_DIR"
  echo "WORKTREE=$ISSUE_WORKTREE_DIR"
  return 0
fi
```

On test failure inside the helper: set `CURRENT_ISSUE_WORKTREE=""` (or leave for debug), return 1 (non-zero), consistent with GitHub `ensure_test_checkpoint` returning 1 on fail.

### Reuse points (shared, provider-agnostic)
- `run_test_stage_hook` — already wired; call early for parity (even if currently a no-op beyond logging).
- `build_command_list` — outputs commands (BUILD/TEST or npm test).
- `CURRENT_ISSUE_WORKTREE` — cd context for command execution (already set by implement path).
- `checkpoint_marker test "$task_slug"` — via `run_progress_cli` or direct.
- `run_progress_cli linear-comment-mutation "$mutation_issue_id" "$body" test "$TASK_SLUG"`
- `run_progress_cli linear-state test` (to resolve name) + `linear-state-mutation "$mutation_issue_id" "$state_id"`
- `update_task_progress_stage "$PROGRESS_FILE" test "done" "$key"`
- `mark_task_progress_failed "$PROGRESS_FILE" test`

### Linear-specific test checkpoint (ensure_linear_test_checkpoint sketch)
1. Reuse/resume: if `test.md` exists locally + (future) we can detect prior planned mutation, reuse and update progress `done`.
2. Call `run_test_stage_hook`.
3. Build command list to temp file.
4. For each command: run inside `CURRENT_ISSUE_WORKTREE` (or fallback), capture log, record PASS/FAIL.
5. Determine overall `PASS`/`FAIL`, recommendation, counts.
6. Write `test.md`:
   - Marker via `checkpoint_marker test "$task_slug"`.
   - Header: `Linear issue $identifier: $title` (no leading `#` on identifier).
   - Sections mirror GitHub exactly: Commands run, Pass/fail summary, Output excerpts (first 20 lines + ...), Remaining risks, Recommendation.
   - Use `write_test_checkpoint_file` if we parameterize header, or a small dedicated writer in linear_issue.sh / extracted helper.
7. Plan Linear comment mutation:
   ```
   body=$(cat "$checkpoint_file")
   mutation_out=$(run_progress_cli linear-comment-mutation "$mutation_issue_id" "$body" test "$TASK_SLUG" ...)
   printf '%s\n' "$mutation_out" > "$task_dir/test.linear-mutation.txt"
   idempotency_key=...
   echo "🔑 test mutation ... (dry-run; set GRKR_LINEAR_MUTATE=1 ...)"
   ```
8. Plan state mutation (to "In Review"):
   - `target_state=$(run_progress_cli linear-state test 2>/dev/null || echo "In Review")`
   - If `LINEAR_STATE_TEST_ID` or suitable id available: `run_progress_cli linear-state-mutation ...`
   - Else: write name-only record `TARGET_STATE=In Review\nSTATE_MUTATION_PLANNED=0`
   - Dump to `test.linear-state-mutation.txt`.
9. On success: `update_task_progress_stage ... test "done" "${idempotency_key:-}"`
10. On any failure: `update_task_progress_stage ... test "failed" ...`; `mark_task_progress_failed "$PROGRESS_FILE" test`; cleanup temp logs; return 1.

### Env vars
- Same as GitHub: `BUILD_COMMAND`, `TEST_COMMAND`.
- Linear: `LINEAR_STATE_TEST` (name override), `LINEAR_STATE_TEST_ID` (optional UUID for mutation).
- `GRKR_LINEAR_MUTATE` — ignored; all paths dry-run.
- `GRKR_ISSUE_PROVIDER=linear` already set.

### Worktree handling
- Success: leave `CURRENT_ISSUE_WORKTREE` set (publish slice will use it).
- Failure: mirror GitHub — `CURRENT_ISSUE_WORKTREE=""` after marking failed; worktree dir left on disk for debug (GitHub path does not auto-clean on test fail in the current ensure path; keep consistent).
- Refuse paths are already handled before reaching test (no test run on refuse).

### Dry-run output style (parity)
- Research/plan: "📝 Planned Linear $stage checkpoint mutation..."
- Implement: "📝 Planning Linear implement In Progress mutation..."
- Test: "📝 Planning Linear test checkpoint mutation for $identifier..." + state target + idempotency notes + "(dry-run...)".

### No gh calls
- `ensure_linear_test_checkpoint` (and any Linear continuation) must never invoke `gh issue comment`, `gh pr create`, etc. Guard in tests via stub that fails on misuse.

---

## 5. progress.json parity

After successful test for Linear:
```json
{
  "provider": "linear",
  "issue_identifier": "ENG-123",
  ...
  "decision": "proceed",
  "stages": {
    "research": {"status": "done"},
    "plan": {"status": "done"},
    "implement_or_refuse": {"status": "done"},
    "test": {"status": "done", "comment_id": "<idempotency-key-or-string>"}
  },
  "status": "planning",   // remains "planning" (complete happens in publish slice)
  ...
}
```

On test failure:
- `stages.test.status = "failed"`
- top-level `status = "failed"` (via `mark_task_progress_failed`)
- `decision` stays "proceed" (failure after decision is not a refusal)

Refusal paths already set `test: "skipped"` via `mark_task_progress_refused`.

Do **not** set `status=complete` or call `mark_task_progress_complete` in this slice. That is publish/complete work (matches spec/26 GitHub behavior where complete follows test+publish; Linear splits the slice).

---

## 6. Fixtures / test plan

**Primary test**: Evolve `test/grkr-linear-issue-implement.sh` (or introduce `test/grkr-linear-issue-test.sh` and update implement test minimally) to drive the full happy path to test completion.
- Reuse stub pattern (fake `codex`, `git`, `gh` that asserts "UNEXPECTED" on gh issue/pr misuse, `LINEAR_FIXTURE_PATH`).
- Drive `bash .../grkr.sh --linear-issue ENG-123`.
- Assert:
  - `research.md`, `plan.md`, `implementation.log`, `test.md` all exist.
  - `progress.json`: `provider=linear`, `decision=proceed`, `implement_or_refuse=done`, `test.status=done`.
  - `test.linear-mutation.txt` (or `*.linear-*.txt`) contains planned commentCreate or body with marker.
  - `test.linear-state-mutation.txt` contains `In Review` or `TARGET_STATE=` or mutation dump.
  - `STAGE=test` (not `implement` as final) in output.
  - `gh` log shows no `issue view` misuse and no `pr create`.
  - Worktree path used for command execution.
  - `implementation.log` still present.
- Failure subcase: override `TEST_COMMAND=false` (or patch codex? no — patch the command list effect); assert `stages.test.status=failed`, `mark_task_progress_failed` visible in progress, non-zero exit from grkr, logs cleaned, message about failure.
- Decision-refuse subcase remains (no test.md expected on refuse path).

**Clear approach chosen**:
- Evolve the current implement test into the end-to-end Linear flow test (reaches `STAGE=test` on proceed). This gives the strongest regression signal that the full research→plan→implement→test path is wired for Linear. Keep a comment noting "implement is an intermediate stage; test is the continuation for success". If a future card needs an "implement-only" stop, a flag or separate entry can be added then.

**Regression**:
- All GitHub `--issue` tests (`grkr-*.sh` that use numeric issues) must pass unchanged.
- `gleam test` + `npm test` green.
- No live token required (`LINEAR_FIXTURE_PATH` + stubs).

**Gleam**:
- Existing `test_stage_test.gleam` and `implement_stage_test.gleam` (Linear commit msg) unchanged or trivial doc updates.
- If a pure test-checkpoint renderer is added later (not required), add unit coverage.

**Run**:
- `npm test` (shell harnesses)
- `gleam test`
- Manual: `LINEAR_FIXTURE_PATH=... bash -x bin/grkr --linear-issue ENG-123` (with TEST_COMMAND=true)

---

## 7. Risks + mitigations

- Duplicating `ensure_test_checkpoint` logic → **Mitigation**: do not duplicate. Extract `write_test_checkpoint_body` / header param (or `format_test_results`) in bin/grkr; GitHub path unchanged; Linear path calls the shared write with different header wording and skips gh entirely. Put Linear sequencing + mutation planning inside `linear_issue.sh`.
- `write_test_checkpoint_file` hardcodes `Issue #%s` → **Mitigation**: refactor to accept or compute header line; old call sites keep GitHub form; Linear uses "Linear issue %s: %s". Add unit-level or shell parity test that the body sections are identical.
- Accidentally calling `gh` from Linear test path → **Mitigation**: strict test stubs that exit non-zero on gh issue/pr; code review; no `gh` in linear_issue.sh test helper.
- File size (`linear_issue.sh` ~574 + `bin/grkr` ~843) → **Mitigation**: current headroom; extract only a tiny shared test-write helper if needed. Monitor with `wc -l`; split before 950.
- Double stage updates or clobbering `comment_id` → **Mitigation**: Linear test path uses idempotency key string (same as implement/refuse); audit that we only write once per stage in the happy path. Decision gate + implement already set prior stages.
- Test failure should refuse vs fail? → **Mitigation**: match GitHub exactly — `stages.test=failed`, top-level failed, non-zero, no auto-refusal. Refusal is a separate, earlier decision.
- Worktree left after test fail → **Mitigation**: consistent with GitHub (CURRENT cleared, dir retained for inspection); document in test.
- Marker / idempotency key reuse on resume for Linear → **Mitigation**: local `test.md` presence + progress `done` is the resume signal for this slice (no remote comment lookup for Linear yet, same as research/plan).
- Prompt wording or templates using "GitHub issue" in test context → Not applicable; test.md is data-driven from commands, not from decision/issue prompts.

---

## 8. Product decisions (non-blocking defaults)

- Linear test state name: **"In Review"** (from `linear_state.test_state` default; overridable by `LINEAR_STATE_TEST`).
- No `mark_task_progress_complete` in this slice (publish slice will do complete + Done).
- `test.md` header: **"Linear issue ENG-123: title"** (no `#` prefix on identifier, matching commit message convention and Linear identifier style).
- On test fail: `progress` marked failed/test failed; exit non-zero; no publish; worktree retained on disk (CURRENT cleared) for debug — same disposition as GitHub.
- `GRKR_LINEAR_MUTATE` still has no effect; all mutations planned only.
- Test commands use the same env/contract as GitHub (BUILD_COMMAND/TEST_COMMAND in worktree).

These are recorded for the implement worker; none are blocking.

---

## 9. Smallest implement-slice acceptance criteria (for child implement card)

Ship in **one PR**:

- After successful implement for `--linear-issue`, the flow continues and calls test execution + writes `test.md`.
- `test.md` exists with correct marker, Linear header wording, commands/summary/excerpts/risks/recommendation.
- Linear test checkpoint mutation planned (dry-run dump `test.linear-mutation.txt`).
- Linear test state mutation planned (name or full, `test.linear-state-mutation.txt`, target "In Review" or override).
- `progress.json`: `stages.test.status = "done"` (success path) or `"failed"` (fail path); `provider=linear` preserved; no `status=complete`.
- `STAGE=test` emitted on success; non-zero + failed marker on command failure.
- GitHub `--issue` full path (including test checkpoint + gh comment + complete flow) + all GitHub tests remain 100% green with zero behavior change.
- New/extended shell test exercises proceed → test path end-to-end (mocked); asserts artifacts + no stray gh calls; failure subcase green.
- `gleam test` + `npm test` green; `gleam build` clean, 0 warnings on touched modules.
- README.md + docs/gleam-migration.md updated with "Linear test stage dry-run landed" note (per AGENTS).
- No file exceeds 1000 LOC.
- No live Linear GraphQL (all mutations planned/dumped).
- Worktree handling and exit codes consistent with GitHub test stage.

---

## 10. Out of scope for this implement PR

- Publish logic (git commit with Linear message, push, PR creation, Linear "complete" comment).
- Calling `mark_task_progress_complete` or moving Linear item to Done.
- Live `GRKR_LINEAR_MUTATE=1` apply path for test comment/state.
- Supervisor / pick / scheduler changes.
- Changes to GitHub test checkpoint code paths or comment posting.
- Full Linear completion flow.
- Updating spec/parts content (wiring only; sync-spec may be run for index).
- Adding a pure Gleam test.md renderer (shell write is acceptable and matches current GitHub pattern).

---

## 11. Recommended implementation order for implement worker

1. Decide on write helper extraction in bin/grkr (parameterize header or add narrow Linear variant) — keep diff small.
2. In `bin/lib/linear_issue.sh`:
   - Add `ensure_linear_test_checkpoint` (or continuation after implement success).
   - Reuse `build_command_list`, `run_test_stage_hook`, `CURRENT_ISSUE_WORKTREE`, `checkpoint_marker`, `run_progress_cli`, `update_task_progress_stage`, `mark_task_progress_failed`.
   - Write test.md with Linear header.
   - Plan comment + state mutations (dry-run dumps + logs).
   - Success: update progress done, echo STAGE=test, leave worktree.
   - Failure: mark failed, non-zero, clear CURRENT.
3. Wire the continuation inside `process_linear_issue` (or small post-impl step) in linear_issue.sh; minimal change in bin/grkr dispatch.
4. Update/evolve the shell test (`grkr-linear-issue-implement.sh` → reaches test) + add failure subcase.
5. Run verification: `gleam build`, `gleam test`, `npm test`, manual fixture run with success + fail cases.
6. Update docs/README notes (thin, per AGENTS).
7. (Optional hygiene) run `scripts/sync-spec.sh`.

---

## 12. Paste-ready implement card brief with /goal

```
/goal Wire Linear test stage after successful implement for --linear-issue (spec/26 parity). Execute BUILD/TEST commands in worktree, write test.md (Linear header wording), plan dry-run Linear comment + "In Review" state mutations, update stages.test done|failed. Leave worktree; no publish, no mark complete. GitHub default + regression untouched.

Context: tip d1c1240 (post #97 implement dry-run). process_linear_issue ends at STAGE=implement with test still pending. GitHub ensure_test_checkpoint + write_test_checkpoint_file complete. linear_state already has test_state + LINEAR_STATE_TEST. test_stage.gleam is thin pure hooks. build_command_list + run_test_stage_hook reusable.

Read (must):
- AGENTS.md (≤1000 LOC, thin bin/, update README after func change, spec/parts canonical, GitHub default, shared delegates)
- spec/parts/17-issue-workflow-overview.md, 26-stage-5-test.md, 31-test-checkpoint.md, 18-task-folder..., 39-recommended...
- docs/design-linear-implement-stage.md (pattern) + this design doc
- bin/grkr (ensure_test_checkpoint, write_test_checkpoint_file, build_command_list, cleanup..., checkpoint_marker, run_test_stage_hook, process_issue flow)
- bin/lib/linear_issue.sh (full; ensure_linear_* helpers, process_linear_issue end state, ensure_linear_implement_in_progress)
- bin/lib/task_progress.sh (update + mark_failed)
- bin/grkr-issue-workflow.sh (thin delegates)
- src/grkr/workflow/test_stage.gleam + test_stage_test.gleam
- src/grkr/progress/{linear_state.gleam, cli.gleam, main.gleam, checkpoint_stage.gleam}
- test/grkr-linear-issue-implement.sh (evolve to test), grkr-linear-issue-mvp.sh, grkr-refusal.sh (test skipped parity)
- README.md Linear section + docs/gleam-migration.md

Acceptance (one PR):
- Linear success path after implement: runs commands, writes test.md (Linear wording, marker, sections), plans test.linear-*.txt (comment + state), stages.test=done, STAGE=test, worktree left.
- Failure path: stages.test=failed, mark_task_progress_failed, non-zero exit, no publish.
- GitHub --issue test path + all gh tests 100% unchanged.
- No live mutate; dry-run only.
- Tests + docs notes; gleam build/test + npm test green; no file >1000 LOC.

Non-goals: publish/PR/complete, live GraphQL, GitHub changes.

Use Grok Build CLI --mode implement (or full). After changes run gleam build + relevant tests. Follow AGENTS exactly.
```

---

**End of design document.**

Next: implement worker takes this + listed files + AGENTS.md + relevant spec parts, writes self-contained prompt, runs the build CLI, verifies `gleam build` / tests, and completes the card.
