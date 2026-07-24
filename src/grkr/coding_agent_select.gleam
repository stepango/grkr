//// coding_agent_select.gleam
//// Agent name resolution (LOC hygiene split, t_e7ea2b4b).
//// Zero behavior change; moved from monolithic coding_agent.gleam.

import gleam/string

import grkr/coding_agent_types.{type Agent, type Step, Codex, Comment, Grok, Resolve}

// --- FFI ---

@external(javascript, "./workflow/worktree_ffi.mjs", "get_env")
pub fn default_get_env(name: String) -> String

// --- Agent name ---

/// Production: read process env via workflow get_env.
pub fn agent_name(step: Step) -> Result(Agent, String) {
  agent_name_from(default_get_env, step)
}

/// Testable: inject env lookup. Precedence per step:
/// GRKR_AGENT_<STEP> → GRKR_CODING_AGENT_<STEP> (legacy) → GRKR_CODING_AGENT → CODING_AGENT → codex
pub fn agent_name_from(
  get_env: fn(String) -> String,
  step: Step,
) -> Result(Agent, String) {
  let raw = resolve_raw_name(get_env, step)
  case raw {
    "codex" -> Ok(Codex)
    "grok" -> Ok(Grok)
    other -> Error(other)
  }
}

fn resolve_raw_name(get_env: fn(String) -> String, step: Step) -> String {
  let step_raw = case step {
    Comment ->
      first_nonempty([
        get_env("GRKR_AGENT_COMMENT"),
        get_env("GRKR_CODING_AGENT_COMMENT"),
      ])
    Resolve ->
      first_nonempty([
        get_env("GRKR_AGENT_RESOLVE"),
        get_env("GRKR_CODING_AGENT_RESOLVE"),
      ])
  }
  let chosen = case step_raw {
    "" ->
      first_nonempty([get_env("GRKR_CODING_AGENT"), get_env("CODING_AGENT")])
    s -> s
  }
  case normalize_name(chosen) {
    "" -> "codex"
    n -> n
  }
}

fn first_nonempty(vals: List(String)) -> String {
  case vals {
    [] -> ""
    [h, ..t] ->
      case string.trim(h) {
        "" -> first_nonempty(t)
        s -> s
      }
  }
}

fn normalize_name(s: String) -> String {
  s
  |> string.lowercase
  |> string.trim
  |> string.replace(" ", "")
  |> string.replace("\t", "")
  |> string.replace("\n", "")
  |> string.replace("\r", "")
}
