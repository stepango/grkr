//// coding_agent_classify.gleam
//// Classify argv builders (LOC hygiene split, t_e7ea2b4b).
//// Zero behavior change; moved from monolithic coding_agent.gleam.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

import grkr/coding_agent_types.{
  type Agent, type Invocation, Codex, Grok, Invocation,
}

// --- FFI ---

@external(javascript, "./coding_agent_ffi.mjs", "split_args")
fn ffi_split_args(s: String) -> List(String)

@external(javascript, "./coding_agent_ffi.mjs", "default_grok_bin")
fn ffi_default_grok_bin() -> String

// --- Classify invocation builders (pure given deps) ---

/// Build classify argv for a known agent. Grok requires prompt_file path already written.
pub fn classify_invocation(
  agent: Agent,
  prompt: String,
  workdir: String,
  get_env: fn(String) -> String,
  has_timeout: Bool,
  prompt_file: Option(String),
) -> Invocation {
  case agent {
    Codex -> classify_codex(prompt, get_env, has_timeout)
    Grok ->
      case prompt_file {
        Some(path) -> classify_grok(path, workdir, get_env, has_timeout)
        None ->
          // Should not happen if caller wrote temp; fail-shaped empty cmd.
          Invocation(bin: "false", args: [], stdin: None)
      }
  }
}

pub fn classify_codex(
  prompt: String,
  get_env: fn(String) -> String,
  has_timeout: Bool,
) -> Invocation {
  let bin = case string.trim(get_env("CODEX_BIN")) {
    "" -> "codex"
    b -> b
  }
  let extra =
    list.append(
      ffi_split_args(get_env("CODEX_ARGS")),
      ffi_split_args(get_env("CODEX_EXTRA_ARGS")),
    )
  let base_args =
    list.append(["exec", "--sandbox", "workspace-write"], extra)
  case has_timeout {
    True ->
      Invocation(
        bin: "timeout",
        args: list.append(["120", bin], base_args),
        stdin: Some(prompt),
      )
    False -> Invocation(bin: bin, args: base_args, stdin: Some(prompt))
  }
}

pub fn classify_grok(
  prompt_file: String,
  workdir: String,
  get_env: fn(String) -> String,
  has_timeout: Bool,
) -> Invocation {
  let bin = case string.trim(get_env("GROK_BIN")) {
    "" -> ffi_default_grok_bin()
    b -> b
  }
  let model = case string.trim(get_env("GROK_MODEL")) {
    "" -> "grok-4.5"
    m -> m
  }
  let max_turns = case string.trim(get_env("GROK_MAX_TURNS")) {
    "" -> "60"
    t -> t
  }
  let grok_args = ffi_split_args(get_env("GROK_ARGS"))
  let base_args =
    list.append(
      [
        "--prompt-file",
        prompt_file,
        "--cwd",
        workdir,
        "-m",
        model,
        "--yolo",
        "--permission-mode",
        "bypassPermissions",
        "--max-turns",
        max_turns,
        "--output-format",
        "plain",
        "--no-memory",
      ],
      grok_args,
    )
  case has_timeout {
    True ->
      Invocation(
        bin: "timeout",
        args: list.append(["120", bin], base_args),
        stdin: None,
      )
    False -> Invocation(bin: bin, args: base_args, stdin: None)
  }
}
