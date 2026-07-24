//// coding_agent.gleam
//// Thin public facade (LOC hygiene split, t_e7ea2b4b).
//// Stable module: grkr/coding_agent
//// Delegates to coding_agent_{types,select,classify,run}. Zero intentional behavior change.
//// Type aliases keep annotations as coding_agent.X; constructors live on coding_agent_types
//// (import that module for Comment / Classify / ExecOk / etc. pattern matches).
//// Env/argv parity: bin/lib/issue_shared_coding_agent.sh + docs/design-gleam-coding-agent-swap.md

import gleam/option.{type Option}

import grkr/coding_agent_classify as classify
import grkr/coding_agent_run as run_mod
import grkr/coding_agent_select as select
import grkr/coding_agent_types as types

pub type Step = types.Step
pub type Agent = types.Agent
pub type RunMode = types.RunMode
pub type ExecOutcome = types.ExecOutcome
pub type Invocation = types.Invocation
pub type FsDeps = types.FsDeps
pub type ExecFn = types.ExecFn

// --- select ---
pub fn agent_name(step: Step) -> Result(Agent, String) {
  select.agent_name(step)
}

pub fn agent_name_from(
  get_env: fn(String) -> String,
  step: Step,
) -> Result(Agent, String) {
  select.agent_name_from(get_env, step)
}

// --- classify ---
pub fn classify_invocation(
  agent: Agent,
  prompt: String,
  workdir: String,
  get_env: fn(String) -> String,
  has_timeout: Bool,
  prompt_file: Option(String),
) -> Invocation {
  classify.classify_invocation(
    agent,
    prompt,
    workdir,
    get_env,
    has_timeout,
    prompt_file,
  )
}

// --- run ---
pub fn run(
  step: Step,
  mode: RunMode,
  prompt: String,
  workdir: String,
  get_env: fn(String) -> String,
  exec: ExecFn,
  fs: FsDeps,
) -> ExecOutcome {
  run_mod.run(step, mode, prompt, workdir, get_env, exec, fs)
}

pub fn run_with_defaults(
  step: Step,
  mode: RunMode,
  prompt: String,
  workdir: String,
  exec: ExecFn,
  fs: FsDeps,
) -> ExecOutcome {
  run_mod.run_with_defaults(step, mode, prompt, workdir, exec, fs)
}

pub fn classify_fail_reply(raw_cmd: String) -> String {
  run_mod.classify_fail_reply(raw_cmd)
}

pub fn classify_output(outcome: ExecOutcome, raw_cmd: String) -> String {
  run_mod.classify_output(outcome, raw_cmd)
}

pub fn agent_label(agent: Agent) -> String {
  run_mod.agent_label(agent)
}

pub fn format_cmd(bin: String, args: List(String)) -> String {
  run_mod.format_cmd(bin, args)
}

pub fn outcome_exit_code(outcome: ExecOutcome) -> Int {
  run_mod.outcome_exit_code(outcome)
}

pub fn int_env(
  get_env: fn(String) -> String,
  name: String,
  default: Int,
) -> Int {
  run_mod.int_env(get_env, name, default)
}
