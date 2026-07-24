# Design: Next product thinning after coding-agent polish

**Status**: Design (docs-only)  
**Date**: 2026-07-23  
**Base tip**: origin/main **8395879** (docs tip-sync #216 after product **b49a072** / #215)  
**Kanban**: t_7e55fd9b  
**Design agent**: Grok Build CLI `model=grok-4.5` (`--mode design` / agent `plan`)

**Parents:**  
[`docs/design-coding-agent-polish.md`](design-coding-agent-polish.md) · [`docs/design-swappable-coding-agent.md`](design-swappable-coding-agent.md) · [`docs/design-gleam-coding-agent-swap.md`](design-gleam-coding-agent-swap.md)

---

## Context

| Fact | Evidence |
|------|----------|
| Docs tip | origin/main **8395879** (tip-sync #216) |
| Product tip | **b49a072** / PR #215 — coding-agent polish P0+P1 (doctor COMMENT/RESOLVE template + `GROK_MODEL` default `grok-4.5`) |
| Design parent | polish **910ba27** / #214; Gleam swap #210+#212; issue_shared FINAL #203 |
| Spec/39 items 6–12 | **done** (decision, refusal, implement, test, comments, PR resolve, cleanup/recovery) |
| Closed | checkpoint-json **NO-GO** (**caef425** / #206); artifact `codex/` rename **NO-GO**; third backend **DEFER** |
| Shell verticals | GitHub stages-split **complete** (#189); issue_shared concern-split **complete** (#203); Linear stages-split **complete** (#177); Linear thinning **complete** (#133) |
| AGENTS LOC bar | hard limit **1000**; all measured candidates **≪1000** |
| Prior hygiene floor | splits started ~430–688 LOC (`comment_handler` 430, `linear_mutation` 440, `handle_comment` 456, `resolve_pr` 436, `phases` 688, `progress/main` 644) |
| Priority | **GitHub-first** (picker / refusal / supervisor / GitHub issue path) |

### Measured LOC @ tip (task + live structure)

| Path | LOC | Notes |
|------|-----|-------|
| `src/grkr/coding_agent.gleam` | **399** | Shared Gleam agent select+exec (comment+resolve) |
| `src/grkr/doctor/validate.gleam` | **387** | Doctor probes + config + create-config |
| `src/grkr/refusal/flow.gleam` | **354** | GitHub refusal orchestration + backlog gh |
| `src/grkr/linear/oauth.gleam` | **353** | Linear OAuth only |
| `src/grkr/project_status/planning.gleam` | **341** | Status move planning |
| `src/grkr/supervisor/recovery.gleam` | **336** | Dead/stale/lock recovery |
| `src/grkr/issue_provider/main.gleam` | **321** | Linear provider CLI |
| `src/grkr/supervisor/state.gleam` | **297** | active_jobs + processed comments |
| `src/grkr/supervisor/loop.gleam` | **274** | Tick loop |
| `bin/lib/linear_issue.sh` | **329** | Residual load/decode/bootstrap + thin sequencer |
| `bin/grkr` | **198** | Thin launcher |
| `bin/lib/github_issue.sh` | **71** | Source-only facade |
| `bin/lib/issue_shared.sh` | **77** | Source-only facade |

---

## 1. Status snapshot

### Complete (do not re-open as product gaps)

- Spec/39 core pipeline items **6–12**
- GitHub `process_issue` thinning + `github_issue` stages-split
- Linear thinning + stages-split + guarded live mutate (default OFF)
- Shared helpers extract + issue_shared concern-split FINAL
- Gleam coding-agent swap (comment classify + resolve_pr)
- Coding-agent polish P0+P1 (**b49a072** / #215)
- Deploy Docker+Helm (**deb0acc** / #166)
- Progress/supervisor/handle_comment/resolve_pr/linear_mutation LOC hygiene waves

### Closed NO-GO / DEFER (stand)

| Item | Verdict | Tip |
|------|---------|-----|
| Checkpoint-json Gleam helpers | **NO-GO** | **caef425** / #206 |
| Artifact path `codex/…` → `agent/…` | **NO-GO** leave forever | polish design |
| Third backend / `GRKR_AGENT_CMD` | **DEFER** | polish design |
| Further GitHub/issue_shared shell body split | **NO-GO** (facades already source-only 71/77) | #189 / #203 |
| Linear residual bootstrap further split | **NO-GO leave** (stages already extracted) | #133 / #177 |

### Parent follow-up hygiene (docs-only when landing this design)

- `docs/design-swappable-coding-agent.md` §Follow-ups **item 4** → mark **DONE** (P0+P1 landed #215)
- `docs/design-coding-agent-polish.md` → mark P0+P1 **landed** @ **b49a072** / #215

---

## 2. Inventory table

| # | Workstream | Evidence | Candidate action |
|---|------------|----------|------------------|
| A | `coding_agent.gleam` LOC hygiene | 399 LOC; sections: Types / Agent name / Classify builders / Run / helpers; callers: `handle_comment_codex`, `comment_handler_codex`, `resolve_pr/codex` + unit tests | Optional concern split: types / select / classify / run + thin facade re-export |
| B | `doctor/validate.gleam` LOC hygiene | 387 LOC; clusters: tools+gh, coding-agent probe, config+remote, grkr dir, `run_validate`/`create-config`; sole caller `doctor/cli.gleam` | Optional split: tools / agent / config / orchestrator |
| C | `refusal/flow.gleam` | 354; `run_refusal` ~97 + JSON extract ~100 + backlog/project gh ~150 | Optional extract backlog helpers |
| D | Other Gleam >300 | oauth 353, planning 341, recovery 336, issue_provider/main 321, state 297, loop 274 | Linear-first or cohesive domains |
| E | `linear_issue.sh` residual | 329; load/decode/meta/progress + thin sequencer; stages already out | Leave |
| F | GitHub shell vertical leftovers | facades 71/77 source-only; stage siblings hold bodies | No further shell split |
| G | Eval matrix / docs tip hygiene | matrix latest mock-green; tip-sync process works | Ops/maintain |
| H | Deploy/ops polish | deploy doc + chart landed #166; no documented gap | None unless ops bug |
| I | Spec/39 behavior gaps | items 6–12 done; no invent | None |
| J | Closed parents | checkpoint-json, artifact rename, third backend | Do not reopen |

---

## 3. Verdict table

| # | Item | Verdict | Rationale (evidence) | Risk | Slice size |
|---|------|---------|----------------------|------|------------|
| A | `coding_agent.gleam` concern split | **GO** | Clear comment-delimited seams (types / select / classify argv / run / output). Shared GitHub path hub (comment+resolve). Strong unit tests inject env/exec. Below prior ~430 floor but matches `linear_mutation` facade quality; future agent growth hits this file first. | Low (pure move + re-export) | **S** (1 PR) |
| B | `doctor/validate.gleam` concern split | **GO** | Textbook clusters (tools/auth vs coding-agent vs config/remote vs run/create). Single CLI entry. Startup path for every GitHub run. | Low | **S** |
| C | `refusal/flow` backlog helpers extract | **DEFER** | GitHub-relevant seam exists, but 354 total is under hygiene floor; cohesive orchestration. Revisit only if editing backlog path or file grows. | Low–med | — |
| D1 | `supervisor/recovery` | **DEFER** | Cohesive recovery domain; no multi-concern sprawl like old `phases.gleam`. | Low | — |
| D2 | `supervisor/state` | **DEFER** | Mild seam; 297 LOC; not blocking. | Low | — |
| D3 | `supervisor/loop` | **NO-GO** | 274; tick orchestration only. | — | — |
| D4 | `linear/oauth` | **NO-GO** (priority) | Linear-only; not GitHub-first; cohesive OAuth. | — | — |
| D5 | `project_status/planning` | **DEFER** | Focused API; lower ROI than coding_agent/doctor. | Low | — |
| D6 | `issue_provider/main` | **DEFER** | Linear CLI dispatcher; experimental path. | Low | — |
| E | `linear_issue.sh` residual bootstrap | **NO-GO leave** | Thinning + stages-split complete; residual is legitimate load/decode/bootstrap + sequencer. | Med if forced | — |
| F | GitHub / issue_shared shell further split | **NO-GO** | Facades already source-only (71/77). | High churn / low ROI | — |
| G | Eval matrix / tip hygiene | **DEFER** | Maintain/ops; not broken. | None | — |
| H | Deploy/ops | **NO-GO** (no gap) | Deploy doc + Helm landed. | — | — |
| I | Spec/39 new features | **NO-GO invent** | Items 6–12 done. | — | — |
| J1 | Checkpoint-json Gleam | **NO-GO stands** | **caef425** / #206 | — | — |
| J2 | Artifact `codex/` rename | **NO-GO stands** | Resume risk | — | — |
| J3 | Third backend / `GRKR_AGENT_CMD` | **DEFER stands** | No consumer | — | — |
| K | False-green gleam test / env pollution | **DEFER** | Quality debt only if already tracked; do not invent product card. | — | — |

**Top line:** Product work remains **optional LOC hygiene only**. There is **no** missing GitHub core behavior vs spec/39. Prefer two small pure-extract GOs on GitHub-critical shared modules rather than “no product GO.”

---

## 4. Ordered slice table (GO only)

| Slice | Goal | Primary files | Est. | Depends |
|-------|------|---------------|------|---------|
| **1** | `coding_agent` concern split (thin facade + concern modules) | `src/grkr/coding_agent.gleam` → facade + `coding_agent_types` / `coding_agent_select` / `coding_agent_classify` / `coding_agent_run` (names flexible; keep **stable** `grkr/coding_agent` import path) | S | none |
| **2** | `doctor/validate` concern split | `src/grkr/doctor/validate.gleam` → thin facade + tools / agent / config(/orchestrator); `doctor/cli.gleam` keeps importing `grkr/doctor/validate` | S | none (parallel OK after 1) |

No slice 3 scheduled. Optional later: refusal backlog extract only if touching that path.

---

## 5. Paste-ready implement brief — Slice 1

```text
# Implement: coding_agent.gleam concern split (slice 1)
# Executor: Grok Build CLI --mode implement (or --mode full), model grok-4.5
# Kanban parent design: docs/design-next-product-after-coding-agent-polish.md
# Base: origin/main after design PR lands

## Goal
Zero-behavior LOC hygiene split of src/grkr/coding_agent.gleam (~399 LOC) into a thin
facade that re-exports the stable public API, plus focused concern modules, matching
prior patterns (progress/linear_mutation, handle_comment, comment_handler).

## Natural seams (live file)
1. Types + FFI externs (~L10–60): Step, Agent, RunMode, ExecOutcome, Invocation, FsDeps, FFI
2. Select (~L62–126): agent_name, agent_name_from, resolve_raw_name, normalize
3. Classify argv builders (~L128–226): classify_invocation, classify_codex, classify_grok
4. Run (~L228–356): ExecFn, run, run_with_defaults, run_classify, run_conflict_resolve
5. Output helpers (~L358–399): classify_fail_reply, classify_output, agent_label, format_cmd, …

## Target shape (suggested; implementer may merge 4+5 if cleaner)
- src/grkr/coding_agent.gleam          — thin facade: pub re-exports only (or thin wrappers)
- src/grkr/coding_agent_types.gleam    — types + FsDeps + ExecFn alias if needed
- src/grkr/coding_agent_select.gleam   — agent_name / agent_name_from + raw resolve
- src/grkr/coding_agent_classify.gleam — classify_invocation + codex/grok builders
- src/grkr/coding_agent_run.gleam      — run / run_with_defaults / classify+resolve runners + output helpers
- coding_agent_ffi.mjs stays where it is (or next to types/run — one home only)

Keep public import path `import grkr/coding_agent` working for:
- src/grkr/workflow/handle_comment_codex.gleam
- src/grkr/supervisor/comment_handler_codex.gleam
- src/grkr/resolve_pr/codex.gleam
- test/grkr/coding_agent_test.gleam

## Acceptance
- [ ] Zero intentional behavior change (argv, env precedence, defaults, fail strings, grok-4.5 default)
- [ ] All prior public symbols still reachable via grkr/coding_agent
- [ ] Each new file ≤1000 LOC (target each <<200)
- [ ] coding_agent.gleam facade preferably <<120 LOC
- [ ] gleam build && gleam test green
- [ ] test/grkr/coding_agent_test.gleam green without import-path churn (or only facade import)
- [ ] Optional: test/grkr-coding-agent-swap.sh green
- [ ] README / docs/gleam-migration.md one-liner: slice 1 landed (if product PR)
- [ ] No shell bin/ changes unless accidental; no Linear mutate; no third backend; no checkpoint-json

## Non-goals
- No new agents / GRKR_AGENT_CMD
- No artifact path rename
- No doctor/validate split (slice 2)
- No rename of run_codex_* call-site APIs in comment/resolve modules
- No behavior change when GRKR_CODING_AGENT unset/codex

## Tests
gleam build
gleam test
# focused: test/grkr/coding_agent_test.gleam
# optional: test/grkr-coding-agent-swap.sh, test/grkr-smoke.sh

## Pattern refs
- src/grkr/progress/linear_mutation.gleam
- src/grkr/workflow/handle_comment.gleam
- docs/design-next-product-after-coding-agent-polish.md
- AGENTS.md (≤1000 LOC; small explicit changes)
```

### Slice 2 brief (short)

Split `doctor/validate.gleam` into tools/auth, coding-agent validation, config+remote+grkr-dir, and thin `validate.gleam` facade preserving `run_validate` / `run_create_config` / `validate_*` for `doctor/cli.gleam`. Zero behavior; `gleam test` + doctor path smoke.

---

## 6. Cross-links (docs-only)

| File | Edit |
|------|------|
| **Create** this file | Full design |
| `docs/gleam-migration.md` | Focused “Next product thinning” pointer here |
| `README.md` | One-liner next product thinning → this design |
| `docs/design-swappable-coding-agent.md` | Follow-up **4** → **DONE** @ b49a072 / #215 |
| `docs/design-coding-agent-polish.md` | Status: P0+P1 **landed** @ b49a072 / #215 |
| Spec | Prefer **no** `spec/parts/` churn |
| Checkpoint-json | **Do not reopen** |

---

## 7. Approach summary

1. **Board is empty of product gaps** against spec/39 core — hygiene/maintain design, not a feature map.
2. **Do not chase LOC under ~400** unless seams are as clear as prior facade splits — only coding_agent + doctor clear that bar with GitHub-first ROI.
3. **Leave shell alone** — GitHub/issue_shared facades are already the end state of the thinning program.
4. **Linear modules stay lower priority** unless a concrete Linear bug/ROI appears.
5. **Factory path:** land this design docs PR → spawn slice-1 implement card with paste-ready brief → Grok Build CLI implement → optional slice 2.

---

## 8. Verification

### This design PR (docs-only)

```bash
test -f docs/design-next-product-after-coding-agent-polish.md
rg -n "GO|NO-GO|DEFER" docs/design-next-product-after-coding-agent-polish.md
rg -n "design-next-product-after-coding-agent-polish" docs/gleam-migration.md README.md
rg -n "DONE|b49a072" docs/design-swappable-coding-agent.md docs/design-coding-agent-polish.md
git diff --stat origin/main
wc -l docs/design-next-product-after-coding-agent-polish.md docs/gleam-migration.md
```

### Slice 1 implement child

```bash
gleam build && gleam test
rg -n "pub fn (agent_name|run|classify_invocation|run_with_defaults)" src/grkr/coding_agent*.gleam
# optional: test/grkr-coding-agent-swap.sh
```

---

## Summary of verdicts

| # | Item | Verdict |
|---|------|---------|
| A | coding_agent concern split | **GO** (slice 1) |
| B | doctor/validate concern split | **GO** (slice 2) |
| C–D | refusal/supervisor/Linear Gleam | **DEFER** / **NO-GO** by priority |
| E–F | shell residual / facades | **NO-GO leave** |
| G–H | eval / deploy | **DEFER** / **NO-GO** |
| I | new spec/39 features | **NO-GO invent** |
| J | checkpoint-json / artifact / third backend | **NO-GO** / **DEFER** stand |

**Implement order:** slice 1 (`coding_agent`) then slice 2 (`doctor/validate`).
