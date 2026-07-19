# Coding agent matrix — 20260719-043447

- LIVE=1 QUICK=0 TIMEOUT=240s
- probes: codex=auth_fail grok=ok
- Bridge: `run_codex_prompt` + per-step `GRKR_AGENT_{DECISION,IMPLEMENT,REMEDIATE}`

## Which evals matter for your projects

| Eval | Fit for grkr/forma/neon | Why |
|------|-------------------------|-----|
| SWE-bench Verified/Pro | Weak direct | Real GH issues, but noisy/contaminated; harness ≠ grkr |
| Terminal-Bench | Medium | CLI/agent competence in shell |
| Aider polyglot | Medium | Multi-lang edit quality |
| lm-eval (MMLU/HumanEval) | Poor | Exam scores, not issue workflow |
| **grkr stage matrix (this)** | **Best** | Same production bridge; mix CLIs per step |

## Results

| config | task | decision/implement/remediate | score | secs | rc | note |
|--------|------|------------------------------|------:|-----:|---:|------|
| mock-all-codex | decision_proceed | codex/codex/codex | 1 | 1s | 0 | proceed_detected |
| mock-all-codex | decision_refuse | codex/codex/codex | 1 | 0s | 0 | refuse_detected |
| mock-all-codex | implement_add_file | codex/codex/codex | 1 | 0s | 0 | result_ok |
| mock-all-codex | remediate_split | codex/codex/codex | 1 | 0s | 0 | big_sh_lines=2 |
| mock-all-grok | decision_proceed | grok/grok/grok | 1 | 0s | 0 | proceed_detected |
| mock-all-grok | decision_refuse | grok/grok/grok | 1 | 0s | 0 | refuse_detected |
| mock-all-grok | implement_add_file | grok/grok/grok | 1 | 0s | 0 | result_ok |
| mock-all-grok | remediate_split | grok/grok/grok | 1 | 0s | 0 | big_sh_lines=2 |
| mock-dec-grok-impl-codex | decision_proceed | grok/codex/codex | 1 | 0s | 0 | proceed_detected |
| mock-dec-grok-impl-codex | decision_refuse | grok/codex/codex | 1 | 0s | 0 | refuse_detected |
| mock-dec-grok-impl-codex | implement_add_file | grok/codex/codex | 1 | 1s | 0 | result_ok |
| mock-dec-grok-impl-codex | remediate_split | grok/codex/codex | 1 | 0s | 0 | big_sh_lines=2 |
| mock-dec-codex-impl-grok | decision_proceed | codex/grok/grok | 1 | 0s | 0 | proceed_detected |
| mock-dec-codex-impl-grok | decision_refuse | codex/grok/grok | 1 | 0s | 0 | refuse_detected |
| mock-dec-codex-impl-grok | implement_add_file | codex/grok/grok | 1 | 0s | 0 | result_ok |
| mock-dec-codex-impl-grok | remediate_split | codex/grok/grok | 1 | 0s | 0 | big_sh_lines=2 |
| mock-impl-grok-rem-codex | decision_proceed | codex/grok/codex | 1 | 0s | 0 | proceed_detected |
| mock-impl-grok-rem-codex | decision_refuse | codex/grok/codex | 1 | 1s | 0 | refuse_detected |
| mock-impl-grok-rem-codex | implement_add_file | codex/grok/codex | 1 | 0s | 0 | result_ok |
| mock-impl-grok-rem-codex | remediate_split | codex/grok/codex | 1 | 0s | 0 | big_sh_lines=2 |
| live-all-grok | decision_proceed | grok/grok/grok | 1 | 11s | 0 | proceed_detected |
| live-all-grok | decision_refuse | grok/grok/grok | 1 | 6s | 0 | refuse_detected |
| live-all-grok | implement_add_file | grok/grok/grok | 1 | 10s | 0 | result_ok |
| live-all-grok | remediate_split | grok/grok/grok | 1 | 70s | 0 | big_sh_lines=2 |

## Summary

- cells: 24  pass: 24  rate: 100.0%
- jsonl: `/Users/claw/work/grkr-v2-cron/.worktrees/coding-agent-eval-matrix/docs/eval-results/coding-agent-matrix-20260719-043447.jsonl`

## Ranked configs

| config | pass/total | avg_sec | fail_notes |
|--------|----------:|--------:|------------|
| mock-dec-codex-impl-grok | 4/4 | 0.0 | all_pass |
| mock-all-grok | 4/4 | 0.0 | all_pass |
| mock-impl-grok-rem-codex | 4/4 | 0.2 | all_pass |
| mock-dec-grok-impl-codex | 4/4 | 0.2 | all_pass |
| mock-all-codex | 4/4 | 0.2 | all_pass |
| live-all-grok | 4/4 | 24.2 | all_pass |

### How to pick for your projects

| Project | Stage | Prefer |
|---------|-------|--------|
| grkr | decision | highest refuse precision |
| grkr | implement | highest RESULT/test success |
| grkr | remediate | fastest correct shrink/split |
| forma / neon-gridlock | implement-like | same matrix idea with repo verify commands |

Per-step config example:

    GRKR_AGENT_DECISION=grok
    GRKR_AGENT_IMPLEMENT=codex   # after codex login
    GRKR_AGENT_REMEDIATE=grok

Codex auth_fail -> run `codex login` then re-run. Grok uses XAI_API_KEY from ~/.hermes/.env.

