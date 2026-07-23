# Design: pure Gleam checkpoint-json helpers (GO/NO-GO)

**Status**: Design-only (plan agent). No product shell/Gleam body moves.  
**Top-line verdict: NO-GO**  
**Reference tip**: origin/main @ **b3c614f** (docs #205); product tip **851bed2** / PR #203 (issue_shared concern-split FINAL); design parent chain includes github stages-split **6dc13ac** / #189 + concern-split design **a594167** / #191.  
**Prior design artifacts**:
- `docs/design-github-issue-lib-thinning.md` §5 remaining table row “Checkpoint comment json helpers (optional; low-ROI)”
- `docs/design-github-issue-stages-split.md` (helpers live in research_plan sibling; “No checkpoint-json Gleam extract”)
- `docs/design-issue-shared-concern-split.md` (explicit non-goal: no checkpoint-json pure Gleam extract)
- `docs/gleam-migration.md` / README: remaining pure Gleam = checkpoint-json optional/low-ROI  
**Gap addressed**: Spec/39 GitHub core and shell thinning/concern-splits are complete. The only documented remaining *optional* pure Gleam extract is these ~25 LOC jq helpers. This card decides GO vs NO-GO with contracts, surface, parity, LOC, and ROI — **without implementing**.  
**Date**: 2026-07-22  
**Kanban**: t_556cf107  

---

## 0. Verdict

| Decision | **NO-GO** |
|----------|-----------|
| Product action | **None.** Keep `checkpoint_comment_id_from_json` / `checkpoint_comment_body_from_json` as stable shell + jq in `bin/lib/github_issue_stages_research_plan.sh`. |
| Why | ~25 LOC of stable, well-tested jq; Gleam already owns marker format; extract needs JSON decode + CLI/bridge + full GitHub regression for no correctness bug and no shared Linear consumer; prior designs already marked optional/low-ROI; stages-split and concern-split already finished the high-value shell work. |
| Revisit when | (a) Linear (or another provider) needs the same comment-list last-marker select, (b) a real parity bug in jq `last`/empty paths, or (c) a broader pure-Gleam GitHub process facade that absorbs ensure_* and already pays CLI/JSON cost. |

**If forced GO later:** slice 1 must stay tiny — pure library + unit tests + optional CLI only; shell one-line delegates with identical stdout; no `ensure_*` rewrite beyond delegate. See §5.1 hypothetical (not scheduled).

---

## 1. Goal / non-goals

### Goal (this card)

Produce this design file with:

1. Exact current shell contracts (cite live files).
2. Target Gleam surface *if* GO (module path, CLI vs library, FFI, shell thin-delegate).
3. Parity cases from checkpoint-resume + research/plan/test paths.
4. LOC budget vs existing progress modules.
5. Explicit **NO-GO** with ROI rationale (or GO + slice table).
6. Explicit non-goals.
7. Pointer plan for later implement (not required now).

### Non-goals (this card and any deferred GO)

- No behavior change to reuse/restore/post, logs, progress.json comment ids, or gh call sequences.
- No Linear path changes; no mutate default flip.
- No re-open of issue_shared concern-split or github stages-split.
- No doctor rewrite.
- **`fetch_issue_comments_json` stays shell** (gh CLI I/O).
- No `ensure_checkpoint_stage` / `ensure_test_checkpoint` orchestration move to Gleam.
- No new public flags.
- No README tip pin churn required for this design-only card (prefer design file only).
- Design phase: **docs only**; no `bin/` or `src/` product logic.

---

## 2. Current state (cite files)

### 2.1 Shell helpers (live contracts)

**File:** `bin/lib/github_issue_stages_research_plan.sh` (stages-split slice 1; GitHub-only)

| Function | ~LOC | Role |
|----------|------|------|
| `fetch_issue_comments_json` | ~8 | `gh issue view --comments --json comments`; stays shell forever |
| `checkpoint_comment_id_from_json` | ~13 | marker → last matching comment `.id` or empty |
| `checkpoint_comment_body_from_json` | ~12 | same select → `.body` or empty |
| `ensure_checkpoint_stage` | ~53 | research/plan reuse / restore / write+post |

**jq contract (identical for id and body; field differs):**

```bash
checkpoint_comment_id_from_json() {
  local issue_json=$1 stage=$2 task_slug=$3
  marker=$(checkpoint_marker "$stage" "$task_slug")
  printf '%s' "$issue_json" | jq -r --arg marker "$marker" '
    ((.comments // []) | if type == "array" then . else [] end
      | map(select((.body // "") | contains($marker)))
      | last
      | .id) // empty
  '
}

checkpoint_comment_body_from_json() {
  # same select; returns .body // empty
}
```

| Concern | Contract |
|---------|----------|
| **Inputs** | (1) JSON string shaped like `gh issue view --comments --json comments` — object with `.comments` array of objects at least `{id, body}`; (2) `stage` string `research` \| `plan` \| `test`; (3) `task_slug` e.g. `issue-1-test-issue`. |
| **Marker** | `checkpoint_marker "$stage" "$task_slug"` → ambient from `bin/lib/issue_shared_progress.sh` → `run_progress_cli marker` → Gleam `grkr/progress/cli` or inline `<!-- grkr:checkpoint stage=%s task=%s version=1 -->`. |
| **Select** | Normalize `.comments` to array (else `[]`); keep comments whose `.body // ""` **contains** marker substring; take **`last`** match (jq last = last array element after filter = newest among matches in list order as returned by gh). |
| **Outputs** | id: jq `-r` string form of `.id` (number prints as digits) or empty; body: text or empty. |
| **Fail → empty** | missing comments key; non-array comments; no marker match; null id/body; empty input handled by jq `// empty`. |
| **Does not** | fetch from network; write files; update progress; post comments. |

**Sibling fetch (stays shell always):**

```bash
fetch_issue_comments_json() {
  comments_json=$(gh issue view "$issue" --comments --json comments 2>/dev/null || true)
  [ -n "$comments_json" ] || comments_json='{"comments":[]}'
  printf '%s\n' "$comments_json"
}
```

### 2.2 Callers

| Caller | File | Use |
|--------|------|-----|
| `ensure_checkpoint_stage` | same research_plan.sh | research/plan: id for reuse; body for restore; id after post re-fetch |
| `ensure_test_checkpoint` | `bin/lib/github_issue_stages_test.sh` | test stage: same three call sites |

**Reuse/restore algorithm (both ensure_*):**

1. `comment_id=$(…_id_from_json …)`  
2. If local `$stage.md` exists **and** id non-empty → reuse; `update_task_progress_stage … done $comment_id`; return.  
3. If id non-empty **and** no local file → body from json; if body non-empty write file, restore log, progress done; return.  
4. Else write checkpoint, `gh issue comment --body-file`, `fetch_issue_comments_json`, id-from-json again, progress update.

### 2.3 Marker ownership (already Gleam)

| Piece | Location | Notes |
|-------|----------|-------|
| Marker HTML | `src/grkr/progress/checkpoint_id.gleam` | `to_html_comment`, `matches_marker` |
| Stage enum | `checkpoint_stage.gleam` | research/plan/test/… |
| CLI `marker` | `src/grkr/progress/cli.gleam` | argv `marker <stage> <task-slug>` |
| Shell bridge | `issue_shared_progress.sh` | `run_progress_cli` + `checkpoint_marker` |

Shell jq uses **substring contains(full marker string)** — same idea as `checkpoint_id.matches_marker` / `string.contains`, but over a **list of comment bodies from JSON**, then **last**.

### 2.4 What is *not* present

- No Gleam decode of `{comments: [{id, body}]}` for checkpoint select.
- No progress CLI subcommand for comment-id/body-from-json.
- No Linear caller of these two functions (GitHub-only; Linear uses different resume/mutation machinery).
- No open bug report against jq last-select in-repo.

### 2.5 Related sizes (LOC budget context)

Approximate at design time (content lines):

| File | ~LOC | Role |
|------|------|------|
| `checkpoint_comment_*` bodies (combined) | **~25** | candidate extract |
| `github_issue_stages_research_plan.sh` | ~111 | home of helpers + ensure research/plan |
| `github_issue_stages_test.sh` | ~154 | test ensure; calls helpers |
| `issue_shared_progress.sh` | ~37 | marker bridge |
| `src/grkr/progress/checkpoint_id.gleam` | ~75 | marker format / match |
| `src/grkr/progress/checkpoint_render.gleam` | ~104 | render + has_checkpoint_marker |
| `src/grkr/progress/checkpoint_plan.gleam` | ~144 | plan/facade helpers |
| `src/grkr/progress/cli.gleam` | (busy CLI surface) | large CLI surface already |
| `gleam.toml` deps | stdlib + javascript only | **no gleam_json** |

All ≪1000. Extract is not driven by LOC pressure.

---

## 3. Target Gleam surface (hypothetical GO only)

Documented for completeness; **not scheduled**.

### 3.1 Module path

Prefer small pure module next to existing marker code:

- **`src/grkr/progress/checkpoint_comments.gleam`** (library)  
  - `select_last_matching_comment_id(json: String, marker: String) -> String`  
  - `select_last_matching_comment_body(json: String, marker: String) -> String`  
  - Or single internal `select_last(json, marker) -> Option(#(id, body))` + two thin exporters matching shell stdout.

Reuse **`checkpoint_id.matches_marker`** / `to_html_comment` only if stage is validated Gleam-side; shell today builds marker via CLI then passes string — parity-preserving path is:

- **Option A (closest parity):** shell still calls `checkpoint_marker`; Gleam receives `(issue_json, marker_string)` and only does JSON select.  
- **Option B:** Gleam receives `(issue_json, stage, task_slug)`, validates stage, builds marker internally. Slightly more logic; must match CLI marker byte-for-byte including fallback path when gleam missing (shell fallback already matches version=1 format).

**Recommend Option A** if ever GO: minimize dual marker paths.

### 3.2 JSON decode (FFI needs)

Repo pattern: **no gleam_json**; workflow uses `src/grkr/workflow/json_ffi.mjs` + `workflow/ffi.gleam` (`parse`, `get_field`, `decode_array`, `decode_string`, `decode_int`, `is_null`).

GO choices:

1. **Reuse workflow JSON FFI** from progress (cross-package import of workflow FFI — coupling smell).  
2. **Copy/thin shared json helper** under `src/grkr/json/` — new shared surface (scope creep).  
3. **Add gleam_json dependency** — new dep for ~25 LOC callers (heavy).  
4. **Keep jq** — status quo (**chosen**).

### 3.3 CLI vs library

If GO shell-thin:

- Extend `grkr/progress/cli` with e.g.  
  - `checkpoint-comment-id <stage> <task-slug>` reading JSON from stdin  
  - `checkpoint-comment-body <stage> <task-slug>` stdin  
  Or marker-string variants to match Option A.  
- Shell wrappers keep **stable names** `checkpoint_comment_*_from_json` and replace jq body with:

```bash
printf '%s' "$issue_json" | run_progress_cli checkpoint-comment-id "$stage" "$task_slug"
```

**Cost:** every resume/restore/post path pays `gleam run -m grkr/progress/cli` startup (marker already does once; this adds more cold starts per stage). jq is cheap and already on the critical path via other tools.

### 3.4 Shell thin-delegate (GO)

- Replace only the jq pipelines inside the two functions.  
- Do **not** rewrite `ensure_*` beyond calling the same function names.  
- `fetch_issue_comments_json` unchanged.

---

## 4. Parity cases

### 4.1 From `test/grkr-checkpoint-resume.sh`

| Case | Expectation |
|------|-------------|
| Pre-seeded comments JSON with research id 1111 + plan 1112 + local research.md/plan.md | Log `♻️ Reusing research… 1111` and `♻️ Reusing plan… 1112`; progress.json comment_ids 1111/1112 |
| Research/plan markers must **not** be re-posted | No research/plan markers in new issue-comment body log |
| Test stage posts new checkpoint | test marker present; comment_id 1113 |
| Marker format | `<!-- grkr:checkpoint stage=… task=issue-1-test-issue version=1 -->` |

Fixture comments are a **raw array** in the mock file; mock `gh issue view` wraps as `{ …, comments: $comments }`. Helpers must see the **object** shape from `fetch_issue_comments_json` / issue view.

### 4.2 Research/plan via `ensure_checkpoint_stage`

| Path | Condition | Helper use |
|------|-----------|------------|
| Reuse | file exists + id non-empty | id only |
| Restore | id non-empty + no file + body non-empty | id + body |
| Fresh post | else | write templates; gh comment; fetch; id on refreshed JSON |

### 4.3 Test via `ensure_test_checkpoint`

Same three paths; stage fixed `test`; after post, failed commands → progress failed + exit 1 still using fetched id.

### 4.4 Edge parity (unit-level if GO)

| Input | Output |
|-------|--------|
| `{}` / no comments | empty |
| `"comments": null` or non-array | empty |
| comments without marker | empty |
| multiple matches | **last** only |
| body null / id null | empty |
| id number vs string | jq -r digit string (progress.json stores number in fixture asserts — shell/progress layer may coerce; do not change) |

### 4.5 Spec refs

- `spec/parts/27-checkpoint-comment-format.md` — machine-detectable markers  
- `28` research, `29` plan, `31` test checkpoint bodies  
- `18` task folder, `19-20` research/plan stages, `26` test stage  

Spec does **not** require Gleam ownership of comment-list JSON select.

---

## 5. LOC budget

| Rule | Application |
|------|-------------|
| Every file ≤1000 | Already true; GO would add ≪200 LOC total |
| Prefer small modules | `checkpoint_comments.gleam` ~40–80; tests ~40–80; cli +10–20 |
| Existing progress | checkpoint_id/render/plan/cli all small–medium; cli already busiest |

**GO estimated delta (if ever):**

| Piece | Est. |
|-------|------|
| `checkpoint_comments.gleam` | +50–80 |
| unit tests | +40–80 |
| cli subcommands | +15–30 |
| shell body replace | −20 jq / +5–15 gleam run bridge |
| JSON FFI share or dep | +0–80 depending on approach |
| **Net value** | movement of ~25 LOC of clarity into ~100–200 LOC of stack |

**NO-GO delta:** +this design doc only.

### 5.1 Hypothetical slice table (GO — not scheduled)

| # | Title | Primary files | Acceptance | Est. |
|---|-------|---------------|------------|------|
| 0 | This design | `docs/design-checkpoint-json-gleam.md` | NO-GO recorded | doc |
| 1 | Pure library + gleeunit | `checkpoint_comments.gleam` + test | jq fixture parity matrix; no shell wire | +80–120 |
| 2 | CLI + shell one-line delegate | `cli.gleam`, research_plan.sh | stdout identical; checkpoint-resume + smoke green | +20–40; shell thin |
| 3 | Docs tip | README + gleam-migration | “checkpoint-json landed” or remove remaining note | docs |

Slice 1 alone is one implement card; **do not start** under current ROI.

---

## 6. NO-GO decision and ROI rationale

### Cost of GO

1. JSON decode infrastructure choice (dep vs FFI coupling vs copy).  
2. CLI surface growth on already-large `progress/cli.gleam`.  
3. Extra `gleam run` latency on every ensure path (id ± body ± post-refetch).  
4. Full GitHub regression: smoke, checkpoint-resume, refusal, impl-to-refusal, line-limit, pr-body-limit, progress-cli, etc.  
5. Ongoing dual-path risk until shell jq fully deleted (and fallback-without-gleam behavior for select — today jq works without gleam.toml; Gleam select would not unless shell keeps jq fallback).

### Benefits claimed — checked

| Claim | Finding |
|-------|---------|
| Correctness / bugfix | No in-repo bug in last-select; tests green on reuse path |
| Maintainability | Helpers already isolated in focused research_plan sibling (~111 LOC), not a god-file |
| Shared with Linear later | Linear does **not** use gh comments JSON select today |
| CLI half-built | Marker/render yes; **comment-list select no** |
| LOC pressure | None (files ≪1000) |
| Completeness of “pure Gleam remaining” | Cosmetic checklist only; migration docs already say optional/low-ROI |

### Honest ROI

> These helpers are ~25 LOC of stable jq. Gleam already owns marker format. Extract is mostly ceremony (JSON + CLI + regression) for a GitHub-only pure select. **Prefer NO-GO.**

Board/product context: concern-split FINAL, stages-splits complete, no open need for this extract.

### Why not the “tiny GO slice” anyway?

Even a library-only slice creates a second source of truth until shell wires it, or dead code if unwired. Wiring adds process spawns and fallback complexity (jq works without Gleam project root; pure Gleam select does not). The research_plan sibling already isolates the concern. **Skip.**

---

## 7. Explicit non-goals (reminder)

- No behavior change  
- No Linear changes  
- No re-open issue_shared concern-split  
- No doctor rewrite  
- No moving `fetch_issue_comments_json` off shell  
- No ensure_* orchestration rewrite  
- No product Gleam/shell in this design card  

---

## 8. Pointer plan (later implement only — N/A under NO-GO)

Under **NO-GO**:

- **This card:** add `docs/design-checkpoint-json-gleam.md` only; optional one-line cross-link from `docs/design-github-issue-lib-thinning.md` §5 row → this file.  
- **Do not** require README / gleam-migration tip pins for design-only (tips already say optional/low-ROI). Optional later hygiene: change “remaining pure Gleam: checkpoint-json optional/low-ROI” to “checkpoint-json **NO-GO** per design-checkpoint-json-gleam.md” on a docs tip-sync if desired — not required for acceptance.  
- **If a future card reopens GO:** update gleam-migration “Next” + README remaining bullet when product lands; keep fetch in shell; slice 1 library-only first.

Optional design-only cross-link sentence for thinning doc §5:

> See `docs/design-checkpoint-json-gleam.md` — **NO-GO** (leave shell jq; low ROI).

---

## 9. Acceptance checklist (this design card)

- [x] Design content complete with explicit **NO-GO**  
- [x] Current shell contracts documented with live file cites  
- [x] Target surface documented (hypothetical only)  
- [x] Parity cases listed  
- [x] LOC budget noted  
- [x] NO-GO ROI rationale explicit (no implement slice scheduled)  
- [x] Non-goals listed  
- [ ] File committed as `docs/design-checkpoint-json-gleam.md`  
- [ ] No product behavior change (satisfied if commit is docs-only)

---

## 10. Regression surface (only if GO ever ships)

**Must:** `gleam build`, `gleam test`, `npm test`, `test/grkr-checkpoint-resume.sh`, `test/grkr-smoke.sh`, refusal + implementation-to-refusal, progress-cli, line-limit, pr-body-limit.  
**Linear:** non-regression only (untouched).  
**bash -n** on touched shells.

---

## Approach summary

| Item | Choice |
|------|--------|
| **Verdict** | **NO-GO** |
| **Product code** | None |
| **Deliverable** | `docs/design-checkpoint-json-gleam.md` |
| **Optional** | One cross-link in `design-github-issue-lib-thinning.md` §5 |
| **Commit msg** | `docs: design checkpoint-json Gleam helpers GO/NO-GO (t_556cf107)` |
| **Why not GO** | ~25 LOC stable jq; marker already Gleam; no Linear share; no bug; no LOC pressure; extract cost (JSON FFI/dep + CLI + gleam run + full suite) ≫ benefit; prior docs already low-ROI |
