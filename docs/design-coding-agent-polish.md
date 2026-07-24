# Design: Coding-agent polish follow-ups

**Status**: Design — P0+P1 **landed** @ **b49a072** / PR #215 (t_49452ed3)  
**Date**: 2026-07-23  
**Base tip**: origin/main **2e32cbe** (docs tip-sync #213 after product **c55f8e1** / #212)  
**Kanban**: t_df8f9141  
**Design agent**: Grok Build CLI `model=grok-4.5` (`--mode design` / agent `plan`)

**Parents:**  
[`docs/design-swappable-coding-agent.md`](design-swappable-coding-agent.md) · [`docs/design-gleam-coding-agent-swap.md`](design-gleam-coding-agent-swap.md)

---

## Context

| Fact | Evidence |
|------|----------|
| Base tip | origin/main docs tip-sync **2e32cbe** (#213) after product **c55f8e1** / #212 |
| Gleam swap DONE | Slice 1 comment classify **4553356** / #210; slice 2 resolve_pr **c55f8e1** / #212; design **a87f379** / #207 |
| Shell bridge FINAL | concern-split **851bed2** / #203 → `issue_shared_coding_agent.sh` |
| Checkpoint-json | **NO-GO** stands (**caef425** / #206) — do not reopen |
| Parent open items | `docs/design-swappable-coding-agent.md` §Follow-ups **2–3** + optional GROK_MODEL align from gleam-swap design slice 4 |

---

## Executive verdict table

| Item | Verdict | Rationale | Risk | Slice if GO |
|------|---------|-----------|------|-------------|
| 1. Artifact path `codex/…` → `agent/…` | **NO-GO** (leave forever) | Cosmetic only; stable entrypoint is already `implementation.log`. Hard cutover breaks resume: `is_sharded` / `emit_task_log_stream` only look at `parts_dir` → `…/codex/….parts`. Dual-read/dual-write is high cost for no functional gain. Spec 04/18/25 + attach/PR text + tests pin path. | High if forced (resume data loss / empty append) | — |
| 2. `GROK_MODEL` default → `grok-4.5` | **GO** | Product policy prefers grok-4.5 (AGENTS.md / Hermes runs); shell + Gleam + doctor template + tests still default `grok-build`. Flip **both** layers together; keep override. | Med (SKU/auth, live matrix, ops relying on grok-build) | **P1** small product slice |
| 3. Third backend / `GRKR_AGENT_CMD` | **DEFER** | No caller need; unknown agent already fails closed (`return 2` / `Error("claude")`). Argv template = quoting, doctor probe, eval matrix explosion, unknown CLI flags. Revisit only with a concrete consumer. | High maintenance if premature | — |
| 4. Doctor config template `GRKR_AGENT_COMMENT` / `RESOLVE` | **GO** | Spec/05 + README already document keys; `config_parse.default_config_template` still omits them (only DECISION/IMPLEMENT/REMEDIATE). Zero runtime behavior. | None | **P0** tiny config/docs |
| 5. Hardcoded Codex inventory | **Scan only** (no rename GO) | Stable public names (`run_codex_prompt`, `run_codex_classify`, `select_codex_*`, module `*_codex.gleam`) are intentional. Cosmetic renames are churn without contract value. | N/A | inventory in design only |

---

## Item deep-dives

### 1. Artifact path rename — **NO-GO**

**Live call sites (verified):**

| Site | Role |
|------|------|
| `src/grkr/workflow/task_log_core.gleam` L14–16, L82 | `parts_dir` → `dirname/codex/basename.parts`; manifest bullets `codex/…` |
| `src/grkr/workflow/task_log_persist.gleam` | Append uses `is_sharded` → only new `parts_dir`; wipe/rewrite parts under that path |
| `src/grkr/progress/templates.gleam` L121 | Implement prompt text embeds `/codex/implementation.log.parts/` |
| `bin/lib/github_issue_stages_implement.sh` L132–133 | `$TASK_DIR/codex/implementation-before-refusal.log` |
| `bin/lib/linear_issue_stages_implement.sh` L107–108 | same |
| Tests | `task_log_test.gleam`, `grkr-line-limit.sh`, `grkr-implementation-to-refusal.sh` |
| Spec | `04-repository-layout.md`, `18-…`, `25-stage-4-implement.md` |
| README | user-facing shards path |

**Resume / idempotency:**  
On append, `task_log_persist` does `is_sharded(target)` which requires `parts_dir` + `part-0000`. After a hard rename to `agent/`, an in-flight task whose parts live under `codex/` is treated as **not sharded**. Emit returns empty/manifest-only content; append can **drop** prior transcript. Dual-write without dual-read is worse (two trees). Dual-read forever means permanent complexity for a directory name.

**Attach / PR body:**  
PR body uses `emit_task_log_stream(implementation.log)` (logical path), not the parts dirname string—so functional PR body is OK if emit keeps working. User-visible completion/docs text and on-disk tree still say `codex/`. Refusal sidecar is a separate hardcoded path.

**Cutover options rejected:**

| Option | Why not |
|--------|---------|
| Hard cutover | Breaks resume on existing task dirs |
| Dual-write + dual-read | Ongoing branch complexity; tests ×2; low ROI |
| Leave forever | **Chosen** — `implementation.log` is the stable API; `codex/` is historical artifact namespace, not the backend selector |

**Revisit only if:** multi-backend concurrent artifact isolation is required (unlikely; one implement log per task).

---

### 2. `GROK_MODEL` default — **GO** → `grok-4.5`

**Parity today (must stay paired):**

| Layer | Default |
|-------|---------|
| `bin/lib/issue_shared_coding_agent.sh` L104 | `${GROK_MODEL:-grok-build}` |
| `src/grkr/coding_agent.gleam` L188–189 | empty → `"grok-build"` |
| Doctor template | `# GROK_MODEL="grok-build"` |
| `spec/parts/05-configuration.md` | commented `grok-build` |
| README coding-agent block | `GROK_MODEL=grok-build` |
| `test/grkr/coding_agent_test.gleam` | pins `grok-build` in argv when env set; default-empty path should assert new default |

**Policy:** Hermes/Stepan product Grok CLI runs prefer **grok-4.5** (AGENTS.md `--model grok-4.5`). Defaults should match intended product SKU; operators who need the old SKU set `GROK_MODEL=grok-build`.

**Why not “keep grok-build + note”:** Silent mismatch between automation policy and code default causes surprise live runs and doc drift. Explicit default flip is one small slice.

**Risks / mitigations:**

- Live eval matrix / CI cells: may need `GROK_MODEL=grok-build` pin if 4.5 unavailable in that env
- Cost/latency: operator override
- Document in README: default is grok-4.5; override for SKU pin

**Must change together:** shell + Gleam + doctor template + spec/05 comment + README + coding_agent tests. No half-flip.

---

### 3. Third backend / `GRKR_AGENT_CMD` — **DEFER**

**Today:** selector is only `codex|grok`. Unknown → shell `return 2` with “supported: codex, grok”; Gleam tests already cover `claude` → Error.

**Why not GO now:**

- No production consumer or doctor probe design
- Thin argv template looks small but needs: placeholder grammar (`%p` prompt, `%w` cwd), shell vs exec array safety, env injection, fail strings, matrix cells × N, per-step overrides
- Doctor “validates only selected agent” becomes open-ended
- Flag drift across CLIs is unbounded

**Revisit when:** a named third agent is required with known headless argv and auth, **or** a single well-specified `GRKR_AGENT_CMD` template with integration tests and doctor “binary exists only” policy.

---

### 4. Doctor / config template — **GO**

**Gap:** `src/grkr/doctor/config_parse.gleam` `default_config_template` documents:

```text
# GRKR_AGENT_DECISION / IMPLEMENT / REMEDIATE
```

Missing (already in `spec/parts/05-configuration.md` and README):

```text
# GRKR_AGENT_COMMENT="codex"   # Gleam comment-classify
# GRKR_AGENT_RESOLVE="grok"    # Gleam resolve_pr
```

Optional: refresh comment that Gleam comment+resolve honor global agent (spec already says this).  
Doctor validate stays **global-only** (no change)—same as shell.

Also touch on P1 or same PR as P0: template `GROK_MODEL` comment when flipping default.

---

### 5. Remaining hardcoded Codex inventory (scan only)

#### Behavior-critical paths / strings (do **not** rename without dedicated GO)

| Location | Kind | Notes |
|----------|------|-------|
| `task_log_core.parts_dir` → `…/codex/….parts` | **path contract** | NO-GO rename |
| Manifest `# Sharded Codex Output` + `codex/…` bullets | **on-disk text** | Cosmetically “Codex”; leave with path |
| `$TASK_DIR/codex/implementation-before-refusal.log` | **path contract** | leave |
| Implement prompt path text in `templates.gleam` | user-facing path | leave with path |
| Log `coding agent (codex/decision)` | **behavior** when agent=codex | agent name in log is dynamic; “codex” when selected is correct |
| Doctor `validate_codex` / default agent `codex` | **behavior** | default backend remains codex |

#### Stable public APIs / module names (**intentional**; cosmetic rename NO-GO)

| Symbol | Why keep |
|--------|----------|
| `run_codex_prompt` (+ alias `run_coding_agent_prompt`) | Shell contract; many call sites; parent design stable name |
| `run_codex_classify` / `parse_codex_output` | Public Gleam API; optional alias already allowed |
| `resolve_pr/codex.gleam`, `handle_comment_codex.gleam`, `comment_handler_codex.gleam` | Module path churn; behavior already agent-aware via `coding_agent` |
| `resolve_with_codex`, types `CodexResolution` | Internal; rename optional later, not polish ROI |
| `select_codex_heading_section` / CLI `select-codex-pr-section` / `extract_codex_pr_body` / `extract_linear_codex_pr_body` | Progress/publish contract |
| `_grkr_run_codex_backend` | Internal shell backend name |

#### Cosmetic comments / logs (optional drive-bys only if touching file anyway)

| Location | Note |
|----------|------|
| Comments “codex impl outputs”, “Thin shell orchestrates codex” | Docs-only clarity; no slice |
| `task_log_cli` help “codex outputs” | optional |
| Variable names `codex_output_file`, `codex_out` | leave |

**Inventory conclusion:** After Gleam swap #210/#212, **no remaining hardcoded Codex *exec*** outside the codex backend itself. Remaining “codex” is path history + stable API names. Do not schedule renames.

---

## Slice plan (GO items only)

### Slice P0 — Doctor/config template comments (tiny)

**Acceptance:**

- [ ] `default_config_template` includes commented `GRKR_AGENT_COMMENT` and `GRKR_AGENT_RESOLVE` (mirror README/spec/05)
- [ ] Optional one-line comment: Gleam comment-classify + resolve_pr honor these / global
- [ ] No doctor validation change
- [ ] `gleam build` / existing doctor tests green
- [ ] If only this lands without P1: leave `GROK_MODEL="grok-build"` comment until P1

**Files:**  
`src/grkr/doctor/config_parse.gleam`  
optional: `spec/parts/05-configuration.md` (already has keys—only if wording stale for resolve “reserved”)  
optional: `test/grkr/doctor/config_parse_test.gleam` if template is asserted

**Tests:** `gleam test` (doctor/config_parse if present); no npm required

---

### Slice P1 — `GROK_MODEL` default `grok-4.5` (shell + Gleam together)

**Acceptance:**

- [ ] Shell default `${GROK_MODEL:-grok-4.5}`
- [ ] Gleam empty env → `"grok-4.5"`
- [ ] Doctor template + README + spec/05 comment show `grok-4.5`
- [ ] Unit tests: default model in argv is `grok-4.5`; explicit `GROK_MODEL=grok-build` still works
- [ ] Override docs one-liner: operators may pin `GROK_MODEL=grok-build`
- [ ] `gleam test` + `test/grkr-coding-agent-swap.sh` green (default agent still codex; grok path only if exercised)
- [ ] No change to `GRKR_CODING_AGENT` default (`codex`)

**Files:**

- `bin/lib/issue_shared_coding_agent.sh`
- `src/grkr/coding_agent.gleam`
- `src/grkr/doctor/config_parse.gleam` (if not done in P0, or update model comment)
- `test/grkr/coding_agent_test.gleam`
- `README.md` (coding-agent block)
- `spec/parts/05-configuration.md` + `bash scripts/sync-spec.sh`
- Parent designs: mark optional slice 4 done when landed

**Tests:**  
`gleam test`; focused coding_agent tests; optional mock matrix still green (mocks don’t care model)

**Order:** Prefer **P0 then P1**, or **single PR P0+P1** if small enough (recommended: one product PR combining P0+P1).

---

## Non-goals / out of scope

- Artifact dir rename or dual-write
- Third backend / `GRKR_AGENT_CMD` / claude
- Renaming stable `run_codex_*` APIs or `*_codex.gleam` modules
- Checkpoint-json Gleam helpers (NO-GO **caef425**)
- Changing default **agent** from codex to grok
- Linear live-mutate, prompt content per backend
- Product behavior in **this design PR** (docs + cross-links only)

---

## Verify recipe

### This design PR (docs-only)

```bash
test -f docs/design-coding-agent-polish.md
rg -n "GO|NO-GO|DEFER" docs/design-coding-agent-polish.md
rg -n "design-coding-agent-polish" docs/design-swappable-coding-agent.md docs/design-gleam-coding-agent-swap.md
git diff --stat origin/main
wc -l docs/design-coding-agent-polish.md
```

### Implement children

**P0:**

```bash
gleam build && gleam test
rg -n "GRKR_AGENT_COMMENT|GRKR_AGENT_RESOLVE" src/grkr/doctor/config_parse.gleam
```

**P1:**

```bash
rg -n 'GROK_MODEL:-grok-4\.5|\"grok-4\.5\"' bin/lib/issue_shared_coding_agent.sh src/grkr/coding_agent.gleam
gleam test
test/grkr-coding-agent-swap.sh
# optional: bash scripts/sync-spec.sh after spec/05
```

---

## Acceptance for this design card

- [x] `docs/design-coding-agent-polish.md` with verdict table + slice plan for GO only
- [x] Cross-links from parent designs
- [x] Thin Next note if useful
- [x] No product code; no file >1000 LOC
- [x] Commit on design branch; ready for Hermes PR

---

## Summary of verdicts

| # | Item | Verdict |
|---|------|---------|
| 1 | `codex/` → `agent/` path rename | **NO-GO** leave forever |
| 2 | `GROK_MODEL` default | **GO** → `grok-4.5` (shell+Gleam) |
| 3 | Third backend | **DEFER** |
| 4 | Doctor COMMENT/RESOLVE template | **GO** (P0) |
| 5 | Codex inventory | scan only; no renames |

**Implement order:** single product PR **P0+P1** preferred (tiny).

**Landed:** P0+P1 @ **b49a072** / PR #215. Next: [`design-next-product-after-coding-agent-polish.md`](design-next-product-after-coding-agent-polish.md).
