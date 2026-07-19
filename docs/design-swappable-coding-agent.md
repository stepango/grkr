# Design: Swappable coding agent (Codex ↔ Grok)

**Status**: Slice 1 landed (issue path bridge + doctor + config/spec).  
**Date**: 2026-07-19  
**Tip base**: origin/main @ 745ca83  

## Goal

Make the coding LLM **easily swappable** between OpenAI **Codex** and xAI **Grok Build** without rewriting GitHub/Linear stage orchestration.

## Contract

| Item | Value |
|------|--------|
| Selector | `GRKR_CODING_AGENT=codex\|grok` (alias `CODING_AGENT`) |
| Default | `codex` |
| Bridge | `run_codex_prompt` (stable) = `run_coding_agent_prompt` in `bin/lib/issue_shared.sh` |
| Inputs | prompt file, workdir, phase label, output path, replace\|append |
| Outputs | stdout transcript + `persist_task_log_output` (unchanged) |
| Doctor | validates **only** the selected agent |

### Codex backend

```text
${CODEX_BIN:-codex} exec --full-auto ${CODEX_ARGS} --cd <workdir> < prompt > log
```

`CODEX_ARGS` (spec/05) is now actually applied.

### Grok backend

Headless flags aligned with Hermes `grok_build_exec.sh` implement path:

```text
${GROK_BIN:-grok|~/.grok/bin/grok} \
  --prompt-file <prompt> --cwd <workdir> -m ${GROK_MODEL:-grok-build} \
  --yolo --permission-mode bypassPermissions \
  --max-turns ${GROK_MAX_TURNS:-60} --output-format plain --no-memory \
  ${GROK_ARGS}
```

## What this slice covers

- Issue decision / implement / line-limit remediation (GitHub + Linear) via shared bridge
- Doctor + default config template + spec/02 + spec/05
- Test expectation strings for new log lines

## Follow-ups (not this PR)

1. **Gleam direct exec still hardcodes `codex`**:
   - `src/grkr/resolve_pr/codex.gleam` (PR conflict resolve)
   - `src/grkr/workflow/handle_comment.gleam` + `supervisor/comment_handler.gleam` (comment classify)
2. Optional rename of artifact dir `codex/implementation.log.parts/` → `agent/` (keep path stable or dual-write).
3. Optional third backend (`claude` / custom argv template via `GRKR_AGENT_CMD`).

## Non-goals

- No behavior change when `GRKR_CODING_AGENT` unset/codex
- No Linear live-mutate change
- No prompt content rewrite per backend (same prompts for both)

## Verify

- `gleam build` + `gleam test`
- `npm test` / regression shells (smoke, refusal, impl-to-refusal, line-limit, checkpoint-resume, branch-exists)
- Manual: `GRKR_CODING_AGENT=grok grkr --issue N` with Grok installed


## Per-step overrides (slice 2)

| Env | Step |
|-----|------|
| `GRKR_AGENT_DECISION` | decision gate |
| `GRKR_AGENT_IMPLEMENT` | implement |
| `GRKR_AGENT_REMEDIATE` | line-limit remediation |

Falls back to `GRKR_CODING_AGENT` then `codex`.

## Eval matrix

```bash
scripts/coding-agent-eval-matrix.sh            # mock + live (probed)
scripts/coding-agent-eval-matrix.sh --mock-only
```

Reports under `docs/eval-results/coding-agent-matrix-latest.md`.
