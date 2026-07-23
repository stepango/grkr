# Design: Gleam coding-agent swap (comment-classify + resolve_pr)

**Status**: Design-only; no product Gleam/shell behavior change in this PR.  
**Top-line verdict: GO** — honor the same `GRKR_CODING_AGENT` contract as the shell bridge at the three remaining hardcoded Codex exec sites, with small slices and default-codex parity.  
**Reference tip**: origin/main docs @ **caef425** (docs #206 checkpoint-json NO-GO after #205 @ b3c614f); product tip **851bed2** / PR #203 (issue_shared concern-split FINAL).  
**Parent design**: [`docs/design-swappable-coding-agent.md`](design-swappable-coding-agent.md) §Follow-ups item 1.  
**Kanban**: t_2c485c25  
**Date**: 2026-07-23  
**Design agent**: Grok Build CLI `model=grok-4.5` (`--mode design` / agent `plan`)

---

## 0. Verdict

| Decision | **GO** |
|----------|--------|
| Product action (later implement cards) | Make Gleam comment-classify + PR-conflict resolve select `codex` \| `grok` via the same env matrix as `bin/lib/issue_shared_coding_agent.sh`. |
| Why GO | Shell issue path already swappable; Gleam direct-exec is the documented gap; three bounded call sites; default/unset must remain codex-identical. |
| This card | **Docs only** — write this design; lightly cross-link parent. No `src/` / `bin/` product edits. |
| Slice 1 (one implement card) | Shared Gleam agent-exec helper + wire **both** near-identical comment-classify modules. |
| Slice 2 | Wire `resolve_pr/codex.gleam` + fail-string / log policy + tests. |

---

## 1. Goal / non-goals

### Goal

Gleam paths that **directly exec** a coding agent honor:

| Item | Contract |
|------|----------|
| Selector | `GRKR_CODING_AGENT=codex\|grok` (alias `CODING_AGENT`) |
| Default | `codex` when unset |
| Optional per-step | **New** step keys `comment` / `resolve` via `GRKR_AGENT_COMMENT` / `GRKR_AGENT_RESOLVE` → fall back to global → `codex` |
| Grok argv | Headless parity with shell bridge (`--prompt-file`, `--cwd`, `-m`, `--yolo`, `--permission-mode bypassPermissions`, `--max-turns`, `--output-format plain`, `--no-memory`, `GROK_ARGS`) |
| Codex default path | **No intentional behavior change** when agent unset/`codex` |

### Non-goals (this workstream)

- No shell issue-path rewrite (`issue_shared_coding_agent.sh` stays source of truth for decision/implement/remediate).
- No artifact dir rename `codex/…parts` → `agent/`.
- No third backend (`claude` / custom argv template).
- No Linear mutate change.
- No behavior change when agent unset or `codex`.
- No Hermes product edits.
- No checkpoint-json reopen (NO-GO stands at caef425 / `docs/design-checkpoint-json-gleam.md`).
- No large rename churn of `*_codex.gleam` modules or public `run_codex_classify` / `resolve_conflicts` (aliases OK).
- Design card: **docs only**.

---

## 2. Current contracts (live file facts)

### 2.1 `src/grkr/resolve_pr/codex.gleam` (~134 LOC)

| Concern | Live fact |
|---------|-----------|
| Bin | `const codex_bin = "codex"` (L10) |
| Argv | `[codex_bin, "exec", "--full-auto", prompt]` — **prompt as argv** (L23) |
| Stdin | empty string `""` (L25) |
| Timeout | **none** |
| Sandbox | **none** (unlike shell: `--sandbox workspace-write`) |
| Parse | split `\n\n` → content+explanation; else `\n---\n`; else whole stdout as content + `"No explanation provided"` (L57–85) |
| Errors | `"Failed to parse Codex response: …"` (L29); `"Codex command failed: …"` (L32); inner `"Command failed with exit code N"` (L119–120) |
| Types | `types.CodexResolution` / `CodexSkipped` / `CodexFailed` (names stay; cosmetic) |
| Public API | `resolve_conflicts`, `validate_resolution` |
| Caller | `src/grkr/resolve_pr/apply.gleam` → `codex.resolve_conflicts` |
| FFI | `@external(javascript, "../resolve_pr/exec.mjs", "executable")` — `execFileSync`, stdin string, no cwd option today |
| Tests | `test/grkr/resolve_pr/codex_test.gleam` — **validate_resolution only** (no exec/argv tests) |

### 2.2 Comment twins (~87 LOC each)

**Files (near byte-twins):**

- `src/grkr/workflow/handle_comment_codex.gleam`
- `src/grkr/supervisor/comment_handler_codex.gleam`

| Concern | Live fact |
|---------|-----------|
| Bin | `let codex_bin = "codex"` (L20) |
| Timeout | optional `timeout 120` if `which timeout` exit 0 (L22–25) |
| Argv (timeout) | `timeout` + `["120", "codex", "exec", "--sandbox", "workspace-write"]` (L28) |
| Argv (no timeout) | `"codex"` + `["exec", "--sandbox", "workspace-write"]` (L29) |
| Prompt | **stdin** via `Some(prompt)` (L32–35, L37) |
| Success | exit 0 → stdout (L38) |
| Fail | stdout+stderr + synthetic `CLASS: refuse` / `REPLY: Codex invocation failed or timed out for command: …` / `CHANGES: N/A` (L39–40) |
| Logs | `"   building codex prompt (len=…)"` (L18); `"   codex raw output (truncated): …"` (L44) |
| Parse | `parse_codex_output` → CLASS / REPLY / CHANGES; default class `answer-only` (L48–60) |
| Public API | `run_codex_classify`, `parse_codex_output` |
| Callers | `handle_comment.gleam` L64–66; `comment_handler.gleam` L63–65 |
| FFI | `grkr/workflow/ffi.executable` → `worktree_ffi.mjs` `executable` |

**Delta vs shell issue bridge (comment path):** shell always uses prompt **file** + out file + `--full-auto` + `--cd workdir`; Gleam comment uses stdin + optional timeout + sandbox, no `--full-auto`, no `--cd`.

**Delta vs shell (resolve path):** Gleam resolve uses prompt-as-argv + `--full-auto`, no sandbox, no timeout, no workdir flag.

### 2.3 Shell bridge (parity source of truth)

**File:** `bin/lib/issue_shared_coding_agent.sh`

| Piece | Contract |
|-------|----------|
| Steps | `decision` \| `implement` \| `remediate` \| `default` |
| Name resolve | step override → `GRKR_CODING_AGENT` / `CODING_AGENT` → `codex` (`_grkr_coding_agent_name`, L13–33) |
| Codex | `${CODEX_BIN:-codex} exec --sandbox workspace-write --full-auto ${CODEX_ARGS} ${CODEX_EXTRA_ARGS} --cd workdir <prompt_file` |
| Grok | `${GROK_BIN:-~/.grok/bin/grok\|grok} --prompt-file --cwd -m ${GROK_MODEL:-grok-build} --yolo --permission-mode bypassPermissions --max-turns ${GROK_MAX_TURNS:-60} --output-format plain --no-memory ${GROK_ARGS}` |
| Auth | load `XAI_API_KEY` from `~/.hermes/.env` when unset (L76–88) |
| Log | `Running coding agent ($agent/$step) to $phase_label...` |
| Unknown agent | stderr + return 2 |

### 2.4 Doctor (global only)

**File:** `src/grkr/doctor/validate.gleam`

- `coding_agent_name()`: `GRKR_CODING_AGENT` → `CODING_AGENT` → config.sh → `codex` (L126–134)
- `validate_coding_agent()`: validates **only selected global** agent (L184–196)
- Does **not** walk per-step overrides (same as shell doctor policy)

**Config template** (`doctor/config_parse.gleam` default config): documents `GRKR_AGENT_{DECISION,IMPLEMENT,REMEDIATE}` only today — later implement may add commented `GRKR_AGENT_COMMENT` / `GRKR_AGENT_RESOLVE` lines (optional, slice 2 or docs-only follow-up).

---

## 3. Env / step matrix

### 3.1 Global (parity)

| Env | Role | Default |
|-----|------|---------|
| `GRKR_CODING_AGENT` | global backend | `codex` |
| `CODING_AGENT` | alias if GRKR unset | — |
| `CODEX_BIN` | codex binary | `codex` |
| `CODEX_ARGS` | extra codex args (word-split on shell; Gleam: best-effort split or pass-through list if simple) | empty |
| `CODEX_EXTRA_ARGS` | e.g. `--skip-git-repo-check` | empty |
| `GROK_BIN` | grok binary | PATH `grok` or `~/.grok/bin/grok` |
| `GROK_MODEL` | model | **`grok-build`** (shell parity first) |
| `GROK_MAX_TURNS` | max turns | `60` |
| `GROK_ARGS` | extra grok flags | empty |
| `XAI_API_KEY` | grok auth | env; optional load from `~/.hermes/.env` if unset (**match shell**) |

**Model policy:** prefer **parity with shell bridge** (`GROK_MODEL` default `grok-build`). Optional later slice to align default to product `grok-4.5` in **both** shell + Gleam together — out of scope here.

### 3.2 Per-step: **new keys `comment` and `resolve`** (recommended)

| Step key | Env override | Used by |
|----------|--------------|---------|
| `comment` | `GRKR_AGENT_COMMENT` (optional legacy `GRKR_CODING_AGENT_COMMENT`) | handle_comment + comment_handler classify |
| `resolve` | `GRKR_AGENT_RESOLVE` (optional legacy `GRKR_CODING_AGENT_RESOLVE`) | resolve_pr conflict resolve |
| (existing) `decision` / `implement` / `remediate` | unchanged | shell issue path only |

**Precedence (match shell):**  
`GRKR_AGENT_<STEP>` → `GRKR_CODING_AGENT` / `CODING_AGENT` → `codex`.

### 3.3 Why not overload `decision` / `implement`

| Reason | Detail |
|--------|--------|
| Semantic mismatch | Comment classify is triage/reply, not implement-or-refuse gate. Conflict resolve is merge surgery, not issue implement. |
| Operator intent | Users may want `implement=grok` but keep fast/local `comment=codex` (or reverse). Overloading forces coupling. |
| Shell phase map | `_grkr_coding_step_from_phase` only maps decision/implement/remediate phrases; comment/resolve never flow through that bridge today. |
| Blast radius | New keys are additive; existing issue-path env matrix untouched. |
| Doctor | Still validates **global** only (same as shell). Per-step overrides are operator footguns already accepted for decision/implement; no new doctor requirement. |

---

## 4. Shared Gleam surface vs thin per-module change

### 4.1 Recommendation: one small helper module

**Path:** `src/grkr/coding_agent.gleam`  
(Alternative acceptable: `src/grkr/agent/exec.gleam` — prefer top-level `coding_agent` to mirror shell module name and avoid deep package churn.)

**ROI:** Positive. Comment twins duplicate ~25 LOC of exec wiring; resolve is a third variant. One helper owns name resolution + argv assembly + exec + temp prompt file lifecycle. Prompt assembly + response parse stay in existing `*_codex.gleam` modules.

### 4.2 API sketch

```gleam
/// src/grkr/coding_agent.gleam

pub type Step {
  Comment
  Resolve
  // Future: Default only if needed; do not add Decision/Implement here
  // (those remain shell-owned).
}

pub type Agent {
  Codex
  Grok
}

pub type RunMode {
  /// Comment classify today: optional timeout 120, sandbox workspace-write,
  /// prompt on stdin for Codex; Grok uses --prompt-file.
  Classify
  /// PR resolve today: --full-auto, prompt-as-argv for Codex (preserve);
  /// Grok uses --prompt-file. No timeout wrapper unless added carefully.
  ConflictResolve
}

pub type ExecOutcome {
  ExecOk(stdout: String)
  ExecFailed(exit_code: Int, stdout: String, stderr: String)
}

/// step override → GRKR_CODING_AGENT / CODING_AGENT → codex
pub fn agent_name(step: Step) -> Agent

/// Build argv + optional stdin; run via injected runner (testability).
pub fn run(
  step: Step,
  mode: RunMode,
  prompt: String,
  workdir: String,
  exec: fn(String, List(String), option.Option(String)) -> ExecOutcome,
) -> ExecOutcome
```

**FFI strategy (keep small):**

| Consumer | Exec | Temp file for Grok prompt |
|----------|------|---------------------------|
| Comment modules | existing `workflow/ffi.executable` | `workflow/ffi.tl_temp_path` + `tl_write_text` + `tl_unlink_file` (already on workflow ffi) |
| resolve_pr | existing `resolve_pr/exec.mjs` `executable` | `resolve_pr/runtime.write_file` + small temp path helper (add `temp_path` to `resolve_pr/fs.mjs` **or** pass path from coding_agent via tiny shared mjs) |

Prefer **injecting** the exec function from callers so `coding_agent.gleam` stays pure-enough and unit-testable without spinning real binaries. Avoid a mega shared FFI package in slice 1.

**Optional thin JS helper** only if word-splitting `CODEX_ARGS`/`GROK_ARGS` is painful in Gleam: e.g. `coding_agent_ffi.mjs` with `split_args(s) -> List(String)` — keep ≤30 LOC.

### 4.3 Stable public names

| Module | Keep | Notes |
|--------|------|-------|
| `handle_comment_codex` / `comment_handler_codex` | `run_codex_classify`, `parse_codex_output` | Internally call `coding_agent.run(Comment, Classify, …)`. Optional alias `run_agent_classify`. |
| `resolve_pr/codex` | `resolve_conflicts`, `validate_resolution` | Internally call helper. Types `CodexResolution` stay (rename later optional). |
| Parse / prompts | stay in place | No prompt content rewrite per backend (parent non-goal). |

### 4.4 Backend argv (target)

#### Classify (`Comment` + `Classify`) — headless only

**Codex (preserve today's shape when selected):**

```text
[timeout 120]?  ${CODEX_BIN:-codex} exec --sandbox workspace-write
  + CODEX_ARGS + CODEX_EXTRA_ARGS
stdin: prompt
```

Do **not** add `--full-auto` on comment path in slice 1 (would be behavior change vs today). Optional later alignment with shell is a separate card.

**Grok:**

```text
[timeout 120]?  ${GROK_BIN} \
  --prompt-file <tmp> --cwd <workdir> -m ${GROK_MODEL:-grok-build} \
  --yolo --permission-mode bypassPermissions \
  --max-turns ${GROK_MAX_TURNS:-60} --output-format plain --no-memory \
  ${GROK_ARGS}
stdin: none
```

- Write prompt to temp via `tl_temp_path("grkr-agent-prompt.")` + `tl_write_text`; unlink best-effort after exec.
- `workdir`: comment worktree dir if callers have it; else `pwd` / `GRKR_ROOT` — **pass explicitly from caller** (both comment handlers have worktree context nearby; today classify only receives `branch` string — slice 1 should thread `workdir` from `worktree_info.dir` into `run_codex_classify` **or** read `CURRENT_ISSUE_WORKTREE` / cwd). Prefer threading `workdir` for clarity (small signature extension: `run_codex_classify(ctx, branch, workdir)` or overload with workdir only).

#### Conflict-resolve (`Resolve` + `ConflictResolve`) — headless only

**Codex (preserve today's shape):**

```text
${CODEX_BIN:-codex} exec --full-auto ${CODEX_ARGS} ${CODEX_EXTRA_ARGS} <prompt-as-argv>
stdin: empty
```

No timeout wrapper (preserve). No sandbox flag (preserve). Adding shell-like sandbox/`--cd` is **out of scope** unless proven necessary (would change sandbox posture).

**Grok:**

```text
${GROK_BIN} --prompt-file <tmp> --cwd <workdir> -m ${GROK_MODEL:-grok-build} \
  --yolo --permission-mode bypassPermissions --max-turns … \
  --output-format plain --no-memory ${GROK_ARGS}
```

- Prompt must move from argv → temp file for Grok (Codex keeps argv for parity with today).
- `workdir`: resolve_pr worktree path from workflow context (`WorktreeContext.worktree_path`) — thread into `resolve_conflicts` or per-file resolve.

### 4.5 Log strings

| Today | Target when agent-aware |
|-------|-------------------------|
| `building codex prompt` | Prefer **neutral** always: `building coding-agent prompt` to avoid dual greps. |
| `codex raw output` | `coding-agent raw output` |
| resolve errors `Codex command failed` | See §5 |

Smoke tests today grep shell issue-path logs, not these Gleam strings — low blast radius. Still document greps in verify recipe.

---

## 5. Fail-path parity

### 5.1 Comment classify

| Condition | Today | Target |
|-----------|-------|--------|
| Non-zero exit / timeout | synthetic CLASS:refuse + REPLY `Codex invocation failed or timed out for command: …` | Same structure; REPLY text: prefer **`Coding agent invocation failed or timed out…`** (generalize). Keep substring `"invocation failed or timed out"` stable. In-repo: no test greps this string today. |
| Missing bin | non-zero from exec → same refuse path | same |
| Unknown agent name | N/A (hardcoded) | treat as fail → same synthetic refuse (do not crash supervisor); optionally log unknown agent once |
| Parse miss | default class `answer-only` | unchanged |

### 5.2 resolve_pr

| Condition | Today | Target |
|-----------|-------|--------|
| Non-zero exit | `Error("Codex command failed: " <> err)` | **Generalize carefully** to `Error("Coding agent command failed: " <> err)` — only `validate_resolution` unit-tested; no assert on error prefix. |
| Parse | currently always Ok with fallback whole stdout | unchanged |
| Empty resolved | validate error | unchanged |
| Conflict markers remain | validate error | unchanged |

**Compatibility choice:** Generalize user-visible `"Codex …"` → `"Coding agent …"` in Gleam fail strings. Do **not** keep lying `"Codex"` when backend is Grok. Accept minor string churn; no shell test depends on it.

### 5.3 XAI_API_KEY / missing grok

- Match shell: if `XAI_API_KEY` unset, best-effort read `~/.hermes/.env` (small ffi or exec `grep` — prefer tiny ffi read in coding_agent helper's mjs).
- Missing grok binary → non-zero exec → existing fail paths (comment refuse / resolve Error). Doctor already fails startup when global agent is grok and missing — runtime still must not crash the process.

---

## 6. Slice table

| Slice | Scope | Acceptance | Est. risk |
|-------|-------|------------|-----------|
| **0 (this card)** | `docs/design-gleam-coding-agent-swap.md` + parent follow-up one-liner | Design complete vs acceptance; PR open; no product code | none |
| **1 (one implement card)** | Add `src/grkr/coding_agent.gleam` (+ minimal ffi if needed); wire **both** `handle_comment_codex.gleam` and `comment_handler_codex.gleam`; thread workdir; Grok temp prompt file; env matrix for step `comment` | See bullets below | low |
| **2** | Wire `resolve_pr/codex.gleam`; temp prompt for Grok; step `resolve`; generalize error strings; unit tests for `agent_name` + argv shape (mock exec) | See bullets below | low–med |
| **3 (optional docs/config)** | spec/05 + config template comments for `GRKR_AGENT_COMMENT` / `GRKR_AGENT_RESOLVE`; parent design checkbox; README one-liner if user-facing | docs accuracy | none |
| **4 (optional)** | Align `GROK_MODEL` default shell+Gleam to `grok-4.5` together | explicit separate card | policy |

### Slice 1 acceptance (implement card)

- [x] `coding_agent.agent_name(Comment)` respects `GRKR_AGENT_COMMENT` → `GRKR_CODING_AGENT`/`CODING_AGENT` → `codex`.
- [x] Both comment modules call shared helper; still export `run_codex_classify` / `parse_codex_output`.
- [x] `GRKR_CODING_AGENT` unset/`codex`: argv+stdin+timeout+sandbox **identical** to today (no `--full-auto` added).
- [x] `GRKR_CODING_AGENT=grok`: headless grok argv with `--prompt-file`, shell-aligned flags; prompt not on argv; temp file cleaned up.
- [x] Non-zero/timeout → synthetic CLASS:refuse + REPLY containing `invocation failed or timed out`.
- [x] `gleam build` + `gleam test` green.
- [x] No shell issue-path edits; no resolve_pr behavior change in this slice.
- [x] Files stay ≤1000 LOC.

**Slice 1 status (t_45efd0d1):** landed in product PR (this implement card).

### Slice 2 acceptance

- [ ] `resolve_conflicts` uses helper with step `Resolve`.
- [ ] Codex path: still `exec --full-auto` + prompt argv + empty stdin (parity).
- [ ] Grok path: `--prompt-file` + headless flags; parse surface unchanged.
- [ ] Fail strings say `Coding agent` not hardcoded `Codex` (or dual-mention); tests updated if any.
- [ ] Unit tests: agent selection + classify/resolve argv construction with fake exec.
- [ ] `gleam build` / `gleam test`; `test/worker-resolve-pr.sh` if applicable still green under default codex.

---

## 7. Doctor / config / docs pointer (later implement)

| Item | Action |
|------|--------|
| Doctor | **No change required** for per-step comment/resolve (validates global only — same as shell). |
| `spec/parts/05-configuration.md` | On slice 1 or 3: document `GRKR_AGENT_COMMENT` / `GRKR_AGENT_RESOLVE`; note Gleam comment+resolve honor global agent. |
| `spec/parts/14` / `15` | Optional wording: "coding agent" instead of only "Codex" when implement lands. |
| Parent `design-swappable-coding-agent.md` | Follow-up item 1 → point at this file; checkbox when slices land. |
| Config template | Comment lines for new overrides (slice 3). |
| README | Only on functional slice if natural one-line under coding-agent section. |
| Tests | Gleam unit tests for name+argv; no mandatory new npm shell unless resolve worker smoke needs grok mock. |
| Greps | If log strings change: search `building codex prompt` / `codex raw output` in repo tests (expect few/none). |

---

## 8. Verify recipe (later implement)

```bash
# Build / unit
gleam build
gleam test

# Shell regression (default codex — no behavior change expected)
npm test
# or focused:
test/grkr-coding-agent-swap.sh   # shell bridge still green
test/grkr-smoke.sh
test/worker-resolve-pr.sh
test/worker-help.sh

# Optional greps after log string edits
rg -n "building codex prompt|codex raw output|Codex invocation failed|Codex command failed" \
  test src || true

# Manual grok (if installed)
GRKR_CODING_AGENT=grok # + worker-handle-comment / resolve path
```

Design-only card verify:

- [x] This file exists and covers all 8 acceptance themes.
- [x] Parent design follow-up points here.
- [x] No product `src/` / `bin/` diffs.
- [ ] Design PR open against main (kanban t_2c485c25).

---

## 9. Cross-links

- Parent: [`docs/design-swappable-coding-agent.md`](design-swappable-coding-agent.md)
- Shell bridge: `bin/lib/issue_shared_coding_agent.sh`
- Spec: `spec/parts/05-configuration.md`, resolve PR (14), comment commands (15)
- Call sites: `handle_comment_codex.gleam`, `comment_handler_codex.gleam`, `resolve_pr/codex.gleam`
- Doctor: `src/grkr/doctor/validate.gleam` (`coding_agent_name`, `validate_coding_agent`)

### Critical files for implementation

- `docs/design-gleam-coding-agent-swap.md` — this design (slice 0)
- `docs/design-swappable-coding-agent.md` — parent follow-up pointer
- `src/grkr/coding_agent.gleam` — **new** shared helper (slice 1)
- `src/grkr/workflow/handle_comment_codex.gleam` + `src/grkr/supervisor/comment_handler_codex.gleam` — twin classify sites (slice 1)
- `src/grkr/resolve_pr/codex.gleam` — conflict-resolve site (slice 2)
- `bin/lib/issue_shared_coding_agent.sh` — env/argv parity reference (do not rewrite)
