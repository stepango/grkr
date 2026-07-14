# Design: Linear Publish + Complete for `--linear-issue`

**Status**: Design-only (plan agent). No product code edits.  
**Reference tip**: Live workspace tip after PR #98 land **bfee58c** (Linear test-stage dry-run).  
**Prior design artifacts**: `docs/design-linear-test-stage.md` (explicitly deferred publish/complete as non-goals; next-slice notes) and `docs/design-linear-implement-stage.md`.  
**Gap addressed**: After successful test for `--linear-issue`, flow ends at `STAGE=test` with `status=planning` (worktree left open, no commit, no PR, no `mark_task_progress_complete`, no Done state). GitHub `process_issue` tail (publish → complete → Done → completion comment) is complete and must remain regression-green. This slice wires dry-run publish + complete parity for Linear.  
**Date**: 2026-07-14

---

## 1. Goal / non-goals

### Goal
Wire publish + complete for `grkr --linear-issue <identifier>` after successful test so that:

- On test success (`stages.test=done`, `decision=proceed`, worktree + `test.md` + `implementation.log` present): perform publish (stage relevant files, commit using Linear commit message, push the `linear-$TASK_SLUG` branch, create or update GitHub PR) and plan Linear completion (comment + Done state) under dry-run.
- Reuse/adapt shared git staging + line-limit enforcement + PR body extraction; use `generate_linear_implement_commit_message` (already provider-aware).
- Call `mark_task_progress_complete` (provider-agnostic) with `branch_url` + `pr_url`.
- Plan Linear state mutation targeting `done` (default "Done" from `linear_state.done` / `LINEAR_STATE_DONE`; `PrSummary` stage mapping) and dump to `complete.linear-state-mutation.txt` (or `publish.linear-state-mutation.txt`).
- Plan Linear completion comment (body modeled on `post_completion_comment` but Linear wording + PR link) via `linear-comment-mutation` (using `pr_summary` stage or sensible equivalent) and dump to `complete.linear-mutation.txt`.
- Clear `CURRENT_ISSUE_WORKTREE`; echo `STAGE=complete`; return success.
- GitHub `--issue` path (including `publish_issue_changes`, label edits, `move_issue_to_done`, `post_completion_comment`) and all GitHub tests remain 100% unchanged.

Preserve:
- `GRKR_ISSUE_PROVIDER=linear` (or `--linear-issue`) selects Linear; default remains GitHub.
- Dry-run by default for all Linear mutations (`GRKR_LINEAR_MUTATE=1` reserved for future live apply).
- Thin shell conventions in `bin/`.
- Every file ≤ 1000 LOC (extract helpers early).
- `spec/parts/` as canonical source.
- Prefer shared delegates (`stage_relevant_issue_files`, `git_in_issue_context`, `ensure_publishable_file_sizes`, `extract_codex_pr_body`, `checkpoint_marker`, `run_progress_cli`, `mark_task_progress_complete`) over duplication.

### Non-goals (explicitly out of this slice)
- Live Linear GraphQL mutations (commentCreate / issueUpdate) — always plan + dry-run dumps.
- Changes to supervisor spawn, decision_gate, refusal paths, or GitHub publish/complete code.
- Altering GitHub PR footer ("Fixes #N") or label behavior.
- Adding a separate "publish" stage key to `progress.json` (GitHub does not; reuse the complete marker).
- Auto-cleaning the worktree directory on disk (match GitHub: only clear `CURRENT_ISSUE_WORKTREE`).
- Supervisor / picker / scheduler changes.

---

## 2. Current state (cite files + tip SHA)

**What works for Linear at bfee58c (post PR #98 test dry-run land)**:
- `--linear-issue ENG-123` → `process_linear_issue` (bin/grkr + `bin/lib/linear_issue.sh`):
  - Full research → plan → decision → implement (with `ensure_linear_implement_in_progress` state plan) → test (`ensure_linear_test_checkpoint`).
  - After successful test: writes `test.md` (Linear header via `write_test_checkpoint_with_header`), plans `test.linear-mutation.txt` + `test.linear-state-mutation.txt` ("In Review"), updates `stages.test=done`, leaves `CURRENT_ISSUE_WORKTREE` set, echoes `STAGE=test` + TASK_DIR + WORKTREE, returns 0.
  - `progress.json`: `provider=linear`, `decision=proceed`, `stages.*` done up to test, top-level `status="planning"`.
  - Worktree on `linear-$TASK_SLUG` branch; no commit/push/PR yet.
- Shared publish machinery (bin/grkr):
  - `publish_issue_changes` (~lines 635-690): stages, early-returns 0 on no diff, line-limit guard, `generate_implement_commit_message`, git commit+push, `gh pr list` + create/edit, GitHub-only label edits.
  - `extract_codex_pr_body` + `ensure_pr_body_limit` + footer ("Fixes #N") + `append_issue_footer`.
  - `ensure_publishable_file_sizes` (staged relevant + remediation loop).
  - `post_completion_comment`, `mark_task_progress_complete` (in task_progress.sh; sets `status=complete`, forces implement/test done, records branch/pr urls).
- Linear Gleam support (already landed):
  - `implement_stage.gleam`: `commit-message --provider linear` → `feat(robot): implement ENG-123 title` (no #).
  - `grkr-issue-workflow.sh`: `generate_linear_implement_commit_message` delegate.
  - `linear_state.gleam`: `done: "Done"`, `state_for_stage(PrSummary) → done`, `is_terminal_state`.
  - `checkpoint_stage.gleam`: `PrSummary` terminal stage (maps to Done).
  - `linear_mutation.gleam`: `create_comment_mutation`, `create_comment_with_pr_link`, `update_state_mutation`.
  - `progress/cli.gleam` + `main.gleam`: `linear-state`, `linear-comment-mutation`, `linear-state-mutation`, `render-pr-summary`.
- GitHub full tail: after test → `ensure_publishable_file_sizes` → `publish_issue_changes` → clear CURRENT → `mark_task_progress_complete` → `move_issue_to_done` → `post_completion_comment`.
- Tests: `test/grkr-linear-issue-implement.sh` reaches `STAGE=test`, asserts `test.md` + mutations + `stages.test=done`, **explicitly asserts no `gh pr create`**, worktree left open. gh stub fails on "issue view" and implicitly on pr create.
- README + gleam-migration + spec/39: "**publish + complete** still deferred".

**What stops after STAGE=test for Linear**:
- No `ensure_publishable_file_sizes`, no commit/push, no `gh pr create`.
- No `mark_task_progress_complete`.
- No Linear Done state plan or completion comment.
- `progress.json` remains `status=planning`.
- No PR_URL / branch_url recorded for Linear success path.
- GitHub path is full through publish + complete + Done.

---

## 3. Modules / files to touch (smallest slice first)

All changes additive or narrow provider branches. GitHub paths untouched.

1. **bin/lib/linear_issue.sh** (currently ~737 LOC → est. +90-160 LOC; stay under 1000)
   - Why: owns `process_linear_issue` continuation after `ensure_linear_test_checkpoint`.
   - Add: `ensure_linear_publish_complete` (or `publish_linear_issue_changes` + completion planning).
     - Call `ensure_publishable_file_sizes` (reuse; it is context-driven via CURRENT).
     - Call (or inline) publish logic: stage, commit with linear msg, push, gh pr create/edit.
     - Skip GitHub label edits.
     - Adapt PR body extraction (no Fixes footer; "Linear: $IDENTIFIER" or link).
     - `mark_task_progress_complete "$PROGRESS_FILE" "$BRANCH_URL" "$PR_URL"`.
     - Plan Linear Done state via `linear-state pr_summary` + `linear-state-mutation` (dump `complete.linear-state-mutation.txt`).
     - Plan completion comment via `linear-comment-mutation` (stage `pr_summary` or equivalent; dump `complete.linear-mutation.txt`); prefer `create_comment_with_pr_link` pattern when PR exists.
     - On success: clear CURRENT, echo `STAGE=complete`, TASK_DIR, WORKTREE.
     - On no-changes (mirror GitHub): return 0 early from publish step, still proceed to mark + Linear completion planning.
     - On publish failure: clear CURRENT, return 1 (no complete side effects).
   - Keep ≤1000 (comfortable headroom).

2. **bin/grkr** (currently ~843 LOC → est. +10-50 LOC or 0)
   - Why: hosts `publish_issue_changes`, `extract_codex_pr_body`, `ensure_publishable_file_sizes`, `ensure_pr_body_limit`, `post_completion_comment`.
   - Preferred (thin): extract or parameterize a small helper for PR body footer so Linear can call a variant or post-process that omits "Fixes #N" and adds Linear link. Or add `extract_linear_codex_pr_body` thin wrapper.
   - Do **not** touch GitHub call sites inside `process_issue` or `publish_issue_changes`.
   - If approaching 950 LOC, extract a tiny `publish_helpers.sh` before landing (AGENTS discipline).
   - `stage_relevant_issue_files`, `git_in_issue_context`, `check_file_line_limit` are already reusable.

3. **bin/grkr-issue-workflow.sh** (thin; ~80 LOC)
   - Already exports `generate_linear_implement_commit_message`. No change expected, or tiny doc note.

4. **test/grkr-linear-issue-implement.sh** (evolve) or new publish test
   - Evolve (or carve continuation) to drive full path to `STAGE=complete`.
   - Update gh stub to **allow** `pr list`, `pr create`, `pr edit` (and related) **only for Linear publish path**; keep failing on misuse or GitHub issue label edits.
   - Assert: commit recorded in log, PR created/updated for `linear-eng-123` branch, `pr_url` + `branch_url` in progress.json, `status=complete`, Done state dump, completion comment dump, `STAGE=complete`.
   - Subcases: no-changes (returns 0 from publish, still completes), publish failure (non-zero, no mark complete), file size remediation before publish.
   - Retain refuse + test-fail subcases.

5. **src/grkr/progress/** (minimal or none)
   - `linear_state`, `checkpoint_stage`, `linear_mutation`, `main`, `cli` already support PrSummary → Done and `create_comment_with_pr_link`. Small doc or test additions only if a pure helper is extracted (not required for slice).

6. **docs/gleam-migration.md + README.md** (post-implement notes, per AGENTS)
   - Implement card will add "Linear publish + complete dry-run landed" note.

7. **spec/parts/** (no content change required for wiring).

**LOC discipline**: Headroom exists. Extract only when a helper clearly benefits reuse and prevents >1000 LOC. New `bin/lib/` file only if `bin/grkr` would exceed.

---

## 4. Wire protocol

### Continuation after test success in `process_linear_issue`
After the existing test success block (which sets CURRENT, prints STAGE=test markers):

```sh
# Success path continuation (inside process_linear_issue or small post_test helper)
ensure_linear_publish_complete \
  "$ISSUE_IDENTIFIER" "$mutation_issue_id" "$TASK_SLUG" "$TASK_DIR" \
  "$ISSUE_TITLE" "$ISSUE_URL" "$BODY" "$codex_output_file" "$BRANCH" \
  "$PROGRESS_FILE" || {
    CURRENT_ISSUE_WORKTREE=""
    return 1
}
CURRENT_ISSUE_WORKTREE=""
echo "STAGE=complete"
echo "TASK_DIR=$TASK_DIR"
echo "WORKTREE=$ISSUE_WORKTREE_DIR"
return 0
```

On publish failure inside the helper: clear CURRENT, return 1 (no complete).

### Order inside ensure_linear_publish_complete (or equivalent)
1. `ensure_publishable_file_sizes "$IDENTIFIER" "$TITLE" "$TASK_SLUG" "$prompt" "$codex_out"` (reuses remediation loop; operates in CURRENT_ISSUE_WORKTREE).
2. Publish:
   - `stage_relevant_issue_files`
   - if `git_in_issue_context diff --cached --quiet` → "No changes for $IDENTIFIER", return 0 (parity; still proceed to mark + Linear complete below).
   - `check_file_line_limit` (fail → abort).
   - `commit_msg=$(generate_linear_implement_commit_message "$IDENTIFIER" "$TITLE")`
   - `git_in_issue_context commit -m "$commit_msg"`
   - `git_in_issue_context push -u origin "$BRANCH"`
   - `BRANCH_URL="https://github.com/$REPO/tree/$BRANCH"`
   - Prepare PR body (via `extract_codex_pr_body` or Linear variant that skips Fixes footer and appends "Linear: $IDENTIFIER" / `$ISSUE_URL`).
   - `gh pr list --head "$BRANCH" ...`; create or edit.
   - **Do not** run `gh issue edit` for labels.
   - Capture `PR_URL`.
3. `CURRENT_ISSUE_WORKTREE=""`
4. `mark_task_progress_complete "$PROGRESS_FILE" "$BRANCH_URL" "$PR_URL"`
5. Plan Linear completion:
   - Resolve target: `target_state=$(run_progress_cli linear-state pr_summary 2>/dev/null || echo "Done")`
   - If `LINEAR_STATE_DONE_ID` (or equiv): `linear-state-mutation "$mutation_issue_id" "$id"` → dump to `complete.linear-state-mutation.txt`.
   - Else name-only record.
   - Completion comment body (Linear wording):
     ```
     ## Completion summary

     Linear issue $IDENTIFIER: $TITLE

     - Recommendation: ready
     - Branch: $BRANCH_URL
     - PR: $PR_URL
     ```
     Optionally append via `create_comment_with_pr_link` pattern.
   - `run_progress_cli linear-comment-mutation "$mutation_issue_id" "$body" pr_summary "$TASK_SLUG"` → dump `complete.linear-mutation.txt`.
6. Echo / return.

### Env vars
- Same as before: `BUILD_COMMAND`, `TEST_COMMAND`, `LINEAR_STATE_DONE`, `LINEAR_STATE_DONE_ID`.
- `GRKR_LINEAR_MUTATE` — still no effect.
- `GRKR_ISSUE_PROVIDER=linear`.

### Worktree / branch handling
- Success: clear `CURRENT_ISSUE_WORKTREE` (dir left on disk for cleanup policy — matches GitHub).
- No-changes or publish success: still mark complete + plan Linear Done.
- Publish failure: do not call mark complete; do not plan Done.

### Dry-run output style (parity)
- "🔄 Auto-committing, pushing and creating PR..." (or Linear variant log).
- "📝 Planning Linear complete / Done state mutation..."
- "🔑 ... idempotency_key=... (dry-run; set GRKR_LINEAR_MUTATE=1 when live apply lands)"
- "✅ Linear publish + complete planned for $IDENTIFIER".

### gh call discipline in tests
- GitHub path continues to use full gh surface.
- Linear publish path uses: `gh pr list`, `gh pr create`, `gh pr edit` (and auth/status).
- Linear path must never call `gh issue edit --add-label` / `--remove-label` or `gh issue comment` for GitHub issues.
- Stub will be updated to enforce this split.

---

## 5. progress.json parity

After successful publish+complete for Linear:

```json
{
  "provider": "linear",
  "issue_identifier": "ENG-123",
  ...
  "decision": "proceed",
  "status": "complete",
  "stages": {
    "research": {"status": "done"},
    "plan": {"status": "done"},
    "implement_or_refuse": {"status": "done"},
    "test": {"status": "done"}
  },
  "branch_url": "https://github.com/stepango/grkr/tree/linear-eng-123",
  "pr_url": "https://github.com/stepango/grkr/pull/NNN"
}
```

- `mark_task_progress_complete` already sets `status=complete`, `decision=proceed`, forces implement/test done, and records the urls. It is provider-agnostic.
- No new stage key (PrSummary is internal to Linear state mapping, not a progress.json stage).

On publish failure before the mark: status remains planning (or failed only via other paths); no urls recorded.

---

## 6. Fixtures / test plan

**Primary test**: Evolve `test/grkr-linear-issue-implement.sh` (preferred for end-to-end signal) or introduce a clear publish continuation.
- Drive `bash .../grkr.sh --linear-issue ENG-123` with success codex + passing TEST_COMMAND.
- gh stub: permit `pr list|create|edit` (record invocations); fail on GitHub issue label edits or stray `issue view` / `issue comment`.
- Assert:
  - `STAGE=complete` (not test).
  - `research.md`, `plan.md`, `implementation.log`, `test.md` present.
  - Commit message in git log contains `ENG-123` (no #) and title.
  - `gh pr create` (or edit) invoked with `--head linear-eng-123`.
  - `progress.json`: `provider=linear`, `status=complete`, `decision=proceed`, `branch_url` + `pr_url` present.
  - `complete.linear-state-mutation.txt` (or publish.*) contains Done / TARGET_STATE + query.
  - `complete.linear-mutation.txt` contains completion body with PR link.
  - No "implemented"/"todo" label edits in gh log.
  - Worktree dir may remain on disk; CURRENT cleared.
- No-changes subcase: patch so diff --cached is quiet after stage; assert publish returns 0 gracefully, still reaches complete + Linear Done plan (PR_URL may be absent or prior).
- Failure subcases:
  - Line limit violation that remediation does not fix → publish aborts, no mark complete, non-zero exit.
  - Simulated `gh pr create` failure → no mark complete.
- Refuse and test-fail subcases remain (no complete artifacts).

**Regression**:
- All GitHub `--issue` tests (smoke, implement-to-refusal, pr-body-limit, etc.) unchanged and green.
- `gleam test` + `npm test` green.
- No live Linear token required.

**Gleam**:
- Existing tests for `implement_stage` (Linear msg), `linear_state` (PrSummary/Done), `checkpoint_stage` remain valid.
- Optional: add a tiny render or mutation test if a new pure surface is added (not required).

**Run**:
- `npm test`
- `gleam test`
- Manual fixture run with success path reaching complete.

---

## 7. Risks + mitigations

- Accidental GitHub label edits or issue comments from Linear path → **Mitigation**: explicit guards + test stub that exits non-zero on `gh issue edit --.*label` or `gh issue comment` during Linear runs; code review; keep Linear publish logic in `linear_issue.sh`.
- Duplicating publish logic → **Mitigation**: reuse `stage_relevant`, `ensure_publishable_file_sizes`, git_in_issue_context, extract helpers (thin Linear body variant only). Put sequencing + Linear mutation planning in linear_issue.sh.
- PR body "Fixes #ENG-123" or wrong footer → **Mitigation**: Linear path uses identifier without # and omits/ replaces the GitHub footer (new thin extract or post-process). Document "Linear: ENG-123" + URL convention.
- `mark_task_progress_complete` clobbering Linear fields → **Mitigation**: it is pure jq status + url injection; it already works for refused paths; audit shows it preserves `provider` and other keys.
- gh pr create stub breakage in existing linear test → **Mitigation**: evolve stub with case that allows pr ops only when Linear publish is active; keep strict "UNEXPECTED" for GitHub issue mutations.
- File size in linear_issue.sh or bin/grkr → **Mitigation**: current headroom; extract early per AGENTS if needed.
- No-changes path must still complete Linear item → **Mitigation**: mirror GitHub (publish returns 0, flow continues to mark + comment). Explicit subtest.
- Resume / idempotency for completion comment → **Mitigation**: local presence of progress `status=complete` + `pr_url` + completed mutation dumps is sufficient for this slice (same as prior Linear stages).

---

## 8. Product decisions (CRITICAL — clear default)

**Recommended default: (A) — GitHub PR from the linear-* branch + Linear completion planning.**

Rationale (grounded in live code + specs):
- The execution environment already has `gh`, `REPO`, and git configured; the same automation that publishes GitHub-originated work can surface `linear-eng-123` branches as reviewable PRs.
- Spec/25 ("create or update a PR") and Spec/26 ("record branch and PR URL", completion actions) are satisfied by producing a real PR and recording its URL.
- Linear worktrees already create real git branches (`linear-$TASK_SLUG`). Leaving them un-pushed and without PR would make changes invisible to standard code review.
- `create_comment_with_pr_link`, `render_pr_summary`, `PrSummary` stage, and `linear_state.done` ("Done") are pre-built exactly for linking PRs back into Linear comments and moving to Done.
- Review code in GitHub (familiar surface, CI, diff) while tracking status in Linear is a practical integration; "Linear-only" (B) would require a different hosting/review story that is not justified as the default here.
- Prior designs (implement + test) deferred "GitHub PR + Fixes footer? Linear comment link?" — this slice resolves it decisively with a clean default.
- (C) with a flag adds surface area and test matrix for the first green slice; default to (A) which is implementable today. A future flag for "Linear-only, no PR" can be added without breaking the default.
- Test stub impact is manageable (controlled allow-list for pr ops in the Linear publish test only).

If a human overrides: document under "Product decisions" and adjust the implement card. But ship (A) as the clear, reviewable, tool-reusing default.

Other decisions (non-blocking):
- Commit message: `feat(robot): implement ENG-123 <title>` (already implemented via `--provider linear`).
- PR body: omit "Fixes #N"; include "Linear: ENG-123" and/or the Linear issue URL.
- GitHub labels ("implemented"/"todo"): skipped for Linear (issue-specific).
- STAGE echo on success: `STAGE=complete` (signals terminal for the Linear workflow).
- Completion comment stage key: prefer `pr_summary` (matches checkpoint_stage terminal + render surface) or a dedicated "complete" body; either is acceptable.

---

## 9. Smallest implement-slice acceptance criteria (for child implement card)

Ship in **one PR**:

- After successful test for `--linear-issue`, the flow continues and performs publish (git stage+commit with Linear message + push + gh pr create/edit for the `linear-*` branch) and plans Linear completion.
- `mark_task_progress_complete` called; `progress.json` has `status=complete`, `branch_url`, `pr_url`; `provider=linear` preserved.
- Linear Done state mutation planned (dry-run dump containing "Done" or `LINEAR_STATE_DONE` target).
- Linear completion comment planned (dry-run dump with summary + branch/PR links).
- `STAGE=complete` emitted; worktree CURRENT cleared on success path.
- No-changes case: publish returns 0 gracefully, still reaches complete + Linear plans.
- Publish failure (e.g. persistent line limit or gh failure): non-zero, no mark complete, no Linear Done plan.
- GitHub `--issue` full path (publish + labels + complete + gh project Done + completion comment) + all GitHub tests remain 100% green with zero behavior change.
- Evolved/extended shell test exercises Linear success path to complete; asserts artifacts, correct commit/PR, no stray GitHub label edits, controlled gh pr usage.
- `gleam test` + `npm test` green; `gleam build` clean.
- README.md + docs/gleam-migration.md updated with thin "Linear publish + complete dry-run landed" note (per AGENTS).
- No file exceeds 1000 LOC.
- No live Linear GraphQL (all mutations planned/dumped).
- Worktree + exit code handling consistent with GitHub publish/complete.

---

## 10. Out of scope for this implement PR

- Live `GRKR_LINEAR_MUTATE=1` apply for completion comment/state.
- Supervisor / pick / scheduler / worker changes.
- Changes to GitHub publish, PR body footers, label handling, or project moves.
- Full Linear completion flow beyond dry-run planning (e.g. no remote comment lookup for resume).
- Adding a pure Gleam "complete" renderer (shell orchestration + existing renderers are sufficient).
- Updating spec/parts content (wiring only; run sync-spec for index if needed).
- New flags for "no PR" mode (document as future if product decides later).

---

## 11. Recommended implementation order for implement worker

1. Decide thin extraction point in bin/grkr for Linear PR body (omit Fixes footer, add Linear link) — keep diff small.
2. In `bin/lib/linear_issue.sh`:
   - Add `ensure_linear_publish_complete` (or sequenced publish + complete helpers) after the existing test success return site.
   - Reuse `ensure_publishable_file_sizes`, `stage_relevant_issue_files`, `git_in_issue_context`, `generate_linear_implement_commit_message`, `extract_*_pr_body` (or variant), `mark_task_progress_complete`, `run_progress_cli`.
   - Commit with Linear message; gh pr create/edit (no labels); plan Done state + completion comment dumps using PrSummary where appropriate.
   - Success: clear CURRENT, STAGE=complete, return 0.
   - Failure paths: early return without complete side effects.
3. Wire continuation inside `process_linear_issue` (minimal).
4. Update/evolve the shell test (allow pr ops for Linear publish path; add assertions for complete artifacts + no label edits).
5. Run verification: `gleam build`, `gleam test`, `npm test`, manual fixture runs (success + no-changes + failure cases).
6. Update README + gleam-migration (thin notes per AGENTS).
7. (Optional) `scripts/sync-spec.sh`.

---

## 12. Paste-ready implement card brief with /goal

```
/goal Wire Linear publish + complete after successful test for --linear-issue (GitHub PR from linear-* branch + mark complete + Done state + completion comment, dry-run). GitHub default + regression untouched.

Context: tip bfee58c (post #98 test dry-run). process_linear_issue ends at STAGE=test with status=planning, worktree left, no commit/PR/complete. GitHub publish_issue_changes + mark_task_progress_complete + post_completion_comment complete. implement_stage already supports --provider linear; linear_state + checkpoint_stage + linear_mutation scaffold PrSummary/Done + with-pr-link. generate_linear_implement_commit_message exists. Current linear test asserts no pr create.

Read (must):
- AGENTS.md (≤1000 LOC, thin bin/, update README after func change, spec/parts canonical, GitHub default, shared delegates)
- spec/parts/17-issue-workflow-overview.md, 25-stage-4-implement.md, 26-stage-5-test.md (§22.4), 39-recommended-implementation-order.md
- docs/design-linear-test-stage.md (explicit next-slice = publish/complete) + design-linear-implement-stage.md + this design
- bin/grkr (publish_issue_changes ~635, extract_codex_pr_body, ensure_publishable_file_sizes, ensure_pr_body_limit, post_completion_comment, process_issue tail ~821-844, stage_relevant, git_in_issue_context)
- bin/lib/linear_issue.sh (full; ensure_linear_test_checkpoint end state, process_linear_issue)
- bin/lib/task_progress.sh (mark_task_progress_complete — provider-agnostic)
- bin/grkr-issue-workflow.sh (generate_linear_implement_commit_message)
- src/grkr/workflow/implement_stage.gleam (linear commit msg)
- src/grkr/progress/{linear_state.gleam (done + PrSummary), linear_mutation.gleam (create_comment_with_pr_link), checkpoint_stage.gleam (PrSummary), cli.gleam + main.gleam}
- test/grkr-linear-issue-implement.sh (evolve; gh stub constraints)
- README.md Linear section + docs/gleam-migration.md

Acceptance (one PR):
- Linear success after test: stages relevant, commits with "feat(robot): implement ENG-123 ...", pushes linear-* branch, gh pr create/edit, skips labels; mark_task_progress_complete with urls; plans complete.linear-*.txt (Done state + completion comment using pr_summary or sensible); STAGE=complete; CURRENT cleared.
- No-changes: publish returns 0, still completes.
- Publish failure: no mark complete.
- GitHub --issue path + all gh tests 100% unchanged.
- No live mutate; dry-run only.
- Tests + docs notes; gleam build/test + npm test green; no file >1000 LOC.

Product default: (A) GitHub PR + Linear completion (rationale in design §8).

Non-goals: live GraphQL, GitHub changes, supervisor work.

Use Grok Build CLI --mode implement (or full). After changes run gleam build + relevant tests. Follow AGENTS exactly.
```

---

**End of design document.**

Next: implement worker takes this + listed files + AGENTS.md + relevant spec parts, writes self-contained prompt, runs the build CLI, verifies `gleam build` / tests, and completes the card.

---

**Post-write verification note (for this design phase)**: After creating only `docs/design-linear-publish-stage.md`, a clean `git status --porcelain` (ignoring pre-existing untracked `.grkr/` noise and build artifacts) should show the new design doc as the sole intentional change in the working tree. No product files under `bin/`, `src/`, or `test/` were modified. (Confirmed via read-only exploration; the implementer will run the status check after their changes.)