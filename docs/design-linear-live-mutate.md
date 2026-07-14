# Design: Linear Live Mutate Apply Path (GRKR_LINEAR_MUTATE)

**Status**: Design-only (plan agent). No product code edits.  
**Reference tip**: origin/main @ **bd523a6** (PR #100 "Linear publish+complete dry-run").  
**Prior design artifacts**: `docs/design-linear-publish-stage.md`, `docs/design-linear-test-stage.md`, `docs/design-linear-implement-stage.md`.  
**Gap addressed**: All Linear mutation sites (research/plan/refuse/implement/test/publish+complete) perform plan + dry-run dump only. `GRKR_LINEAR_MUTATE=1` is a documented no-op. This slice designs the guarded live apply path (default remains dry-run/off) so that when enabled + token present, planned GraphQL executes after each dump. GitHub path untouched; forward-looking slice.  
**Date**: 2026-07-14

---

## 1. Goal / non-goals

### Goal
Design a minimal, safe, default-OFF live apply path for planned Linear GraphQL mutations (`commentCreate`, `issueUpdate`) so that:

- When `GRKR_LINEAR_MUTATE=1` **and** a resolved access token is present (`GRKR_LINEAR_ACCESS_TOKEN` or `~/.linear/token.txt` via `issue_provider/client.resolve_access_token`), the system executes the planned mutation(s) after each dry-run planning step.
- Otherwise (unset / `0` / empty / no token): preserve exact current behavior — plan, dump `*.linear-*.txt`, log dry-run marker, advance local `progress.json`, never POST.
- A single, consistent apply pattern is wired after every dump site (research, plan, refuse, implement, test, complete).
- HTTP layer gains variables support so `{ query, variables }` can be sent (current `postGraphqlSync` only sends `{ query }`).
- Idempotency and safety are explicit: HTML checkpoint markers for comments, stage-scoped state keys, result sidecars, soft-fail defaults, name-only skips.
- GitHub `--issue` / `GRKR_ISSUE_PROVIDER=github` (default) path and all GitHub tests remain 100% unchanged.
- Existing shell tests (dry-run by default) stay green without new env; no live Linear API calls in CI.

Preserve:
- `GRKR_ISSUE_PROVIDER=linear` (or `--linear-issue`) selects Linear; default remains GitHub.
- Thin shell conventions in `bin/`.
- Every file ≤ 1000 LOC (extract helpers early).
- `spec/parts/` as canonical source.
- Prefer shared helpers (`run_progress_cli`, `resolve_access_token`, existing redaction, checkpoint markers) over duplication.
- Never treat OAuth app credentials in `~/.linear/secret.txt` as bearer tokens (existing `resolve_access_token` contract).

### Non-goals (explicitly out of this slice)
- Changing GitHub publish, labels, comments, project moves, or any `process_issue` tail.
- Supervisor / picker / scheduler / worker spawn changes.
- Enabling mutate by default or in CI.
- Auto-resolving state UUIDs from human names without explicit `LINEAR_STATE_*_ID` (unless a tiny, clearly safe optional helper is justified).
- Live CI calls or any network in default test runs.
- Altering the local progress advancement contract (local `stages.*=done` still happens on plan regardless of apply result).
- Full remote resume / comment lookup for idempotency (local dumps + result sidecars + marker presence are sufficient).
- New public flags beyond the documented `GRKR_LINEAR_MUTATE` (and optional `GRKR_LINEAR_MUTATE_STRICT`).

---

## 2. Current state (cite files + tip SHA)

**What exists at bd523a6 (PR #100 publish+complete dry-run)**:

- Full Linear `--linear-issue` path: research → plan → decision → implement (In Progress plan) → test (In Review plan) → publish (real GitHub PR from `linear-*`) + complete (Done plan + completion comment plan).
- Every mutation site uses the same dry-run pattern:
  1. `run_progress_cli linear-comment-mutation|linear-state-mutation|plan-linear-refusal`.
  2. Dump stdout to `*.linear-*.txt` (format: `query\nvariables_json\nidempotency_key`, or name-only `TARGET_STATE=...\nSTATE_MUTATION_PLANNED=0` when no UUID).
  3. Log "🔑 ... (dry-run; set GRKR_LINEAR_MUTATE=1 when live apply lands)".
  4. Never POST; local `progress.json` advances.
- `bin/lib/linear_issue.sh` (~901 LOC) owns the six call sites via `ensure_linear_checkpoint_stage`, `ensure_linear_refusal_checkpoint`, `ensure_linear_implement_in_progress`, `ensure_linear_test_checkpoint`, `ensure_linear_publish_complete`.
- Gleam planning layer:
  - `src/grkr/progress/linear_mutation.gleam` (~174 LOC): `MutationRequest { query, variables_json, idempotency_key }`, `create_comment_mutation` (prepends HTML marker), `update_state_mutation` (key is currently `grkr-state-update-<issueId>` — stage-agnostic), `create_comment_with_pr_link`, `mutation_result_from_response`, `is_idempotent_error`, `should_retry_mutation`, `check_token_status`, `format_mutation_for_logging` (redacts variables).
  - `src/grkr/progress/cli.gleam` + `main.gleam`: planning-only CLIs; `emit_mutation` prints the three-line form.
  - `src/grkr/progress/checkpoint_id.gleam`: `<!-- grkr:checkpoint stage=... task=... version=1 -->` + `grkr-checkpoint-<stage>-<slug>`.
- Refusal also plans via Gleam (`src/grkr/refusal/linear_flow.gleam`) + writes dumps.
- `src/grkr/issue_provider/client.gleam`: `resolve_access_token`, `run_graphql_query` → `post_graphql`.
- `src/grkr/issue_provider/linear_http.mjs`: `postGraphqlSync` only ever does `JSON.stringify({ query: payload })`; **no `variables` field**. This is the critical blocker for live apply of planned mutations (which separate query + variables_json).
- Alternate stack: `src/grkr/linear/{client.gleam, graphql.gleam, client_ffi.mjs}` (promise-based, used only by opt-in e2e tests) properly includes variables. Design recommends reusing the **issue_provider** sync path for progress apply.
- State names: `linear-state <stage>` CLI + `LINEAR_STATE_*` / `*_ID` envs; no auto-resolution from names in this scope.
- Tests: `test/grkr-linear-issue-implement.sh` (full path to complete), `test/grkr-linear-issue-mvp.sh`, `test/grkr-linear-refuse-progress.sh`; all fixture/stub-based; no network Linear.
- Logs and README explicitly say `GRKR_LINEAR_MUTATE` is reserved / no-op today.

**What is missing**:
- No execution of planned `MutationRequest`.
- No variables support in the HTTP path used by issue_provider.
- No apply guard, no result sidecar, no apply ledger.
- State idempotency key is not stage-scoped.

---

## 3. Inventory table of every dry-run mutation site

All sites at bd523a6 (PR #100). Pattern is uniform: plan → dump → dry-run log. Local progress advances independently.

| Stage / function                        | Dump file(s)                              | GraphQL intent          | State target env (name / id)          | Notes on dump when no id |
|-----------------------------------------|-------------------------------------------|-------------------------|---------------------------------------|----------------------------|
| `ensure_linear_checkpoint_stage` research | `research.linear-mutation.txt`           | commentCreate          | n/a                                   | — |
| `ensure_linear_checkpoint_stage` plan   | `plan.linear-mutation.txt`               | commentCreate          | n/a                                   | — |
| `ensure_linear_refusal_checkpoint`      | `refusal.linear-mutation.txt`, `refusal.linear-state-mutation.txt`, `refusal.linear-plan.txt` | commentCreate + optional issueUpdate | `LINEAR_STATE_BACKLOG` / Backlog (+ optional `LINEAR_STATE_BACKLOG_ID`) | Name-only + `STATE_MUTATION_PLANNED=0` when no id |
| `ensure_linear_implement_in_progress`   | `implement.linear-state-mutation.txt`    | issueUpdate            | `LINEAR_STATE_IMPLEMENT` / `LINEAR_STATE_IMPLEMENT_ID` | Name-only record |
| `ensure_linear_test_checkpoint`         | `test.linear-mutation.txt`, `test.linear-state-mutation.txt` | commentCreate + issueUpdate | `LINEAR_STATE_TEST` / `LINEAR_STATE_TEST_ID` | Name-only when no `LINEAR_STATE_TEST_ID` |
| `ensure_linear_publish_complete`        | `complete.linear-state-mutation.txt`, `complete.linear-mutation.txt` | issueUpdate Done + commentCreate (pr_summary) | `LINEAR_STATE_DONE` / `LINEAR_STATE_DONE_ID` | Name-only when no id |

Dump wire formats (observed):
- Comment/state full: `query\nvariables_json\nidempotency_key\n` (three lines).
- Refusal fallback: extracts via `---COMMENT_QUERY---` / `---STATE_VARIABLES---` markers into same three-line files.
- Name-only state: `TARGET_STATE=...\nSTATE_MUTATION_PLANNED=0\n` (no query line; cannot apply).

Idempotency keys today:
- Comments: `grkr-checkpoint-<stage>-<slug>` (via marker).
- State: `grkr-state-update-<issueId>` (stage-agnostic; collision risk across implement/test/complete/refuse).

---

## 4. Minimal apply path architecture

Prefer the **smallest safe slice** that reuses existing surfaces.

### 4.1 Central apply helper (dual surface, same contract)

**Shell side (primary wiring point)**: a small helper in `bin/lib/linear_issue.sh` (or thin extracted `bin/lib/linear_mutate.sh` if `linear_issue.sh` nears 1000 LOC):

```sh
# maybe_apply_linear_mutation <dump_file> | <query> <vars_json> <key>
# Behavior:
#   GRKR_LINEAR_MUTATE != 1  → log "LINEAR_MUTATE=dry-run key=..." ; return 0
#   no token                 → log warning, keep dump, "LINEAR_MUTATE=skipped-no-token" ; return 0 (soft)
#   mutate=1 + token         → POST, parse, write sidecar <dump>.linear-apply-result.txt, log explicit marker
#   name-only state dump     → "LINEAR_MUTATE=skipped-no-state-id target=..." ; return 0
```

**Gleam side (optional but recommended for pure parse/apply logic)**: add `linear-apply-mutation` CLI (or extend existing mutation CLIs with an apply mode) that:
- Reads a three-line form (query + vars_json + key) from stdin or file.
- Respects the same env gates.
- Returns structured result for shell consumption or writes the sidecar.

One call-site pattern used by all six stages: immediately after writing the dump file (and before or after the dry-run log line), invoke the apply helper with the just-written path. On apply success the sidecar is authoritative for "what happened".

### 4.2 HTTP variables support (critical)

Extend the issue_provider HTTP surface while preserving backward compat for query-only callers (fetch-issue, assigned-issues, etc.):

Options (choose smallest):
- A) Add `postGraphqlWithVariablesSync(endpoint, auth, query, variables_json)` in `linear_http.mjs` and a matching FFI + wrapper in `client.gleam` (e.g., `run_graphql_query_with_variables` or `run_graphql_mutation`).
- B) Extend `postGraphqlSync` to accept an optional variables payload (string or object) and keep the existing 3-arg form working for query-only.

Recommended: (A) — new narrow surface keeps the read path untouched and obvious. The new path builds `{"query": q, "variables": parsedVars}`.

The Gleam apply layer (or a thin FFI helper) will parse the `variables_json` string into the JS object for the POST.

Do **not** pull the promise-based `linear/client` stack into the sync progress apply path unless a clear justification emerges; issue_provider is already sync and used by the fetch path.

### 4.3 Wiring sketch (after each dump write)

```sh
# After:
printf '%s\n' "$mutation_out" > "$task_dir/$stage.linear-mutation.txt"
# Add:
maybe_apply_linear_mutation "$task_dir/$stage.linear-mutation.txt" "$mutation_issue_id" "$stage"
```

Same pattern for every state mutation dump and the two complete dumps. Refusal path in `linear_flow.gleam` (Gleam) can either shell out to the same helper (preferred) or emit a signal the shell applies uniformly.

### 4.4 Result sidecar + local ledger

- Per-dump sidecar: `*.linear-apply-result.txt` containing at minimum: `key=... status=applied|skipped|failed applied_id=... error=...` (redacted).
- Optional: append-only `.linear-apply-ledger.jsonl` at task_dir root for tooling.
- Resume: if sidecar for the same key reports success, skip re-POST (even if dump file is present).

---

## 5. Safety

### 5.1 Default OFF
- `unset`, `""`, `"0"`, or any value other than literal `1` → dry-run (identical logs and artifacts as today).
- Explicit `GRKR_LINEAR_MUTATE=1` + token → apply.

### 5.2 Idempotency
- **Comments**: body already contains `<!-- grkr:checkpoint stage=... task=... version=1 -->`. Apply may optionally query Linear comments for marker presence before POST; on duplicate error from Linear, treat as success (idempotent). On resume, presence of successful `*.linear-apply-result.txt` for the key is sufficient to skip.
- **State updates**: current key `grkr-state-update-<issueId>` collides across stages. **Proposal**: change planned key generation for state to stage-scoped, e.g.:
  - `grkr-state-<stage>-<issueId>` (simple), or
  - `grkr-state-<issueId>-<stateId>` (more precise).
  - Keep the dump format unchanged (last line is still the key). Pure plan dumps remain compatible.
  - Migration: the planning side (`update_state_mutation`) becomes aware of an optional stage or uses a composite key when called from apply-aware paths. Document the new key format in the implement card.
- Local ledger (sidecar or jsonl) provides the "already applied" signal without requiring remote lookup on every resume.

### 5.3 Name-only dumps
- When a state mutation dump contains only `TARGET_STATE=...` + `STATE_MUTATION_PLANNED=0` (no UUID), apply must **not** guess a UUID.
- Log: `LINEAR_MUTATE=skipped-no-state-id target=In Review key=...`
- Workflow continues (soft). This is the documented contract for "state name known, concrete id not provided".

### 5.4 Ordering for complete
- Current dry-run order in `ensure_linear_publish_complete`: mark complete locally → plan Done state → plan completion comment.
- Recommendation: **apply comment first, then Done state** (so a failure before the state move leaves the issue open with visible evidence in the comment). Alternative (align with GitHub move-then-comment): Done then comment. Document the chosen order explicitly in code + logs; either is acceptable if consistent and stated.
- Hard publish failure gate is preserved: if publish aborts (line limit, commit fail, gh create fail), do **not** call mark complete and do **not** emit or apply Done/comment mutations.

### 5.5 Soft vs hard failure
- Default: **soft-fail** for research/plan/implement/test/refuse mutations (log `LINEAR_MUTATE=failed ...`, write sidecar, continue workflow). A Linear outage must not brick GitHub PR publish.
- Complete mutations: still gated behind successful publish; soft-fail is acceptable but a failed complete mutation after a successful publish should be loud (still non-fatal to the overall exit unless `GRKR_LINEAR_MUTATE_STRICT=1`).
- Optional (can defer to follow-up): `GRKR_LINEAR_MUTATE_STRICT=1` turns selected apply failures into hard errors (non-zero from the apply helper). Refuse path remains soft by default even under strict.

### 5.6 Redaction & secrets
- Never log the token.
- Never log full variables bodies on stderr for mutation apply (reuse/extend `format_mutation_for_logging` which already redacts variables).
- Use existing `client.redact` on any error paths that surface token material.

### 5.7 No partial complete-on-publish-failure
- Identical contract as today: publish failure → no complete side effects, no Done, no completion comment, exit non-zero from the publish helper, CURRENT cleared.

---

## 6. Modules / files to touch (smallest first, LOC estimates)

All estimates keep files ≤ 1000 LOC. Extract early if headroom is threatened.

1. **`src/grkr/issue_provider/linear_http.mjs`** (small; ~65 LOC → +30-50)
   - Add `postGraphqlWithVariablesSync(endpoint, auth, query, variablesJsonString)` (or accept a combined payload).
   - Build `{"query": q, "variables": JSON.parse(v) || {}}`.
   - Preserve the existing `postGraphqlSync` 3-arg form exactly (query-only callers unchanged).

2. **`src/grkr/issue_provider/client.gleam`** (~120 LOC → +20-40)
   - Add `run_graphql_mutation(access_token, query, variables_json)` or `run_graphql_with_variables`.
   - Thin wrapper over the new FFI; reuse redaction + require_access_token.
   - Do not change the query-only `run_graphql_query` signature or callers.

3. **`src/grkr/progress/linear_mutation.gleam`** (~174 LOC → +60-120)
   - Add `apply_mutation(request, token_resolver, poster)` or equivalent pure + effect boundary.
   - Improve `mutation_result_from_response` to parse real Linear success shapes (look for `commentCreate.comment.id`, `issueUpdate.success`, etc.) and surface `comment_id` / state info.
   - Make state idempotency key stage-aware (add optional stage or derive from call context). Keep `update_state_mutation` signature or add an overload; document the key change.
   - Add `parse_apply_result`, helpers for sidecar formatting.
   - Unit-testable pure surfaces for classification and key generation.

4. **`src/grkr/progress/cli.gleam` + `main.gleam`** (cli ~140, main ~420 → +30-70 total)
   - Add CLI entry `linear-apply-mutation <dump_or_stdin>` (reads three-line form, respects env gate, performs apply if allowed, prints machine-readable result or writes sidecar).
   - Or: a flag/mode on existing mutation CLIs (less preferred; separate apply surface is clearer).
   - Expose `check-token` already exists; reuse for gate.
   - Keep all planning CLIs untouched in behavior.

5. **`bin/lib/linear_issue.sh`** (~901 LOC → +40-90; monitor; extract if needed)
   - Add `maybe_apply_linear_mutation` (or source a thin `linear_mutate.sh`).
   - After every dump write in the six sites, invoke the helper.
   - Update header comment to reflect live-apply support when enabled.
   - If this file would exceed 1000, extract `bin/lib/linear_mutate.sh` (thin) before landing.
   - Refusal state + comment apply happens from the same helper (shell path).

6. **`src/grkr/refusal/linear_flow.gleam`** (~299 LOC → +10-30)
   - After writing dumps, either call a shell apply helper (via ffi) or document that the shell orchestrator is responsible for a post-plan apply pass for refusal.
   - Preferred: keep the Gleam flow as "plan + write", and let the uniform shell apply site (after `run_refusal_linear` returns) perform the apply step for consistency with the other five sites.

7. **Tests** (no new LOC pressure on product files)
   - `test/grkr/progress/linear_mutation_test.gleam`: pure tests for parse, gate, idempotent classification, variables encoding, key scoping.
   - Shell tests: evolve or add subcases in existing linear harnesses using PATH-injected stubs for the apply CLI / `postGraphql*` (never live net).
   - Fixture HTTP or `GRKR_LINEAR_APPLY_CMD` override for hermetic apply tests.

8. **Docs (post-func, per AGENTS)**
   - Implement card will update `README.md` + `docs/gleam-migration.md` (thin notes).
   - This design doc is the spec for the slice.

**Explicitly do NOT touch** (per scope):
- `bin/grkr` GitHub paths (`process_issue`, `publish_issue_changes`, `ensure_test_checkpoint`, etc.).
- Any supervisor/, github_picker/, workflow/ (except thin provider dispatch already present).
- `worker-*.sh` (they delegate; behavior change would be via progress apply only).
- GitHub label / project / comment surfaces.

---

## 7. Tests strategy

### Unit (Gleam)
- `linear_mutation_test.gleam` additions:
  - `create_comment_mutation` still prepends marker and produces stable key.
  - `update_state_mutation` key is now stage-scoped when stage provided (or new constructor exercised).
  - `mutation_result_from_response` classifies success (comment id present), state success, errors, and idempotent shapes.
  - Env gate mock: apply returns dry-run / skipped when `GRKR_LINEAR_MUTATE != "1"`.
  - Variables JSON round-trips without injecting secrets into logs.
  - `is_idempotent_error`, `should_retry_mutation` cover Linear-shaped errors.

### Shell (harness, hermetic)
- Use the existing pattern: copy `grkr.sh` + libs into tmpdir, stub `gh`, `git`, `codex`, provide `LINEAR_FIXTURE_PATH`.
- Inject a fake apply surface via `PATH` (a tiny script that prints the required `LINEAR_MUTATE=...` markers and writes sidecars) or set `GRKR_LINEAR_APPLY_CMD` if the design introduces an override.
- Cases (all without real network):
  1. `GRKR_LINEAR_MUTATE` unset/0 → dumps written, no network attempted, classic dry-run logs.
  2. `GRKR_LINEAR_MUTATE=1` but no token → soft skip with `LINEAR_MUTATE=skipped-no-token`, dumps kept, workflow continues.
  3. `GRKR_LINEAR_MUTATE=1` + stub success → sidecar written, `LINEAR_MUTATE=applied key=... comment_id=...`, progress still shows done.
  4. `GRKR_LINEAR_MUTATE=1` + stub idempotent error → `LINEAR_MUTATE=skipped-already`, treated as success for resume.
  5. `GRKR_LINEAR_MUTATE=1` + stub hard error → `LINEAR_MUTATE=failed ...` (redacted), soft-fail (exit 0 from apply helper), workflow continues.
  6. Name-only state dump → `LINEAR_MUTATE=skipped-no-state-id`, no apply attempted.
  7. Resume: prior successful sidecar present → apply helper skips POST.
  8. Complete path only applies after successful publish gate (failure before mark → no complete dumps or applies).
  9. GitHub `--issue` path: zero behavior change; no Linear apply surfaces exercised.

### Regression
- All existing `grkr-*.sh` (GitHub and Linear dry-run) remain green with default env.
- `gleam test` + `npm test` green.
- `gleam build` clean, 0 warnings on touched modules.
- Manual smoke with `GRKR_LINEAR_MUTATE=1` + stubbed HTTP only (never in CI).

### No live API in CI
- `LINEAR_FIXTURE_PATH` + PATH stubs + `GRKR_LINEAR_APPLY_CMD` override are the only mechanisms. Token-bearing runs are developer-only / e2e canary.

---

## 8. Logging / UX markers (copy-paste table for implementer)

| Condition                              | Stderr marker (exact or close)                          | Sidecar written?          | Exit from apply helper |
|----------------------------------------|---------------------------------------------------------|---------------------------|------------------------|
| `GRKR_LINEAR_MUTATE` != 1              | `LINEAR_MUTATE=dry-run key=grkr-checkpoint-...`         | No (or dry-run note)      | 0                      |
| Mutate=1 but no usable token           | `LINEAR_MUTATE=skipped-no-token key=...`                | Optional note             | 0 (soft)               |
| Applied successfully (comment)         | `LINEAR_MUTATE=applied key=... comment_id=cmt_xxx`      | Yes (with remote id)      | 0                      |
| Applied successfully (state)           | `LINEAR_MUTATE=applied key=... state_id=...`            | Yes                       | 0                      |
| Skipped because already applied (idempotent or ledger) | `LINEAR_MUTATE=skipped-already key=...`          | Yes (prior result)        | 0                      |
| Failed (non-idempotent)                | `LINEAR_MUTATE=failed key=... error=...` (redacted)     | Yes (error)               | 0 (soft) or non-zero if STRICT |
| Name-only state (no id)                | `LINEAR_MUTATE=skipped-no-state-id target=In Review`    | Optional                  | 0                      |
| HTTP / parse error during apply        | `LINEAR_MUTATE=failed ...` + redacted details           | Yes                       | 0 (soft)               |

All markers must be grep-friendly and include the idempotency key. Full variables never appear in these logs.

---

## 9. Product decisions with recommended defaults

| Decision | Recommendation | Rationale |
|----------|----------------|-----------|
| Default for `GRKR_LINEAR_MUTATE` | OFF (anything != literal `1` is dry-run) | Matches every prior design; prevents accidental live writes; explicit opt-in. |
| Soft vs hard on apply failure | Soft default for research/plan/implement/test/refuse; complete is gated by publish success. Optional `GRKR_LINEAR_MUTATE_STRICT=1` for hard on selected steps (deferrable). | Linear outage must not brick a GitHub PR publish. Refuse path is advisory. |
| State idempotency key scoping | Stage-scoped: `grkr-state-<stage>-<issueId>` (or `<issueId>-<stateId>`). | Prevents implement vs test vs complete vs refuse colliding in ledgers. Dump format unchanged. |
| Complete apply order | Comment first, then Done (evidence preserved if Done fails). Alternative: Done then comment to mirror GitHub move-then-comment. Document the chosen order. | Comment-then-Done is safer for auditability on partial failure. |
| HTTP surface | New `postGraphqlWithVariablesSync` + Gleam wrapper (keep query-only path byte-for-byte). | Smallest diff; no risk to fetch-issue. |
| Reuse which client stack | issue_provider (sync) for progress apply. | Already used by fetch; keeps the apply path sync and simple. Linear e2e stack remains separate. |
| Name-only state | Never invent UUIDs; skip with clear marker. | Contractual; env `*_ID` is the only source of concrete ids. |
| Local ledger format | Per-dump `*.linear-apply-result.txt` (simple); optional `.linear-apply-ledger.jsonl` later. | Matches existing dump style; easy for shell + tests. |
| Strict mode scope | Optional, can be implemented in follow-up. Refuse remains soft even under strict. | Keeps first slice minimal. |

---

## 10. Acceptance checklist for child implement card

Ship in **one PR**:

- `GRKR_LINEAR_MUTATE=1` (with token) causes planned mutations to be POSTed after dumps for all six sites; default (unset/0) remains pure dry-run with identical artifacts and logs.
- HTTP layer supports variables: new narrow surface added; query-only callers (fetch-issue etc.) unchanged.
- Apply helper (shell ± Gleam CLI) implements the gate, redaction, sidecar, and all listed markers.
- State keys are stage-scoped (or composite) so different stages do not collide.
- Name-only state dumps are skipped with `skipped-no-state-id`.
- Complete path only applies after successful publish gate; publish failure yields no complete mutations or applies.
- Soft-fail default: research/plan/implement/test/refuse apply errors do not abort the overall workflow or prevent GitHub PR publish.
- Idempotency: HTML marker present in bodies; successful sidecar causes resume skip; duplicate Linear errors treated as success.
- All existing Linear shell tests (`grkr-linear-issue-implement.sh`, mvp, refuse) remain green in default (dry-run) mode with zero new env.
- New or extended unit tests cover parse, gate, key scoping, result classification.
- New or extended shell tests cover the apply matrix (dry-run, no-token, success, idempotent, failure, name-only, resume, publish-gate) using stubs only.
- `gleam build`, `gleam test`, `npm test` green; 0 warnings on touched modules.
- No file exceeds 1000 LOC (extract if `linear_issue.sh` or others approach).
- README.md + docs/gleam-migration.md updated with thin "Linear live mutate guarded apply landed" note (per AGENTS).
- GitHub `--issue` paths + all GitHub tests 100% unchanged.
- No live Linear calls in CI; design + code enforce this.
- Design decisions documented in code comments and logs where relevant (order for complete, key format, soft/hard).

---

## 11. Out of scope

- Default-on or CI enablement of `GRKR_LINEAR_MUTATE`.
- Supervisor/picker/scheduler/worker changes.
- GitHub publish or any modification to `process_issue`.
- Full remote comment scan for resume (local sidecars + marker are enough).
- Auto-resolution of state names to UUIDs (env `*_ID` remains required for live state apply).
- New user-facing flags beyond the documented mutate envs.
- Changes to the alternate `linear/` e2e stack (unless needed for a tiny shared redaction helper).
- Updating spec/parts content (wiring only; sync-spec may be run for index hygiene).
- Hard-fail strict mode in the first slice (document as optional follow-up).

---

## 12. Paste-ready implement `/goal` + full brief

```
/goal Implement guarded live Linear mutate apply (GRKR_LINEAR_MUTATE=1) for all planned mutations after dry-run pipeline on main@bd523a6 / PR #100. Default remains dry-run everywhere. Write sidecars, explicit markers, fix HTTP variables support, stage-scoped state keys. GitHub default + regression untouched.

Context: tip bd523a6 (PR #100 publish+complete dry-run). All six Linear stages plan + dump to *.linear-*.txt and log dry-run; GRKR_LINEAR_MUTATE is a no-op. issue_provider/linear_http.mjs only sends {query}. State key today is grkr-state-update-<issueId> (collides). HTML markers already present for comments. resolve_access_token and redaction exist. Tests are fixture/stub only.

Read (must):
- AGENTS.md (≤1000 LOC, thin bin/, update README after func change, spec/parts canonical, GitHub default, shared helpers)
- docs/design-linear-live-mutate.md (this design; all sections)
- docs/design-linear-publish-stage.md + design-linear-test-stage.md + design-linear-implement-stage.md (patterns + inventory)
- bin/lib/linear_issue.sh (full; all six ensure_* mutation sites + dump patterns)
- src/grkr/progress/{linear_mutation.gleam, cli.gleam, main.gleam, checkpoint_id.gleam}
- src/grkr/refusal/linear_flow.gleam (refusal dumps)
- src/grkr/issue_provider/{client.gleam, linear_http.mjs, main.gleam} (fetch path + postGraphqlSync)
- src/grkr/linear/{client.gleam, graphql.gleam, client_ffi.mjs} (variables precedent; prefer issue_provider path)
- test/grkr-linear-issue-implement.sh, grkr-linear-refuse-progress.sh, grkr-linear-issue-mvp.sh (test patterns)
- test/grkr/progress/linear_mutation_test.gleam
- README.md Linear section + docs/gleam-migration.md

Acceptance (one PR):
- GRKR_LINEAR_MUTATE=1 + token executes after dumps for research/plan/refuse/implement/test/complete; else identical dry-run behavior.
- HTTP variables support added (new narrow surface); query-only callers untouched.
- Apply helper emits the exact markers in §8; writes *.linear-apply-result.txt sidecars.
- State keys stage-scoped (no cross-stage collision).
- Name-only dumps skipped with skipped-no-state-id.
- Complete applies only after publish success gate.
- Soft-fail default (research/plan/implement/test/refuse); complete gated.
- Idempotency via marker + sidecar + duplicate-error tolerance.
- Existing dry-run Linear tests green with zero env change; new apply-matrix shell + unit tests using stubs only.
- gleam build/test + npm test green; no file >1000 LOC.
- README + gleam-migration thin notes (per AGENTS).
- GitHub paths 100% unchanged; no live net in CI.

Non-goals: default-on, GitHub changes, supervisor work, auto state name resolution, live CI calls.

Use Grok Build CLI --mode implement (or full). After changes run gleam build + relevant tests + the linear shell harnesses. Follow AGENTS exactly.
```

---

**End of design document.**

After writing: `docs/design-linear-live-mutate.md` exists as the sole intentional product of this design phase. No Gleam or shell source was edited. The implementer will use this + the listed files + AGENTS.md to produce a self-contained prompt for the Grok Build CLI, verify `gleam build` / tests, and complete the card.

---

**Post-write verification (for this design phase)**: A clean `git status --porcelain` (ignoring pre-existing untracked `.grkr/`, build artifacts, and any prior design docs) should show only the addition of `docs/design-linear-live-mutate.md`. Confirmed via read-only exploration; the implement card will run the status check after code changes.