# Design: Concern-split `bin/lib/issue_shared.sh` (concern siblings + thin facade)

**Status**: Design-only (plan agent). No product shell/Gleam body moves in this card.  
**Reference tip**: origin/main @ **c0d4d5d** (docs tip-sync #190 after product **6dc13ac** / PR #189 github stages-split slice 4 complete). Product tip **6dc13ac** / #189 (`github_issue.sh` facade source-only 71 LOC; stages-split complete).  
**Prior design artifacts**: `docs/design-github-issue-stages-split.md` (**primary structure mirror**), `docs/design-linear-issue-stages-split.md`, `docs/design-grkr-shared-helpers-extract.md` (how helpers landed in `issue_shared.sh`, PRs #136–#144), `docs/design-swappable-coding-agent.md` (coding-agent bridge contract #149/#150), `docs/design-github-issue-lib-thinning.md` (checkpoint-json optional/low-ROI stays separate).  
**Gap addressed**: After GitHub stages-split **complete** (slices 1–4 → research_plan/implement/test/publish; facade **71 LOC**) and Linear stages-split **complete** (cb6b1b5 / #177; facade ~88 LOC), the largest remaining **shared shell vertical** is `bin/lib/issue_shared.sh` (**387 LOC**). It grew with coding-agent bridge #149/#150 after shared-helpers extracts #136–#144. It is under the 1000 LOC hard limit but is the next high-value shell concern-split: thin facade at the stable path + focused concern siblings, **zero behavior change**.  
**Date**: 2026-07-21  
**Kanban**: t_696215fe  

---

## 1. Goal / non-goals

### Goal

Produce `docs/design-issue-shared-concern-split.md` so implementers can ship ordered PRs that:

- Concern-split `bin/lib/issue_shared.sh` into focused **concern siblings** (test-write, line-limit, coding-agent, progress, attach) plus a **thin facade** at the **stable path** `bin/lib/issue_shared.sh` (already sourced by `bin/grkr` **before** provider libs).
- Keep every file ≤1000 LOC; prefer siblings **≪300** (all clusters already ≪200 body LOC).
- Preserve external contracts: public function names, ambient call-time resolution, `GRKR_CODING_AGENT` / `GRKR_AGENT_*` matrix, log strings (`coding agent (<name>/<step>)`), exit codes, progress CLI bridge, line-limit remediation, attach-via-gh behavior.
- Do **not** dump provider-only stage bodies into shared siblings; do **not** move GitHub/Linear stage bodies.

### Non-goals

- No behavior change to user-facing flags, `--issue` / `--linear-issue` contracts, or mutation defaults.
- No mutate default flip (`GRKR_LINEAR_MUTATE` remains opt-in OFF).
- No provider stage body moves (`github_issue_stages_*`, `linear_issue_stages_*` untouched except optional header/comment mentions).
- No Hermes product edits beyond this design doc (+ optional short Next tip pointers).
- No public function renames — ambient bash resolution and tests depend on stable names.
- No new public flags or provider switches.
- `GRKR_ISSUE_PROVIDER` default remains **GitHub**.
- Do not dump provider-only code into shared.
- No pure Gleam rewrite of the coding-agent bridge in this workstream (optional later only if justified; not part of concern-split slices).
- No checkpoint-json pure Gleam extract (`design-github-issue-lib-thinning.md` optional/low-ROI stays separate).
- Design phase: docs only (+ optional Next pointer); **no** product shell body moves.

Preserve (per AGENTS + priors): thin shell conventions; ≤1000 LOC; `spec/parts/` canonical; shared neutral helpers stay shared; heavy exec/gh/worktree loops may stay shell.

---

## 2. Current state (cite files + tip)

### Re-measured LOC at tip c0d4d5d / product 6dc13ac

Verified by reading files at this tip (line counts match pre-measure; `issue_shared.sh` ends at L388 including trailing newline → **387** content lines as commonly counted).

| File | LOC | Role |
|------|-----|------|
| `bin/lib/issue_shared.sh` | **387** | Neutral shared bridges ← **this target** |
| `bin/lib/linear_issue.sh` | 329 | Thin Linear sequencer + load/meta; sources mutate + stages facade |
| `bin/grkr` | 198 | Thin launcher + GitHub `process_issue` sequencer |
| `bin/lib/task_progress.sh` | 176 | Shared progress.json |
| `bin/lib/linear_issue_stages_test.sh` | 176 | Linear test sibling |
| `bin/lib/linear_issue_stages_publish.sh` | 175 | Linear publish sibling |
| `bin/lib/github_issue_stages_implement.sh` | 173 | GitHub implement sibling |
| `bin/lib/github_issue_stages_test.sh` | 154 | GitHub test sibling |
| `bin/lib/github_issue_stages_publish.sh` | 152 | GitHub publish sibling |
| `bin/lib/linear_issue_stages_implement.sh` | 133 | Linear implement sibling |
| `bin/lib/linear_issue_stages_refusal.sh` | 131 | Linear refusal sibling |
| `bin/lib/refusal_paths.sh` | 125 | Shared refusal path helpers |
| `bin/lib/linear_issue_stages_research_plan.sh` | 125 | Linear research_plan sibling |
| `bin/lib/github_issue_stages_research_plan.sh` | 111 | GitHub research_plan sibling |
| `bin/lib/linear_issue_stages.sh` | 88 | Linear stages **facade source-only** (pattern reference) |
| `bin/lib/github_issue.sh` | 71 | GitHub stages **facade source-only** (pattern reference) |
| `bin/lib/linear_mutate.sh` | 62 | Guarded `maybe_apply_linear_mutation` only |

**Key Gleam near limits**: none near 1000. Largest under `src/` ~**440** (`progress/linear_mutation.gleam`). Other large modules already facaded (phases, progress/main, handle_comment, comment_handler, resolve_pr/main). Comfortable headroom everywhere for this shell-only workstream.

### Source chain (must preserve)

`bin/grkr` sources (order) — **do not change the single `issue_shared.sh` entry**:

1. `doctor.sh`, `grkr-project-status.sh`, `grkr-issue-workflow.sh`
2. `lib/refusal_paths.sh`, `lib/task_progress.sh`
3. **`lib/issue_shared.sh`** ← stable shared entry (becomes facade; still **before** providers)
4. **`lib/linear_issue.sh`** → mutate + stages facade (Linear only)
5. **`lib/github_issue.sh`** → GitHub stages facade
6. `grkr-task-slug.sh`; later `grkr-templates.sh` (after log setup)

Bash resolves functions at **call time**. Provider stages and tests only need all shared fns defined before dispatch (after full source of `issue_shared.sh` facade + siblings).

### What prior work already did

| Work | Tip / PR | Effect |
|------|----------|--------|
| Shared helpers extract | #136–#144 → **c801967** | Bridges moved from `bin/grkr` into one `issue_shared.sh`; grkr → 198 launcher |
| Swappable coding agent | **d55dd73** / #149 + **1edf636** / #150 | Bridge grew ~249→387; `GRKR_CODING_AGENT` + per-step overrides; log form `coding agent (<name>/<step>)` |
| Linear stages-split | #167–#177 → **cb6b1b5** | Facade + 5 siblings; **shell facade pattern** |
| GitHub stages-split | #180–#189 → **6dc13ac** | Facade + 4 siblings; stages-split **complete** |
| Docs tip-sync after #189 | **c0d4d5d** / #190 | Tips pin product 6dc13ac |

**Note on existing header “Slice 1–5” in `issue_shared.sh`:** those labels document the **historical extract-into-shared** order from `design-grkr-shared-helpers-extract.md` (test-write → line-limit → coding → progress → attach). They are **not** the concern-split ship order below. Implementers should rewrite the facade header to describe **concern-split** slices and sibling paths (mirror github/linear facade headers).

### Shared path flow (unchanged contract)

Both providers call shared bridges ambiently:

- **Test**: `build_command_list` → worktree exec → `write_test_checkpoint_with_header` (uses `checkpoint_marker`) → `cleanup_test_result_logs`
- **Decision/implement**: `run_codex_prompt` / alias `run_coding_agent_prompt`
- **Publish guard**: `ensure_publishable_file_sizes` (→ collect/check → optional `run_codex_prompt` remediate); GitHub publish also calls `check_file_line_limit` directly
- **Progress / markers**: `run_progress_cli`, `checkpoint_marker` (Linear mutations heavily; GitHub markers; tests stub `run_progress_cli`)
- **GitHub logs**: `attach_issue_logs` (finalize, refuse paths, `cleanup_on_exit` when flagged)

---

## 3. Inventory: every function in `issue_shared.sh`

Re-verified via full file read (387 LOC). Approx body LOC includes function-local comments immediately above the function where they document only that function.

| ~LOC | Function | ~lines | External callers | Ambient deps (call-time) | Notes |
|-----:|----------|--------|------------------|--------------------------|-------|
| 17 | `build_command_list` | 36–52 | github/linear `stages_test` | `BUILD_COMMAND`, `TEST_COMMAND` | Pure list; default `npm test` |
| 10 | `cleanup_test_result_logs` | 54–63 | github/linear `stages_test` | none beyond args | rm temp logs from results tsv |
| 67 | `write_test_checkpoint_with_header` | 65–131 | github via `write_test_checkpoint_file`; linear test direct | **`checkpoint_marker`** (progress cluster) | Header-param shared body writer |
| 12 | `collect_file_line_limit_violations` | 133–144 | internal (`check` / `ensure_publishable`) | `git_in_issue_context`, `MAX_FILE_LINES` | Staged ACMR files > limit |
| 13 | `check_file_line_limit` | 146–158 | github `stages_publish`; internal ensure | → collect | Prints ❌ lines; return violations |
| 31 | `ensure_publishable_file_sizes` | 160–190 | `process_issue` (`bin/grkr`); linear `stages_publish` | stage_*, git_in_*, **`run_codex_prompt`**, `write_line_limit_fix_prompt`, `CURRENT_ISSUE_WORKTREE` | Remediation loop then re-check |
| 21 | `_grkr_coding_agent_name` | 195–215 | internal | `GRKR_AGENT_*`, `GRKR_CODING_AGENT`, `CODING_AGENT` | Step override → global → codex |
| 9 | `_grkr_coding_step_from_phase` | 218–226 | internal | phase label substrings | decision / implement / remediate |
| 17 | `_grkr_run_codex_backend` | 230–246 | internal | `CODEX_BIN`, `CODEX_ARGS`, `CODEX_EXTRA_ARGS` | codex exec sandbox |
| 48 | `_grkr_run_grok_backend` | 249–296 | internal | `GROK_*`, `XAI_API_KEY`, `~/.hermes/.env` | Grok Build headless |
| 3 | `run_coding_agent_prompt` | 299–301 | alias; `grkr-coding-agent-swap.sh` | → `run_codex_prompt` | Stable preferred name |
| 43 | `run_codex_prompt` | 303–345 | github/linear implement stages; ensure_publishable; tests | backends, `persist_task_log_output` | Log: `coding agent ($agent/$step)` |
| 19 | `run_progress_cli` | 347–365 | many linear stages + mutate; github markers; tests stub | `SCRIPT_DIR`, `GRKR_GLEAM_PROJECT_ROOT`, gleam progress/cli | Marker fallback if no gleam.toml |
| 6 | `checkpoint_marker` | 367–372 | github research_plan; write_test_checkpoint_with_header; linear test | → `run_progress_cli marker` | Thin convenience |
| 15 | `attach_issue_logs` | 374–388 | github implement/finalize/refuse; `refusal_paths.sh`; `bin/grkr` cleanup_on_exit | `CURRENT_ISSUE`, `LOGFILE`, `gh` | Linear has **no** callers |

**Internal-only (still public bash names if sourced; do not rename):** `_grkr_coding_agent_name`, `_grkr_coding_step_from_phase`, `_grkr_run_codex_backend`, `_grkr_run_grok_backend`, `collect_file_line_limit_violations`.

**Cross-cluster ambient deps after split** (call-time; all siblings loaded by facade before dispatch):

- `write_test_checkpoint_with_header` → `checkpoint_marker` (**progress**)
- `ensure_publishable_file_sizes` → `run_codex_prompt` (**coding_agent**)
- `checkpoint_marker` → `run_progress_cli` (same module if kept together)

**Not in this file (stay put):**

- `process_issue` / launcher / trap → `bin/grkr`
- Provider stage bodies → `github_issue_stages_*` / `linear_issue_stages_*`
- `task_progress.sh`, `refusal_paths.sh` (except they **call** attach ambiently)
- Pure Gleam progress/cli, templates, workflow bridges already extracted

---

## 4. Target module map + ownership boundaries

### Recommended shape: thin facade + **five** concern modules

Mirror github/linear stages facades: stable entry path + fail-closed BASH_SOURCE-relative `.` of children.

| Path | Owns | Est. LOC after split |
|------|------|----------------------|
| `bin/lib/issue_shared.sh` | **Facade only** (after final slice): short header + ordered fail-closed `.` of children. **No function bodies.** **Stable path** already sourced by `bin/grkr` and by `test/grkr-coding-agent-swap.sh`. | ~45–70 |
| `bin/lib/issue_shared_test_write.sh` | `build_command_list`, `cleanup_test_result_logs`, `write_test_checkpoint_with_header` | ~100–120 |
| `bin/lib/issue_shared_line_limit.sh` | `collect_file_line_limit_violations`, `check_file_line_limit`, `ensure_publishable_file_sizes` | ~70–90 |
| `bin/lib/issue_shared_coding_agent.sh` | `_grkr_coding_*`, backends, `run_coding_agent_prompt`, `run_codex_prompt` | ~160–180 |
| `bin/lib/issue_shared_progress.sh` | `run_progress_cli`, `checkpoint_marker` | ~35–50 |
| `bin/lib/issue_shared_attach.sh` | `attach_issue_logs` | ~25–40 |

**Why five children (not fewer):**

- Matches natural concern seams already documented in the current header clusters.
- Each child stays well under 200 LOC → room for comments without approaching 1000.
- Independent shippable PRs with focused regression surfaces (`grkr-coding-agent-swap`, `grkr-line-limit`, `grkr-progress-cli`, smoke attach paths).
- Facade keeps **one** source path for `bin/grkr` and direct sourcers.

**Why keep attach separate (not fold into progress):**

- Different deps (`gh` + `CURRENT_ISSUE`/`LOGFILE` vs gleam progress CLI).
- GitHub-primary callers; progress is heavily Linear + marker.
- Fold is an acceptable alternative if implementers prefer one fewer file (~attach 15 LOC); document fold in PR if chosen. Default: **keep separate** for symmetry with five historical extract slices.

**Why facade is `issue_shared.sh` (not a new name):**

- `bin/grkr` already sources `lib/issue_shared.sh` only.
- `test/grkr-coding-agent-swap.sh` sources `$root/bin/lib/issue_shared.sh` directly.
- Extra hop would force grkr + tests to change without benefit (same rationale as GitHub facade path).

### Alternatives considered

| Alternative | Verdict |
|-------------|---------|
| Three modules: `{test_write, publish_guard+coding, progress+attach}` | Rejected: coding-agent deserves isolation (matrix tests, largest cluster); weaker PR isolation |
| Fold attach into progress | Acceptable fallback if file count bothers; default keep separate |
| `bin/grkr` sources each sibling | Rejected: facade keeps one stable path (matches github/linear) |
| Dump any provider stage into shared siblings | **Forbidden** |
| Pure Gleam coding-agent rewrite in this work | **Out of scope** (optional later card if ever) |

### Source order inside the facade

```text
# issue_shared.sh (facade) — bin/grkr sources this BEFORE linear_issue + github_issue
. ".../issue_shared_coding_agent.sh"  # ensure_publishable calls run_codex_prompt
. ".../issue_shared_progress.sh"      # write_test_checkpoint calls checkpoint_marker
. ".../issue_shared_test_write.sh"    # uses checkpoint_marker ambiently
. ".../issue_shared_line_limit.sh"    # uses run_codex_prompt ambiently
. ".../issue_shared_attach.sh"        # independent; CURRENT_ISSUE/LOGFILE at call time
```

- Prefer **dependency-before-depender for readability**: coding_agent before line_limit; progress before test_write.
- **Call-time resolution**: any order works if **all** siblings are sourced before dispatch / before tests call shared fns.
- Still fail-closed if a sibling is missing (mirror github/linear facades):

```bash
CANDIDATE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/issue_shared_….sh"
if [ -f "$CANDIDATE" ]; then . "$CANDIDATE"
else echo "❌ missing issue_shared … module: $CANDIDATE" >&2; return 1 2>/dev/null || exit 1
fi
```

### Ownership boundaries

| Surface | Rule |
|---------|------|
| `bin/grkr` | Thin launcher + `process_issue`; **still one** `source …/issue_shared.sh`; do not re-absorb shared bodies |
| `issue_shared.sh` | Facade only after final slice |
| `issue_shared_*.sh` | Provider-agnostic shared bridges only |
| `github_issue*` / `linear_*` | **No** shared body moves into provider files; no provider stage dump into shared |
| `refusal_paths.sh` / `task_progress.sh` | Unchanged call sites (attach / progress names stable) |

### Stable public API (do not rename)

All of: `build_command_list`, `cleanup_test_result_logs`, `write_test_checkpoint_with_header`, `collect_file_line_limit_violations`, `check_file_line_limit`, `ensure_publishable_file_sizes`, `_grkr_coding_agent_name`, `_grkr_coding_step_from_phase`, `_grkr_run_codex_backend`, `_grkr_run_grok_backend`, `run_coding_agent_prompt`, `run_codex_prompt`, `run_progress_cli`, `checkpoint_marker`, `attach_issue_logs`.

Call sites stay byte-identical in meaning (args, exit codes, globals, log strings).

### Coding-agent contract (do not change)

Per `docs/design-swappable-coding-agent.md` + #149/#150:

| Item | Value |
|------|--------|
| Selector | `GRKR_CODING_AGENT=codex\|grok` (alias `CODING_AGENT`) |
| Per-step | `GRKR_AGENT_DECISION` / `IMPLEMENT` / `REMEDIATE` (+ legacy `GRKR_CODING_AGENT_*`) |
| Default | `codex` |
| Bridge | `run_codex_prompt` = `run_coding_agent_prompt` |
| Log form | `coding agent (<name>/<step>)` — tests grep this after #150 |

### test-copy / fixture packaging

`test/test-copy-grkr-lib.sh` already:

```bash
cp "$repo_root/bin/lib/"*.sh "$dest/lib/"
```

New `issue_shared_*.sh` siblings are **auto-copied**. Still:

- Document packaging in design + first implement header/comment (like github/linear).
- Fail-closed facade if sibling missing (do not silently omit functions).
- Optional: one-line comment in `test-copy-grkr-lib.sh` noting `issue_shared_*.sh` siblings (github/linear notes already present).

Direct sourcer: `test/grkr-coding-agent-swap.sh` uses repo `bin/lib/issue_shared.sh` — facade must pull siblings from the same directory via `BASH_SOURCE`.

---

## 5. Ordered shippable slice table (smallest first)

Each product slice acceptance:

- Files ≤1000 LOC; siblings prefer ≪300  
- `bash -n` on every touched `.sh`  
- `gleam build` + `gleam test` green  
- GitHub + Linear regression surfaces green when shared touched (see §6)  
- Zero intentional behavior change; no new flags; no mutate default flip  
- README + `docs/gleam-migration.md` thin Next note on functional slices  
- Empty/trivial diff on provider stage **bodies**; `bin/grkr` source line stays single `issue_shared.sh`  
- Public names + `GRKR_CODING_AGENT` matrix unchanged; log greps still match  

| # | Title | Primary files | What moves | Acceptance highlight | Est. LOC delta |
|---|-------|---------------|------------|----------------------|----------------|
| **0** | Design only (this doc) | `docs/design-issue-shared-concern-split.md` + optional Next pointer | none | Design complete; no product | +doc only |
| **1** | **First implement**: attach extract + introduce facade sourcing | facade begins + new `issue_shared_attach.sh` | Exact move: `attach_issue_logs`; facade sources attach; other bodies remain in facade | smoke + refusal + impl-to-refusal attach paths; `attach_issue_logs` still resolves from grkr | facade −~15 body + source block; attach ~25–40 |
| **2** | progress → `issue_shared_progress.sh` | facade + new progress module | Exact move `run_progress_cli` + `checkpoint_marker` | progress-cli + Linear refuse/apply stubs + checkpoint markers | −~25 body |
| **3** | line-limit → `issue_shared_line_limit.sh` | facade + new line_limit module | Exact move collect + check + ensure_publishable | grkr-line-limit + Linear publish path + process_issue step 6 | −~56 body |
| **4** | test-write → `issue_shared_test_write.sh` | facade + new test_write module | Exact move build_command_list + cleanup + write_test_checkpoint_with_header | smoke + checkpoint-resume + Linear test paths | −~94 body |
| **5** | coding-agent → `issue_shared_coding_agent.sh`; facade source-only | facade + new coding_agent module | Exact move all `_grkr_coding_*`, backends, alias, `run_codex_prompt`; **no bodies left in facade** | coding-agent-swap + smoke decision/implement greps + line-limit remediate log | facade ~45–70; coding_agent ~160–180 |
| **6** (optional) | Header/docs “issue_shared concern-split complete” | docs | No logic | Tip pins accurate | docs only |

### Why attach first (not coding-agent or test-write)

1. **Smallest complete vertical** (~15 LOC body) that still proves multi-file facade + fail-closed source.  
2. Dedicated GitHub coverage via smoke / refusal / impl-to-refusal / cleanup attach paths without touching coding-agent matrix or line-limit remediation.  
3. Establishes pattern before larger clusters (test-write ~94, coding-agent ~154).  
4. Lowest blast radius for packaging mistakes (missing sibling → fail-closed message).  
5. Mirrors Linear “smallest high-signal first” and GitHub research_plan-first philosophy.

**Acceptable swaps** (same end state; must still introduce facade + fail-closed in whichever lands first):

- **line_limit first** if implementer wants a dedicated `grkr-line-limit.sh` signal immediately.  
- **progress+attach in one PR** (two siblings or folded) if attach alone feels too thin for CI cost.  
- Do **not** start with coding-agent (~154, highest complexity / env matrix) until facade packaging is proven.

### LOC risk rules

- Block any slice leaving a single `issue_shared*` file >~900 without further split.  
- Do **not** add provider stage code to shared siblings.  
- Do **not** fatten `bin/grkr` or provider facades.  
- Coding-agent pure Gleam rewrite remains **out of scope**.  
- Siblings target ≪300 (coding_agent largest ~180).

### Safe move pattern (every product slice) — mirror github/linear

1. New sibling with **exact** function body + local comments (no refactors).  
2. Facade sources sibling; **remove** definition from old home (**no** thin wrapper left).  
3. Update headers (concern-split slice N, ambient deps, remaining bodies list).  
4. `bash -n` + full shared regression (§6) + gleam + npm.  
5. README + gleam-migration thin note.

---

## 6. Regression surface

### Build

- `gleam build` + `gleam test`  
- `bash -n` on all touched shells  

### Cross-cutting (prefer every product slice)

- `npm test` (includes coding-agent-swap + worker/robot suite)

### GitHub (must stay green when shared touched)

- `test/grkr-smoke.sh`  
- `test/grkr-checkpoint-resume.sh`  
- `test/grkr-refusal.sh`  
- `test/grkr-implementation-to-refusal.sh`  
- `test/grkr-line-limit.sh`  
- `test/grkr-pr-body-limit.sh`  
- `test/grkr-progress-cli.sh`  
- `test/grkr-coding-agent-swap.sh` (**direct** `issue_shared.sh` sourcer)  
- `test/grkr-dirty-worktree-warning.sh`, `grkr-branch-exists.sh`, `grkr-init.sh`, `grkr-installed-layout.sh`  

### Linear (must stay green when shared touched)

- `test/grkr-linear-issue-implement.sh`  
- `test/grkr-linear-issue-mvp.sh`  
- `test/grkr-linear-refuse-progress.sh` (stubs `run_progress_cli` after sourcing chain)  
- `test/grkr-linear-apply-matrix.sh`  

### Log-string greps (post #150 — do not break)

Tests assert the form **`coding agent (<name>/<step>)`**, e.g.:

- `🚀 Running coding agent (codex/decision) to decide whether to implement the issue...`
- `🚀 Running coding agent (codex/implement) to implement the issue...`
- `✅ coding agent (codex/implement) finished implement the issue.`
- `✅ coding agent (codex/remediate) finished remediate file line-limit violations.`

Exact body move of `run_codex_prompt` preserves these. Any drive-by edit to log format is a **regression**.

Behavioral invariants: identical logs, gh calls, artifacts, progress.json, mutation dumps, exit codes, worktree cleanup; `GRKR_CODING_AGENT` / `GRKR_AGENT_*` matrix unchanged.

---

## 7. Spec + AGENTS citations

| Ref | Why |
|-----|-----|
| `AGENTS.md` | ≤1000 LOC; thin `bin/`; README on functional change; `spec/parts/` canonical; shell conventions |
| `spec/parts/02-core-requirements.md` | Coding agent bridge location |
| `spec/parts/05-configuration.md` | `GRKR_CODING_AGENT` / CODEX_ARGS / Grok config |
| `spec/parts/17-issue-workflow-overview.md` | E2E issue workflow |
| `spec/parts/22` | Decision gate (uses `run_codex_prompt`) |
| `spec/parts/25` | Implement |
| `spec/parts/26` / `31` | Test checkpoint (test-write cluster) |
| `spec/parts/38` | Acceptance (if useful) |
| `spec/parts/39` | Order / status notes |
| Prior designs in header | Pattern + coding-agent contract + non-goals continuity |

No spec content change required for pure shell LOC split. If `spec/parts/` tips are touched later, Hermes runs `scripts/sync-spec.sh`.

---

## 8. Recommended first implement slice + rationale

**First product slice**: Extract `attach_issue_logs` into `bin/lib/issue_shared_attach.sh` and convert `issue_shared.sh` into a **facade that sources the attach module** while temporarily retaining other function bodies in the facade file.

**Rationale**: smallest high-signal vertical; proves facade + fail-closed multi-file packaging; strong GitHub attach coverage; lowest blast radius vs coding-agent matrix / line-limit remediation / test checkpoint formatting; sets pattern for slices 2–5.

See §10 for paste-ready card brief.

---

## 9. Follow-up implement card titles (do not implement here)

1. `implement: issue_shared attach extract + facade (slice 1)` — **first**  
2. `implement: issue_shared progress → issue_shared_progress.sh (slice 2)`  
3. `implement: issue_shared line-limit → issue_shared_line_limit.sh (slice 3)`  
4. `implement: issue_shared test-write → issue_shared_test_write.sh (slice 4)`  
5. `implement: issue_shared coding-agent → issue_shared_coding_agent.sh; facade source-only (slice 5)`  
6. `docs: tip-sync after issue_shared concern-split complete` (if high-level tips lag)  
7. *(separate, optional, non-goal here)* pure Gleam coding-agent bridge if ever justified  
8. *(separate, optional)* checkpoint-json pure extract per `design-github-issue-lib-thinning.md`  

Factory may spawn slice 1 as child of this design card after land.

---

## 10. Paste-ready first implement card brief with `/goal`

```
/goal Extract attach_issue_logs from bin/lib/issue_shared.sh into bin/lib/issue_shared_attach.sh and make issue_shared.sh a thin facade that sources the attach module (while other shared bodies remain in the facade until later slices). Zero behavior change. Stable function names. bin/grkr still sources only issue_shared.sh (before provider libs). No public renames. No new flags. No GRKR_CODING_AGENT / mutate default changes. Provider stage bodies untouched. No Gleam rewrite.

Context: tip c0d4d5d (docs #190) / product tip 6dc13ac #189 GitHub stages-split complete. issue_shared.sh 387 LOC largest remaining shared shell vertical after shared-helpers #136–#144 + coding-agent #149/#150 + github/linear stages-splits complete. Design: docs/design-issue-shared-concern-split.md (this card parent). Pattern: exact body move like github/linear stages-split facades (fail-closed BASH_SOURCE source).

Read (must):
- AGENTS.md
- docs/design-issue-shared-concern-split.md (§4–§6, §10)
- docs/design-github-issue-stages-split.md (facade pattern reference)
- docs/design-linear-issue-stages-split.md (facade pattern reference)
- docs/design-grkr-shared-helpers-extract.md (how attach landed)
- docs/design-swappable-coding-agent.md (do not change coding-agent contract this slice)
- bin/lib/issue_shared.sh (attach_issue_logs ~L374–388 + header)
- bin/grkr (source order: issue_shared before linear/github; cleanup_on_exit attach call)
- bin/lib/refusal_paths.sh + github_issue_stages_implement.sh (attach callers)
- bin/lib/github_issue.sh or linear_issue_stages.sh (fail-closed source pattern)
- test/test-copy-grkr-lib.sh (already cp bin/lib/*.sh — siblings auto-copied; optional comment)
- test/grkr-smoke.sh, grkr-refusal.sh, grkr-implementation-to-refusal.sh
- spec/parts/02,05,17,39 as needed

Implement (Grok Build --mode implement or full, --model grok-4.5):
1. Add bin/lib/issue_shared_attach.sh with exact attach_issue_logs body + comment block (CURRENT_ISSUE/LOGFILE/gh ambient).
2. At top of issue_shared.sh (after rewritten concern-split header), source attach sibling via BASH_SOURCE-relative path with fail-closed missing message (mirror github_issue.sh / linear_issue_stages.sh); remove in-file definition (no wrappers).
3. Update issue_shared.sh header: facade begins; document concern-split slice 1; list remaining bodies still in file; clarify old "Slice 1–5" extract labels are historical.
4. Do not rename functions; do not touch provider stage bodies; no new flags; bin/grkr still one source line for issue_shared.
5. Optional: one-line test-copy comment noting issue_shared_*.sh (glob already covers).

Verify:
- bash -n bin/lib/issue_shared*.sh
- bash test/grkr-smoke.sh
- bash test/grkr-refusal.sh
- bash test/grkr-implementation-to-refusal.sh
- bash test/grkr-coding-agent-swap.sh
- bash test/grkr-line-limit.sh
- bash test/grkr-progress-cli.sh
- bash test/grkr-linear-refuse-progress.sh
- bash test/grkr-linear-issue-mvp.sh
- gleam build && gleam test
- npm test (or full GitHub + Linear suites above)
- git diff --stat: empty or trivial on github_issue_stages_* / linear_issue_stages_* bodies; bin/grkr still sources only issue_shared.sh

Acceptance:
- All files ≤1000 LOC; attach sibling ≪100
- attach_issue_logs still resolves from grkr / refusal_paths / github finalize paths via facade
- Identical gh issue comment log attachment behavior
- README + docs/gleam-migration.md thin note (Next product thinning → issue_shared concern-split slice 1 landed)

Non-goals: no progress/line-limit/test-write/coding-agent extracts yet; no Gleam rewrite; no coding-agent matrix behavior change; no Linear mutate default change; no provider stage moves.
```

Suggested Grok Build CLI invocation for implementers:

```bash
~/.hermes/scripts/grok_build_exec.sh \
  --cwd <worktree> \
  --prompt-file /tmp/grkr-grok-prompt.txt \
  --mode implement \
  --model grok-4.5 \
  --max-turns 60 \
  --log /tmp/grkr-grok-last.log
```

---

## 11. Risks and mitigations

| Risk | Mitigation |
|------|------------|
| Missing sibling → mysterious “command not found” | Fail-closed facade source (github/linear pattern); test-copy already globs `*.sh` |
| Cross-module ambient deps (test_write→marker, ensure_publishable→codex) | All siblings sourced before dispatch; document dependency-before-depender order in facade header |
| Accidental behavior edit during move | Exact body move only; no drive-by refactors; diff = pure relocation |
| Coding-agent log string drift | Do not edit `run_codex_prompt` log lines; slice 5 is exact move; greps in smoke/refusal/line-limit/swap |
| Direct sourcer `grkr-coding-agent-swap.sh` misses siblings | Facade uses `BASH_SOURCE` dirname next to facade; swap test sources facade path |
| Tests that redefine `run_progress_cli` after source | Call-time override still works if definition happens after full facade source (unchanged pattern) |
| Header comment drift / confusion with historical extract “Slice 1–5” | Rewrite facade header for concern-split; children carry local ambient docs |
| Temptation to “also” rewrite coding agent in Gleam | Explicit non-goal; separate card if ever |
| Parallel workers editing monolith | Detached worktree from origin/main; small slices |

---

## 12. Non-goals (restated)

- **No behavior change** — logs, artifacts, exit codes, gh/Linear side effects identical.  
- **No mutate default flip**; GitHub remains default provider.  
- **No provider stage body moves**; no dump of provider-only code into shared.  
- **No public renames**; no new flags.  
- **No Hermes product shell/Gleam implementation** in the design card.  
- **No pure Gleam coding-agent bridge** in this workstream.  
- **No checkpoint-json Gleam extract** here.  
- **`bin/grkr` source order unchanged** — still exactly one `source …/lib/issue_shared.sh` before providers.

---

## 13. Done criteria for this design card

- [x] Goal / non-goals (zero behavior; GitHub default; no renames; no provider dumps; no Gleam coding rewrite; no new flags)  
- [x] Current state LOC + tip c0d4d5d / product 6dc13ac + source chain + prior work  
- [x] Full function inventory + callers + ambient notes  
- [x] Target module map (facade + five concern modules) + alternatives + source order  
- [x] Ordered slice table (smallest first; slice 1 ≤~150 LOC move) + acceptance + LOC rules + safe move pattern  
- [x] Regression surface (incl. coding-agent log greps)  
- [x] Spec + AGENTS citations  
- [x] Recommended first implement + rationale  
- [x] Follow-up card titles  
- [x] Paste-ready first implement brief with `/goal` + Grok Build CLI hint  
- [x] Risks/mitigations + non-goals restated  
- [ ] Product implementation — **out of scope** (child cards)  
- [ ] Optional: one-line Next pointer in README and/or `docs/gleam-migration.md` (docs-only; prefer design doc alone if tip pins are huge)

---

## 14. Next step

Kanban: land this design PR → spawn **implement: issue_shared attach extract + facade (slice 1)** with parent = design task, detached worktree from new `origin/main`, Grok Build `--mode implement` / `--model grok-4.5`, verify GitHub+Linear suites + gleam + npm, then continue slices 2–5 until facade is source-only.

---

## Context summary

| Item | Value |
|------|--------|
| Target | `bin/lib/issue_shared.sh` **387 LOC**, 15 fns (+ 4 `_grkr_*` internals) |
| Pattern | github stages-split complete @ **6dc13ac** / #189; linear @ **cb6b1b5** / #177 |
| Facade path | **`issue_shared.sh` itself** (grkr + coding-agent-swap already source it) |
| Siblings | 5 (`attach`, `progress`, `line_limit`, `test_write`, `coding_agent`) |
| First implement | attach cluster + facade source |
| bin/grkr invariant | still one `source …/issue_shared.sh` **before** providers |
| Non-goal | coding-agent Gleam rewrite; provider stage moves; renames; new flags |

**Design-only — no product shell or Gleam code was edited.**
